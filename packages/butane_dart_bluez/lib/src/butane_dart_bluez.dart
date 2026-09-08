import 'dart:async';
import 'dart:typed_data';

import 'package:bluez/bluez.dart';
import 'package:butane_dart/interface.dart';
import 'package:dbus/dbus.dart';

import 'advertising.dart';
import 'gatt_server.dart';

/// Linux implementation of `butane` backed by BlueZ over D-Bus.
///
/// Central role is backed by the `bluez` package. Peripheral role
/// (advertising + local GATT) is driven via raw D-Bus because the `bluez`
/// package does not wrap `LEAdvertisement1` / `GattManager1`.
base class ButaneDartBluez extends ButanePlatformInterface {
  ButaneDartBluez({BlueZClient? client}) : _client = client ?? BlueZClient();

  final BlueZClient _client;
  BlueZAdapter? _defaultAdapter;
  Future<void>? _connecting;
  bool _connected = false;

  /// True between [scan] and [cancelScan]. Gates [scanStream] emissions so
  /// they match CoreBluetooth's `stopScan` semantics — after cancel, no more
  /// ScanResults flow even though BlueZ keeps emitting PropertiesChanged for
  /// paired/connected devices.
  bool _scanning = false;

  /// Cache of BlueZDevice lookups keyed by MAC address. BlueZ's
  /// [BlueZClient.devices] is a flat list with no address index, so we
  /// memoize to avoid a linear scan on every connect/read/write call. The
  /// underlying BlueZDevice is a stable wrapper around a D-Bus object path —
  /// safe to cache for the lifetime of the client.
  final Map<String, BlueZDevice> _deviceCache = {};

  /// Separate system-bus client used for the peripheral role (advertising
  /// and local GATT objects). We keep this distinct from the `bluez`
  /// package's internal bus because we need to register our own objects
  /// on the bus, and the package does not expose its underlying
  /// [DBusClient]. Lazily created on first peripheral-role call.
  DBusClient? _peripheralBus;

  /// Adapter object path (e.g. `/org/bluez/hci0`). Looked up on demand by
  /// scanning BlueZ's managed objects for the first `Adapter1` interface.
  String? _adapterPath;

  /// Currently registered advertisement, or null when not advertising.
  /// BlueZ supports one advertisement per caller at a time under this API.
  LEAdvertisement? _advertisement;

  /// Monotonic counter used to mint unique advertisement object paths.
  /// `dbus` 0.2.5 has no `unregisterObject`, so re-advertising must use a
  /// fresh path to avoid "path already registered" errors. Old objects
  /// remain on the bus as no-ops — BlueZ stops talking to them after
  /// UnregisterAdvertisement.
  int _advertisementCounter = 0;

  /// Monotonic counter for GATT application paths. Same rationale as
  /// [_advertisementCounter] — fresh paths on re-registration avoid
  /// collisions with the now-orphaned prior tree.
  int _applicationCounter = 0;

  /// Monotonic request id issued for every incoming ATT read/write so
  /// the app can pair [AttRequest]s with `respondToRequest` calls.
  int _requestCounter = 0;

  /// Currently registered GATT application and its service tree, or null
  /// when no service has been added. BlueZ allows exactly one
  /// application per caller per adapter, so we rebuild the tree on each
  /// [addService].
  _GattApplicationRegistration? _application;

  /// Pending read/write requests awaiting a call to [respondToRequest].
  /// Keyed by the request id minted in the characteristic handler.
  final Map<int, Completer<({AttResult result, Uint8List? value})>>
      _pendingReads = {};
  final Map<int, Completer<AttResult>> _pendingWrites = {};

  /// Broadcast controllers for peripheral-manager event streams. Created
  /// lazily so tests / tooling that never touch the peripheral role
  /// don't allocate them.
  StreamController<({String serviceUuid, String? error})>?
      _serviceAddedController;
  StreamController<AttRequest>? _readRequestController;
  StreamController<List<AttRequest>>? _writeRequestsController;

  /// Service UUID filter set by [scan]. Empty means "match any". BlueZ's
  /// `SetDiscoveryFilter` with `UUIDs` is unreliable for late-arriving UUID
  /// data (scan responses, cached devices seeded from `_client.devices` before
  /// BlueZ has parsed their ads), so we mirror CoreBluetooth's
  /// `scanForPeripherals(withServices:)` semantics in Dart by filtering every
  /// emission in [scanStream] against this set.
  Set<String> _scanUuidFilter = const {};

  /// Device properties that warrant re-emitting a [ScanResult] when they
  /// change. Limited to advert-relevant fields so we don't spam on churn from
  /// GATT state (e.g. `ServicesResolved`).
  static const _advertRelevantProps = <String>{
    'RSSI',
    'ManufacturerData',
    'ServiceData',
    'UUIDs',
    'Alias',
    'Name',
    'TxPower',
  };

  Future<void> _ensureConnected() {
    if (_connected) return Future.value();
    return _connecting ??= () async {
      await _client.connect();
      _connected = true;
      final adapters = _client.adapters;
      if (adapters.isNotEmpty) {
        _defaultAdapter = adapters.first;
      }
    }();
  }

  // --- Central: adapter state -----------------------------------------------

  @override
  Future<ClientState> clientState([Session? session]) async {
    await _ensureConnected();
    final adapter = _defaultAdapter;
    if (adapter == null) return ClientState.unsupported;
    return adapter.powered ? ClientState.poweredOn : ClientState.poweredOff;
  }

  @override
  Stream<ClientState> clientStateStream([Session? session]) {
    late StreamController<ClientState> controller;
    StreamSubscription<List<String>>? sub;

    controller = StreamController<ClientState>(
      onListen: () async {
        await _ensureConnected();
        final adapter = _defaultAdapter;
        if (adapter == null) {
          controller.add(ClientState.unsupported);
          await controller.close();
          return;
        }
        // Seed with the current state.
        controller.add(
          adapter.powered ? ClientState.poweredOn : ClientState.poweredOff,
        );
        // Re-emit on Powered changes. We deliberately don't filter on the
        // property list — bluez_client batches multiple changes into one
        // event, and misfires are cheaper than missed transitions.
        sub = adapter.propertiesChangedStream.listen((changed) {
          if (changed.contains('Powered')) {
            controller.add(
              adapter.powered ? ClientState.poweredOn : ClientState.poweredOff,
            );
          }
        });
      },
      onCancel: () async {
        await sub?.cancel();
        sub = null;
      },
    );

    return controller.stream;
  }

  // --- Central: scanning ----------------------------------------------------

  @override
  Future<void> scan({
    Iterable<String>? forServices,
    Session? session,
  }) async {
    // Set _scanUuidFilter SYNCHRONOUSLY before any awaits. The porcelain
    // layer subscribes to [scanStream] before calling [scan] (see
    // PlatformStreamController.stream getter → createStream listen →
    // outer controller onListen_ → platform.scan), and the async bodies
    // of the two are racing. If we set _scanUuidFilter after an await,
    // [scanStream.onListen] can run first with the stale/empty filter
    // and emit false-positive seed results.
    _scanUuidFilter = forServices == null
        ? const {}
        : {for (final u in forServices) u.toLowerCase()};

    await _ensureConnected();
    final adapter = _defaultAdapter;
    if (adapter == null) {
      throw StateError('No BlueZ adapter available');
    }

    // Purge stale cached devices that match our filter. BlueZ's
    // `device.uuids` is cumulative — any service UUID ever seen for a MAC
    // stays cached. macOS/iOS peripherals rotate their random address per
    // advertising session, so cache entries from prior runs linger with our
    // test service UUID attached to MACs that are no longer advertising
    // (or advertising something else). Without this purge,
    // `PropertiesChanged(RSSI)` on those stale entries — which BlueZ fires
    // whenever it picks up a nearby advert with the same MAC — feeds stale
    // devices into our emission path via [_matchesScanFilter]'s cumulative
    // UUID check, and the caller tries to connect to a dead address.
    //
    // Removing via adapter.RemoveDevice also clears any stuck Device1 DBus
    // registration behind the "Unable to register device interface" errors
    // seen in journalctl (bluez#1157-style collisions), letting BlueZ
    // register a fresh object when the address re-appears.
    //
    // Targeted: only purge non-connected devices that match the filter,
    // so unrelated cached peers stay intact.
    if (_scanUuidFilter.isNotEmpty) {
      for (final device in List<BlueZDevice>.from(_client.devices)) {
        if (device.connected) continue;
        if (!_matchesScanFilter(device)) continue;
        // Best-effort: if removeDevice fails (e.g. device already gone)
        // the next scan will still pick up a fresh advert.
        try {
          await adapter.removeDevice(device);
        } catch (_) {}
      }
    }

    // BlueZ's SetDiscoveryFilter expects a{sv} — each value is a variant.
    //
    // We only set `Transport: le` (no `UUIDs`). BlueZ's `UUIDs` filter silently
    // excludes devices whose service UUIDs haven't yet arrived via scan
    // response or PropertiesChanged — which is exactly the case for freshly
    // advertising peripherals, and also for devices already in the BlueZ
    // cache. Client-side filtering in [scanStream] (via [_scanUuidFilter])
    // handles this correctly.
    final filter = <String, DBusValue>{
      'Transport': DBusVariant(const DBusString('le')),
    };

    // If discovery is already running (because a prior cancelScan left it
    // going — see [cancelScan] for why), stop it first so SetDiscoveryFilter
    // can apply the new filter cleanly. BlueZ requires filter updates to
    // happen while discovery is stopped.
    if (adapter.discovering) {
      await adapter.stopDiscovery();
    }
    await adapter.setDiscoveryFilter(filter);
    await adapter.startDiscovery();
    _scanning = true;
  }

  /// True when [device] should be emitted under the current scan filter.
  ///
  /// Mirrors `CBCentralManager.scanForPeripherals(withServices:)`: an empty
  /// filter matches any device, otherwise the device's advertised UUIDs must
  /// intersect the requested set. BlueZ reports UUIDs lowercase; we compare
  /// case-insensitively against the stored filter.
  bool _matchesScanFilter(BlueZDevice device) {
    if (_scanUuidFilter.isEmpty) return true;
    for (final uuid in device.uuids) {
      if (_scanUuidFilter.contains(uuid.id.toLowerCase())) return true;
    }
    return false;
  }

  @override
  Stream<ScanResult> scanStream([Session? session]) {
    late StreamController<ScanResult> controller;
    final subs = <StreamSubscription<Object?>>[];

    // Live emissions (deviceAdded / PropertiesChanged) are gated on
    // _scanning so cancelScan() halts output, matching CoreBluetooth's
    // stopScan semantics. The initial seed is NOT gated — it's the
    // snapshot of BlueZ's current cache at subscribe time, and racing it
    // against scan() would randomly drop entries depending on when the
    // async onListen body runs vs. when scan() flips the flag.
    void live(BlueZDevice device) {
      if (!_scanning) return;
      if (!_matchesScanFilter(device)) return;
      if (!controller.isClosed) controller.add(_toScanResult(device));
    }

    void watchDevice(BlueZDevice device) {
      subs.add(
        device.propertiesChangedStream.listen((changed) {
          // A late `UUIDs` update may flip a previously-unmatched device into
          // the filter — live() re-checks, so no extra handling needed here.
          if (changed.any(_advertRelevantProps.contains)) live(device);
        }),
      );
    }

    controller = StreamController<ScanResult>.broadcast(
      onListen: () async {
        await _ensureConnected();
        if (_defaultAdapter == null) {
          await controller.close();
          return;
        }
        // Do NOT seed from cache. CoreBluetooth's `scanForPeripherals`
        // only reports peripherals that emit a fresh advert in the current
        // scan session; already-cached peers come from
        // `retrievePeripherals(withIdentifiers:)` instead. Seeding from
        // BlueZ's cumulative cache is both non-canonical AND unreliable:
        // BlueZ never drops stale UUIDs, so a `C4:EF:DA:...` entry from a
        // prior Mac Studio session still reports our test UUID long after
        // the peripheral has rotated its random address, and we'd emit a
        // dead address to the caller.
        //
        // We still subscribe [watchDevice] on cached entries so that IF
        // one of them re-advertises in the current session, the resulting
        // `PropertiesChanged` flows through [live]. Any stale cached
        // entries that match our filter were purged in [scan] above.
        for (final device in _client.devices) {
          watchDevice(device);
        }
        // New discoveries.
        subs.add(
          _client.deviceAddedStream.listen((device) {
            live(device);
            watchDevice(device);
          }),
        );
        // NOTE: deviceRemovedStream intentionally ignored — BlueZ removes
        // stale devices on its own schedule and the platform interface has
        // no "device disappeared" signal for scans.
      },
      onCancel: () async {
        for (final s in subs) {
          await s.cancel();
        }
        subs.clear();
      },
    );

    return controller.stream;
  }

  @override
  Future<void> cancelScan({Session? session}) async {
    _scanning = false;
    // Intentionally do NOT reset _scanUuidFilter here. [connect] uses it as
    // a fallback to select a GATT profile UUID when BlueZ's cached device
    // entry has no advertised UUIDs (e.g. because the cache predates the
    // ad, or was merged from a stale BR/EDR entry). Resetting breaks that
    // fallback when the caller stops discovery before calling connect.
    // The next scan() overwrites it with a fresh filter.
    //
    // Intentionally do NOT call adapter.stopDiscovery() here. BlueZ removes
    // devices with random addresses from its object tree shortly after
    // discovery stops (see bluez#214). macOS / iOS peripherals advertise with
    // rotating RPAs, so a scan→connect sequence that stops discovery between
    // the two steps races the cleanup — Connect/ConnectProfile then targets
    // a path that no longer exists and the call hangs until D-Bus reply
    // timeout.
    //
    // Leaving discovery running keeps the discovered RPA alive through the
    // connect handshake. The next scan() stops+restarts discovery so filter
    // changes still apply cleanly. Cost: continuous LE scanning until the
    // plugin shuts down — acceptable for this desktop-Linux plugin.
  }

  // --- Mapping helpers ------------------------------------------------------

  ScanResult _toScanResult(BlueZDevice device) {
    final session = PeripheralSession(peripheralIdentifier: device.address);
    // BlueZ vs CoreBluetooth naming mapping:
    //   device.alias  — user-editable friendly name → CBPeripheral.name
    //   device.name   — raw advertised local name   → CBAdvertisementDataLocalNameKey
    // BlueZ defaults alias to name when the user hasn't renamed the device,
    // so the two are usually equal anyway.
    return ScanResult(
      peripheral: Peripheral(
        session: session,
        state: device.connected
            ? ConnectionState.connected
            : ConnectionState.disconnected,
        name: device.alias.isNotEmpty ? device.alias : null,
        rssi: device.rssi,
      ),
      advertisementData: AdvertisementData(
        localName: device.name.isNotEmpty ? device.name : null,
        manufacturerData: _flattenManufacturerData(device.manufacturerData),
        serviceUuids: device.uuids.map((u) => u.id).toList(),
        serviceData: _mapServiceData(device.serviceData),
        txPowerLevel: device.txPower,
      ),
    );
  }

  /// Fold BlueZ's `Map<manufacturerId, payload>` into a single CoreBluetooth-
  /// compatible blob: `[id_lsb, id_msb, ...payload]` per entry, concatenated.
  ///
  /// Rationale: iOS emits `CBAdvertisementDataManufacturerDataKey` as raw
  /// `Data` where the first 2 bytes are the little-endian company ID followed
  /// by the manufacturer-specific payload. BlueZ separates the two. Preserving
  /// the iOS convention means app code written against iOS/macOS keeps
  /// working.
  Uint8List? _flattenManufacturerData(
    Map<BlueZManufacturerId, List<int>> data,
  ) {
    if (data.isEmpty) return null;
    final out = BytesBuilder();
    for (final entry in data.entries) {
      final id = entry.key.id;
      out.addByte(id & 0xff);
      out.addByte((id >> 8) & 0xff);
      out.add(entry.value);
    }
    return out.toBytes();
  }

  Map<String, Uint8List> _mapServiceData(Map<BlueZUUID, List<int>> data) {
    return {
      for (final entry in data.entries)
        entry.key.id: Uint8List.fromList(entry.value),
    };
  }

  // --- Central: connect + GATT ----------------------------------------------

  /// Resolve [address] (MAC) to a [BlueZDevice]. Returns null if BlueZ doesn't
  /// know the device — scanning must have seen it, or it must be paired.
  BlueZDevice? _findDevice(String address) {
    final cached = _deviceCache[address];
    if (cached != null) return cached;
    for (final device in _client.devices) {
      if (device.address == address) {
        _deviceCache[address] = device;
        return device;
      }
    }
    return null;
  }

  BlueZDevice _requireDevice(PeripheralSession session) {
    final device = _findDevice(session.peripheralIdentifier);
    if (device == null) {
      throw StateError(
        'Unknown peripheral ${session.peripheralIdentifier} — '
        'scan or pair the device first',
      );
    }
    return device;
  }

  BlueZGattService _requireService(BlueZDevice device, String serviceUuid) {
    final want = serviceUuid.toLowerCase();
    for (final svc in device.gattServices) {
      // BlueZUUID.toString() wraps the raw id in `BlueZUUID('...')` — use
      // `.id` for the bare UUID string. Same idiom as `_toScanResult`.
      if (svc.uuid.id.toLowerCase() == want) return svc;
    }
    throw StateError(
      'Service $serviceUuid not found on ${device.address} — '
      'call discoverServices() first',
    );
  }

  BlueZGattCharacteristic _requireCharacteristic(
    BlueZDevice device,
    String serviceUuid,
    String characteristicUuid,
  ) {
    final service = _requireService(device, serviceUuid);
    final want = characteristicUuid.toLowerCase();
    for (final char in service.gattCharacteristics) {
      if (char.uuid.id.toLowerCase() == want) return char;
    }
    throw StateError(
      'Characteristic $characteristicUuid not found in service '
      '$serviceUuid on ${device.address}',
    );
  }

  BlueZGattDescriptor _requireDescriptor(
    BlueZDevice device,
    String serviceUuid,
    String characteristicUuid,
    String descriptorUuid,
  ) {
    final characteristic =
        _requireCharacteristic(device, serviceUuid, characteristicUuid);
    final want = descriptorUuid.toLowerCase();
    for (final descriptor in characteristic.gattDescriptors) {
      if (descriptor.uuid.id.toLowerCase() == want) return descriptor;
    }
    throw StateError(
      'Descriptor $descriptorUuid not found in characteristic '
      '$characteristicUuid on ${device.address}',
    );
  }

  /// Resolve the D-Bus object path of a GATT characteristic. The `bluez`
  /// package hides `_BlueZObject.path` behind a private field, so we
  /// walk BlueZ's ObjectManager tree via our own system-bus client.
  ///
  /// BlueZ structures the tree as:
  ///   /org/bluez/hci0/dev_XX_XX/serviceNNNN/charNNNN
  /// We match by `org.bluez.GattCharacteristic1.UUID` property
  /// under any child of a path containing the device's MAC (with `:`→`_`).
  ///
  /// Results are cached for the lifetime of the connection since BlueZ
  /// assigns paths deterministically per device+service+char combination.
  final Map<String, DBusObjectPath> _charPathCache = {};

  Future<DBusObjectPath> _resolveCharacteristicPath(
    String deviceAddress,
    String serviceUuid,
    String characteristicUuid,
  ) async {
    final cacheKey =
        '${deviceAddress.toLowerCase()}/$serviceUuid/$characteristicUuid'
            .toLowerCase();
    final cached = _charPathCache[cacheKey];
    if (cached != null) return cached;

    final dict = await _managedObjects();
    // Device path fragment: MAC with colons → underscores (BlueZ convention).
    final macFragment = 'dev_${deviceAddress.replaceAll(':', '_')}';
    final wantSvc = serviceUuid.toLowerCase();
    final wantChar = characteristicUuid.toLowerCase();

    for (final entry in dict.children.entries) {
      final objPath = (entry.key as DBusObjectPath).value;
      if (!objPath.contains(macFragment)) continue;
      final ifaces = (entry.value as DBusDict).children;
      final charIface =
          ifaces[const DBusString('org.bluez.GattCharacteristic1')];
      if (charIface == null) continue;
      final props = (charIface as DBusDict).children;
      final uuidProp = props[const DBusString('UUID')];
      if (uuidProp == null) continue;
      final uuidVal =
          (uuidProp is DBusVariant ? uuidProp.value : uuidProp) as DBusString;
      if (uuidVal.value.toLowerCase() != wantChar) continue;

      // Verify the parent service UUID matches — two services could have
      // a characteristic with the same UUID (unlikely but spec-legal).
      final svcPath = objPath.substring(0, objPath.lastIndexOf('/'));
      final svcIfaces =
          (dict.children[DBusObjectPath(svcPath)] as DBusDict?)?.children;
      if (svcIfaces != null) {
        final svcIface = svcIfaces[const DBusString('org.bluez.GattService1')];
        if (svcIface != null) {
          final svcProps = (svcIface as DBusDict).children;
          final svcUuidProp = svcProps[const DBusString('UUID')];
          if (svcUuidProp != null) {
            final svcUuid = (svcUuidProp is DBusVariant
                ? svcUuidProp.value
                : svcUuidProp) as DBusString;
            if (svcUuid.value.toLowerCase() != wantSvc) continue;
          }
        }
      }

      final resolved = DBusObjectPath(objPath);
      _charPathCache[cacheKey] = resolved;
      return resolved;
    }
    throw StateError(
      'Could not resolve D-Bus path for characteristic '
      '$characteristicUuid (service $serviceUuid) on $deviceAddress',
    );
  }

  @override
  Future<Iterable<Peripheral>> peripherals({
    Iterable<String> peripheralIdentifiers = const [],
    Session? session,
  }) async {
    await _ensureConnected();
    final wanted = peripheralIdentifiers.toSet();
    final out = <Peripheral>[];
    for (final device in _client.devices) {
      if (wanted.isNotEmpty && !wanted.contains(device.address)) continue;
      out.add(_toPeripheral(device));
    }
    return out;
  }

  @override
  Future<Iterable<Peripheral>> connectedPeripherals({
    Iterable<String> serviceUuids = const [],
    Session? session,
  }) async {
    await _ensureConnected();
    final wanted = {for (final u in serviceUuids) u.toLowerCase()};
    final out = <Peripheral>[];
    for (final device in _client.devices) {
      if (!device.connected) continue;
      if (wanted.isNotEmpty) {
        final offered = device.uuids.map((u) => u.id.toLowerCase());
        if (!offered.any(wanted.contains)) continue;
      }
      out.add(_toPeripheral(device));
    }
    return out;
  }

  @override
  Future<void> connect({required PeripheralSession session}) async {
    await _ensureConnected();
    final device = _requireDevice(session);
    if (device.connected) return;

    // Use `Device1.Connect()` for all peers. For dual-mode public-address
    // peripherals (e.g. a Mac advertising over LE with the same address it
    // uses for BR/EDR) this relies on the controller being in LE-only mode
    // — `ControllerMode = le` in `/etc/bluetooth/main.conf`. Without that,
    // BlueZ 5.72's `select_conn_bearer` (src/device.c) breaks ties toward
    // BR/EDR when both bearers have similar timestamps, tries HFP/AVDTP
    // profiles, and never runs GATT primary service discovery. There is
    // no D-Bus-only workaround on 5.72 — `PreferredBearer` landed in 5.80+.
    // See packages/butane_bluez/README.md for the setup requirement.
    //
    // Fire-and-forget + error capture. We poll `device.connected` below
    // because the D-Bus reply can be delayed past the default timeout on
    // some peers, while the `Connected` property still flips promptly.
    Object? connectError;
    unawaited(() async {
      try {
        await device.connect();
      } catch (err) {
        connectError = err;
      }
    }());

    const pollInterval = Duration(milliseconds: 250);
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (!device.connected) {
      if (connectError != null) {
        throw StateError(
          'BlueZ Connect() failed for ${session.peripheralIdentifier}: '
          '$connectError',
        );
      }
      if (DateTime.now().isAfter(deadline)) {
        throw StateError(
          'BlueZ connect timed out for ${session.peripheralIdentifier}: '
          'device never became connected within 30s',
        );
      }
      await Future<void>.delayed(pollInterval);
    }
  }

  @override
  Future<void> cancelConnection({required PeripheralSession session}) async {
    await _ensureConnected();
    // Soft-fail if BlueZ no longer knows the device — CoreBluetooth's
    // cancelPeripheralConnection is a no-op on unknown peripherals.
    final device = _findDevice(session.peripheralIdentifier);
    if (device == null || !device.connected) return;
    await device.disconnect();
  }

  @override
  Future<ConnectionState> connectionState({
    required PeripheralSession session,
  }) async {
    await _ensureConnected();
    final device = _findDevice(session.peripheralIdentifier);
    if (device == null) return ConnectionState.disconnected;
    return device.connected
        ? ConnectionState.connected
        : ConnectionState.disconnected;
  }

  @override
  Stream<ConnectionState> connectionStateStream({
    required PeripheralSession session,
  }) {
    late StreamController<ConnectionState> controller;
    StreamSubscription<List<String>>? sub;

    controller = StreamController<ConnectionState>(
      onListen: () async {
        await _ensureConnected();
        final device = _findDevice(session.peripheralIdentifier);
        if (device == null) {
          controller.add(ConnectionState.disconnected);
          return;
        }
        controller.add(
          device.connected
              ? ConnectionState.connected
              : ConnectionState.disconnected,
        );
        // BlueZ exposes only a boolean `Connected` property — we can't
        // distinguish connecting/disconnecting transitional states the way
        // CoreBluetooth can. Emit connected/disconnected edges only.
        sub = device.propertiesChangedStream.listen((changed) {
          if (changed.contains('Connected')) {
            controller.add(
              device.connected
                  ? ConnectionState.connected
                  : ConnectionState.disconnected,
            );
          }
        });
      },
      onCancel: () async {
        await sub?.cancel();
        sub = null;
      },
    );

    return controller.stream;
  }

  @override
  Future<void> discoverServices({
    required PeripheralSession session,
    Iterable<String>? serviceUuids,
  }) async {
    await _ensureConnected();
    final device = _requireDevice(session);
    if (!device.connected) {
      throw StateError(
        'Cannot discover services on disconnected peripheral '
        '${session.peripheralIdentifier}',
      );
    }
    // BlueZ auto-resolves services on connect — wait for the
    // `ServicesResolved` property to become true. The `serviceUuids`
    // filter is advisory only; BlueZ resolves all services regardless
    // and we return them from [services()] where callers can filter.
    //
    // Poll instead of listening to PropertiesChanged: the `ServicesResolved`
    // edge can land before we subscribe, and the gattServices list also
    // needs the InterfacesAdded signals that the poll sees without special
    // handling.
    if (device.servicesResolved && device.gattServices.isNotEmpty) return;
    const pollInterval = Duration(milliseconds: 250);
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (!device.servicesResolved || device.gattServices.isEmpty) {
      if (DateTime.now().isAfter(deadline)) {
        throw TimeoutException(
          'BlueZ did not resolve services on '
          '${session.peripheralIdentifier} within 15 s',
        );
      }
      await Future<void>.delayed(pollInterval);
    }
  }

  @override
  Future<Iterable<Service>> services({
    required PeripheralSession session,
  }) async {
    await _ensureConnected();
    final device = _requireDevice(session);
    return [
      for (final svc in device.gattServices)
        Service(uuid: svc.uuid.id, isPrimary: svc.primary),
    ];
  }

  @override
  Future<void> discoverCharacteristics({
    required PeripheralSession session,
    required String serviceUuid,
    Iterable<String>? characteristicUuids,
  }) async {
    await _ensureConnected();
    final device = _requireDevice(session);
    final service = _requireService(device, serviceUuid);
    // BlueZ materializes characteristics as part of ServicesResolved.
    // However, the InterfacesAdded D-Bus signals for characteristic objects
    // may arrive slightly after ServicesResolved becomes true. Poll until
    // at least one characteristic appears (or timeout).
    if (service.gattCharacteristics.isNotEmpty) return;
    const pollInterval = Duration(milliseconds: 250);
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (service.gattCharacteristics.isEmpty) {
      if (DateTime.now().isAfter(deadline)) {
        throw TimeoutException(
          'No characteristics materialized for service $serviceUuid on '
          '${session.peripheralIdentifier} within 10 s',
        );
      }
      await Future<void>.delayed(pollInterval);
    }
  }

  @override
  Future<Iterable<Characteristic>> characteristics({
    required PeripheralSession session,
    required String serviceUuid,
  }) async {
    await _ensureConnected();
    final device = _requireDevice(session);
    final service = _requireService(device, serviceUuid);
    return [
      for (final char in service.gattCharacteristics)
        Characteristic(
          uuid: char.uuid.id,
          properties: _flagsToProperties(char.flags),
          descriptors: [
            for (final desc in char.gattDescriptors)
              Descriptor(uuid: desc.uuid.id),
          ],
        ),
    ];
  }

  Peripheral _toPeripheral(BlueZDevice device) {
    return Peripheral(
      session: PeripheralSession(peripheralIdentifier: device.address),
      state: device.connected
          ? ConnectionState.connected
          : ConnectionState.disconnected,
      name: device.alias.isNotEmpty ? device.alias : null,
      rssi: device.rssi,
    );
  }

  CharacteristicProperty _flagsToProperties(
    Set<BlueZGattCharacteristicFlag> flags,
  ) {
    return CharacteristicProperty(
      broadcast: flags.contains(BlueZGattCharacteristicFlag.broadcast),
      read: flags.contains(BlueZGattCharacteristicFlag.read),
      writeWithoutResponse:
          flags.contains(BlueZGattCharacteristicFlag.writeWithoutResponse),
      write: flags.contains(BlueZGattCharacteristicFlag.write),
      notify: flags.contains(BlueZGattCharacteristicFlag.notify),
      indicate: flags.contains(BlueZGattCharacteristicFlag.indicate),
      authenticatedSignedWrites:
          flags.contains(BlueZGattCharacteristicFlag.authenticatedSignedWrites),
      extendedProperties:
          flags.contains(BlueZGattCharacteristicFlag.extendedProperties),
      // BlueZ exposes `encrypt-authenticated-read/write` flags but no
      // matching enum distinguishing notify/indicate encryption — mirror
      // false to match the CoreBluetooth semantic.
      notifyEncryptionRequired: false,
      indicateEncryptionRequired: false,
    );
  }

  // --- Central: read/write/notify, RSSI --------------------------------------

  @override
  Future<Uint8List> readCharacteristic({
    required PeripheralSession session,
    required String serviceUuid,
    required String characteristicUuid,
  }) async {
    await _ensureConnected();
    final device = _requireDevice(session);
    final char =
        _requireCharacteristic(device, serviceUuid, characteristicUuid);
    final bytes = await char.readValue();
    return Uint8List.fromList(bytes.toList());
  }

  @override
  Future<void> writeCharacteristic({
    required PeripheralSession session,
    required String serviceUuid,
    required String characteristicUuid,
    required Uint8List value,
    bool withoutResponse = false,
  }) async {
    await _ensureConnected();
    // Call WriteValue via raw D-Bus because the bluez 0.1.4 package's
    // writeValue builds the options dict with unwrapped values
    // (DBusString instead of DBusVariant(DBusString)), causing
    // "Provided value don't match signature" from the dbus package.
    final charPath = await _resolveCharacteristicPath(
      session.peripheralIdentifier,
      serviceUuid,
      characteristicUuid,
    );
    final bus = await _ensurePeripheralBus();
    final result = await bus.callMethod(
      destination: 'org.bluez',
      path: charPath,
      interface: 'org.bluez.GattCharacteristic1',
      member: 'WriteValue',
      values: [
        DBusArray(DBusSignature('y'), value.map(DBusByte.new)),
        DBusDict(DBusSignature('s'), DBusSignature('v'), {
          const DBusString('type'): DBusVariant(
            DBusString(withoutResponse ? 'command' : 'request'),
          ),
        }),
      ],
    );
    if (result is DBusMethodErrorResponse) {
      throw StateError(
        'BlueZ WriteValue failed on $charPath: '
        '${result.errorName} ${result.values}',
      );
    }
  }

  @override
  Future<Uint8List> readDescriptor({
    required PeripheralSession session,
    required String serviceUuid,
    required String characteristicUuid,
    required String descriptorUuid,
  }) async {
    await _ensureConnected();
    final device = _requireDevice(session);
    final descriptor = _requireDescriptor(
      device,
      serviceUuid,
      characteristicUuid,
      descriptorUuid,
    );
    final bytes = await descriptor.readValue();
    return Uint8List.fromList(bytes.toList());
  }

  @override
  Future<void> writeDescriptor({
    required PeripheralSession session,
    required String serviceUuid,
    required String characteristicUuid,
    required String descriptorUuid,
    required Uint8List value,
  }) async {
    await _ensureConnected();
    final device = _requireDevice(session);
    final descriptor = _requireDescriptor(
      device,
      serviceUuid,
      characteristicUuid,
      descriptorUuid,
    );
    await descriptor.writeValue(value);
  }

  @override
  Future<void> observeCharacteristic({
    required PeripheralSession session,
    required String serviceUuid,
    required String characteristicUuid,
    bool observe = true,
  }) async {
    await _ensureConnected();
    _requireDevice(session);
    // The bluez 0.1.4 package does not expose StartNotify/StopNotify
    // (it TODO'd them as "require fd manipulation"). Call via raw D-Bus.
    final charPath = await _resolveCharacteristicPath(
      session.peripheralIdentifier,
      serviceUuid,
      characteristicUuid,
    );
    final bus = await _ensurePeripheralBus();
    final method = observe ? 'StartNotify' : 'StopNotify';
    final result = await bus.callMethod(
      destination: 'org.bluez',
      path: charPath,
      interface: 'org.bluez.GattCharacteristic1',
      member: method,
    );
    if (result is DBusMethodErrorResponse) {
      throw StateError(
        'BlueZ $method failed on $charPath: '
        '${result.errorName} ${result.values}',
      );
    }
  }

  @override
  Stream<Uint8List> characteristicValueStream({
    required PeripheralSession session,
    required String serviceUuid,
    required String characteristicUuid,
  }) {
    // Subscribe to PropertiesChanged on the characteristic's D-Bus path.
    // BlueZ emits `org.freedesktop.DBus.Properties.PropertiesChanged`
    // with the interface name + changed property map whenever the Value
    // property is updated by a notification or indication.
    late StreamController<Uint8List> controller;
    StreamSubscription<DBusSignal>? sub;

    controller = StreamController<Uint8List>(
      onListen: () async {
        await _ensureConnected();
        final charPath = await _resolveCharacteristicPath(
          session.peripheralIdentifier,
          serviceUuid,
          characteristicUuid,
        );
        final bus = await _ensurePeripheralBus();
        sub = bus
            .subscribeSignals(
          sender: 'org.bluez',
          interface: 'org.freedesktop.DBus.Properties',
          member: 'PropertiesChanged',
          path: charPath,
        )
            .listen((signal) {
          // PropertiesChanged args: (interface_name: s, changed: a{sv},
          //                          invalidated: as)
          if (signal.values.length < 2) return;
          final ifaceName = (signal.values[0] as DBusString).value;
          if (ifaceName != 'org.bluez.GattCharacteristic1') return;
          final changed = (signal.values[1] as DBusDict).children;
          final valueProp = changed[const DBusString('Value')];
          if (valueProp == null) return;
          final inner = valueProp is DBusVariant ? valueProp.value : valueProp;
          if (inner is! DBusArray) return;
          final bytes = Uint8List.fromList(
            inner.children.map((v) => (v as DBusByte).value).toList(),
          );
          if (!controller.isClosed) controller.add(bytes);
        });
      },
      onCancel: () async {
        await sub?.cancel();
        sub = null;
      },
    );

    return controller.stream;
  }

  @override
  Future<int> readRssi({required PeripheralSession session}) async {
    await _ensureConnected();
    final device = _requireDevice(session);
    // BlueZ updates the RSSI property periodically while connected.
    // If the device isn't connected or BlueZ hasn't published an RSSI
    // update yet, the cached value may be 0 — match CoreBluetooth
    // semantics (which also returns the last known value).
    return device.rssi;
  }

  @override
  Future<int> requestMtu({
    required PeripheralSession session,
    required int mtu,
  }) async {
    try {
      // BlueZ owns ATT negotiation and exposes no client-side target-MTU
      // request. Waiting for service resolution ensures its characteristic
      // objects, including their negotiated MTU properties, are available.
      await discoverServices(session: session);
      final managedObjects = await _managedObjects();
      final devicePathFragment =
          'dev_${session.peripheralIdentifier.replaceAll(':', '_')}'
              .toLowerCase();

      for (final entry in managedObjects.children.entries) {
        final objectPath = (entry.key as DBusObjectPath).value.toLowerCase();
        if (!objectPath.contains(devicePathFragment)) continue;
        final interfaces = (entry.value as DBusDict).children;
        final characteristic =
            interfaces[const DBusString('org.bluez.GattCharacteristic1')];
        if (characteristic is! DBusDict) continue;
        final mtuProperty = characteristic.children[const DBusString('MTU')];
        final mtuValue =
            mtuProperty is DBusVariant ? mtuProperty.value : mtuProperty;
        if (mtuValue is DBusUint16 && mtuValue.value > 0) {
          return mtuValue.value;
        }
      }
    } catch (_) {
      // Normalize lookup, D-Bus, and malformed-property failures to the same
      // platform-facing contract below.
    }
    throw StateError(
      'BlueZ did not publish a negotiated ATT MTU for '
      '${session.peripheralIdentifier}',
    );
  }

  // --- Peripheral: advertising ----------------------------------------------

  Future<DBusClient> _ensurePeripheralBus() async {
    var bus = _peripheralBus;
    if (bus != null) return bus;
    bus = DBusClient.system();
    _peripheralBus = bus;
    return bus;
  }

  Future<DBusDict> _managedObjects() async {
    final bus = await _ensurePeripheralBus();
    final result = await bus.callMethod(
      destination: 'org.bluez',
      path: DBusObjectPath('/'),
      interface: 'org.freedesktop.DBus.ObjectManager',
      member: 'GetManagedObjects',
    );
    if (result is! DBusMethodSuccessResponse ||
        result.returnValues.isEmpty ||
        result.returnValues.first is! DBusDict) {
      throw StateError('BlueZ GetManagedObjects returned no data');
    }
    return result.returnValues.first as DBusDict;
  }

  /// Walk BlueZ's ObjectManager tree to find the first object that
  /// implements `org.bluez.Adapter1`. BlueZAdapter doesn't expose its
  /// D-Bus path publicly in 0.1.4 and we can't reuse the bluez package's
  /// internal client, so we do the lookup ourselves.
  Future<String> _ensureAdapterPath() async {
    final cached = _adapterPath;
    if (cached != null) return cached;
    final dict = await _managedObjects();
    for (final entry in dict.children.entries) {
      final interfaces = entry.value as DBusDict;
      for (final ifaceKey in interfaces.children.keys) {
        if ((ifaceKey as DBusString).value == 'org.bluez.Adapter1') {
          final pathValue = (entry.key as DBusObjectPath).value;
          _adapterPath = pathValue;
          return pathValue;
        }
      }
    }
    throw StateError('No BlueZ adapter found on the system bus');
  }

  @override
  Future<ClientState> peripheralManagerState([
    PeripheralManagerSession? session,
  ]) async {
    // Peripheral and central roles share the same adapter; the adapter's
    // powered state is what gates either role's ability to operate.
    return clientState();
  }

  @override
  Stream<ClientState> peripheralManagerStateStream([
    PeripheralManagerSession? session,
  ]) {
    // Same reasoning as [peripheralManagerState]: adapter state is the
    // ground truth. The stream is forwarded verbatim from the central
    // side so subscribers get identical semantics (seed + edges).
    return clientStateStream();
  }

  @override
  Future<void> startAdvertising({
    PeripheralManagerSession? session,
    String? localName,
    Iterable<String>? serviceUuids,
  }) async {
    await _ensureConnected();
    final bus = await _ensurePeripheralBus();
    final adapterPath = await _ensureAdapterPath();

    // CoreBluetooth replaces the advertisement on repeated starts; match
    // that here by tearing down any existing advertisement first. The
    // caller doesn't need to pair start/stop.
    if (_advertisement != null) {
      await stopAdvertising(session: session);
    }

    final path = DBusObjectPath(
      '/com/nicospencer/butane/advertisement${++_advertisementCounter}',
    );
    final advert = LEAdvertisement(
      objectPath: path,
      localName: localName,
      serviceUuids: [for (final u in serviceUuids ?? const <String>[]) u],
    );
    bus.registerObject(advert);

    try {
      final result = await bus.callMethod(
        destination: 'org.bluez',
        path: DBusObjectPath(adapterPath),
        interface: 'org.bluez.LEAdvertisingManager1',
        member: 'RegisterAdvertisement',
        values: [
          path,
          DBusDict(
            DBusSignature('s'),
            DBusSignature('v'),
            const <DBusValue, DBusValue>{},
          ),
        ],
      );
      if (result is DBusMethodErrorResponse) {
        throw StateError(
          'BlueZ RegisterAdvertisement failed: '
          '${result.errorName} ${result.values}',
        );
      }
    } catch (_) {
      // Leave the DBusObject registered (no unregisterObject in dbus
      // 0.2.5) but drop our reference so callers can retry with a fresh
      // path. BlueZ never saw the object in this case, so it's inert.
      _advertisement = null;
      rethrow;
    }
    _advertisement = advert;
  }

  @override
  Future<void> stopAdvertising({PeripheralManagerSession? session}) async {
    final advert = _advertisement;
    if (advert == null) return;
    _advertisement = null;

    final bus = _peripheralBus;
    final adapterPath = _adapterPath;
    if (bus == null || adapterPath == null) return;

    // UnregisterAdvertisement can fail if BlueZ already dropped the
    // advertisement (e.g. adapter powered off). We've already cleared our
    // side, so treat any error response as best-effort cleanup rather
    // than propagating.
    await bus.callMethod(
      destination: 'org.bluez',
      path: DBusObjectPath(adapterPath),
      interface: 'org.bluez.LEAdvertisingManager1',
      member: 'UnregisterAdvertisement',
      values: [advert.path],
    );
  }

  // --- Peripheral: local GATT services --------------------------------------

  StreamController<({String serviceUuid, String? error})>
      _ensureServiceAddedController() => _serviceAddedController ??=
          StreamController<({String serviceUuid, String? error})>.broadcast();

  StreamController<AttRequest> _ensureReadRequestController() =>
      _readRequestController ??= StreamController<AttRequest>.broadcast();

  StreamController<List<AttRequest>> _ensureWriteRequestsController() =>
      _writeRequestsController ??=
          StreamController<List<AttRequest>>.broadcast();

  @override
  Future<void> addService({
    PeripheralManagerSession? session,
    required MutableService service,
  }) async {
    await _ensureConnected();
    final bus = await _ensurePeripheralBus();
    final adapterPath = await _ensureAdapterPath();

    // BlueZ locks the GATT tree after RegisterApplication — we can't
    // just append a service. Tear down and rebuild: serialize the
    // existing services + the new one into a fresh application tree.
    final priorServices = _application?.services ?? const <MutableService>[];
    final merged = <MutableService>[
      ...priorServices
          .where((s) => s.uuid.toLowerCase() != service.uuid.toLowerCase()),
      service,
    ];
    await _rebuildApplication(bus, adapterPath, merged);

    // Emit on serviceAddedStream to match CoreBluetooth's callback model.
    _ensureServiceAddedController()
        .add((serviceUuid: service.uuid, error: null));
  }

  @override
  Stream<({String serviceUuid, String? error})> serviceAddedStream([
    PeripheralManagerSession? session,
  ]) =>
      _ensureServiceAddedController().stream;

  @override
  Future<void> removeService({
    PeripheralManagerSession? session,
    required String serviceUuid,
  }) async {
    final current = _application?.services ?? const <MutableService>[];
    final remaining = current
        .where((s) => s.uuid.toLowerCase() != serviceUuid.toLowerCase())
        .toList();
    if (remaining.length == current.length) return;
    if (remaining.isEmpty) {
      await _unregisterApplication();
      return;
    }
    final bus = await _ensurePeripheralBus();
    final adapterPath = await _ensureAdapterPath();
    await _rebuildApplication(bus, adapterPath, remaining);
  }

  @override
  Future<void> removeAllServices({PeripheralManagerSession? session}) async {
    await _unregisterApplication();
  }

  Future<void> _unregisterApplication() async {
    final app = _application;
    if (app == null) return;
    _application = null;
    final bus = _peripheralBus;
    final adapterPath = _adapterPath;
    if (bus == null || adapterPath == null) return;
    await bus.callMethod(
      destination: 'org.bluez',
      path: DBusObjectPath(adapterPath),
      interface: 'org.bluez.GattManager1',
      member: 'UnregisterApplication',
      values: [app.rootPath],
    );
    // DBusObject children stay registered on our bus (no
    // unregisterObject in dbus 0.2.5), but the app counter guarantees
    // any future registration uses a fresh path.
  }

  Future<void> _rebuildApplication(
    DBusClient bus,
    String adapterPath,
    List<MutableService> services,
  ) async {
    // Unregister the prior application on BlueZ's side first. Paths for
    // the new tree are fresh, so no collision — but leaving the old
    // application registered would leave BlueZ advertising stale GATT
    // metadata.
    await _unregisterApplication();

    final appRoot =
        DBusObjectPath('/com/nicospencer/butane/app${++_applicationCounter}');
    final app = GattApplication(appRoot);
    bus.registerObject(app);

    final registered = <MutableService>[];
    final delegate = _GattDelegate(this);
    var serviceIndex = 0;
    for (final svc in services) {
      final servicePath =
          DBusObjectPath('${appRoot.value}/service$serviceIndex');
      final serviceObj = GattService(
        objectPath: servicePath,
        uuid: svc.uuid,
        isPrimary: svc.isPrimary,
      );
      app.addChild(serviceObj);
      bus.registerObject(serviceObj);

      var charIndex = 0;
      for (final char in svc.characteristics) {
        final charPath = DBusObjectPath('${servicePath.value}/char$charIndex');
        final charObj = GattCharacteristic(
          objectPath: charPath,
          servicePath: servicePath,
          uuid: char.uuid,
          serviceUuid: svc.uuid,
          flags: flagsFromCharacteristicProperty(char.properties),
          delegate: delegate,
          initialValue: char.value,
        );
        app.addChild(charObj);
        bus.registerObject(charObj);
        delegate.registerCharacteristic(svc.uuid, char.uuid, charObj);

        var descIndex = 0;
        for (final desc in char.descriptors ?? const <MutableDescriptor>[]) {
          final descPath = DBusObjectPath('${charPath.value}/desc$descIndex');
          final descObj = GattDescriptor(
            objectPath: descPath,
            characteristicPath: charPath,
            uuid: desc.uuid,
            value: desc.value,
          );
          app.addChild(descObj);
          bus.registerObject(descObj);
          descIndex++;
        }
        charIndex++;
      }
      registered.add(svc);
      serviceIndex++;
    }

    _application = _GattApplicationRegistration(
      root: app,
      rootPath: appRoot,
      services: registered,
      delegate: delegate,
    );

    final result = await bus.callMethod(
      destination: 'org.bluez',
      path: DBusObjectPath(adapterPath),
      interface: 'org.bluez.GattManager1',
      member: 'RegisterApplication',
      values: [
        appRoot,
        DBusDict(
          DBusSignature('s'),
          DBusSignature('v'),
          const <DBusValue, DBusValue>{},
        ),
      ],
    );
    if (result is DBusMethodErrorResponse) {
      _application = null;
      throw StateError(
        'BlueZ RegisterApplication failed: '
        '${result.errorName} ${result.values}',
      );
    }
  }

  @override
  Future<void> respondToRequest({
    PeripheralManagerSession? session,
    required int requestId,
    required AttResult result,
    Uint8List? value,
  }) async {
    final read = _pendingReads.remove(requestId);
    if (read != null) {
      read.complete((result: result, value: value));
      return;
    }
    final write = _pendingWrites.remove(requestId);
    if (write != null) {
      write.complete(result);
      return;
    }
    // Unknown request id — silently ignore rather than throwing, since
    // CoreBluetooth tolerates stale respondToRequest calls (e.g.
    // central disconnects mid-read).
  }

  @override
  Future<bool> updateValue({
    PeripheralManagerSession? session,
    required String serviceUuid,
    required String characteristicUuid,
    required Uint8List value,
  }) async {
    final app = _application;
    if (app == null) return false;
    final char =
        app.delegate.findCharacteristic(serviceUuid, characteristicUuid);
    if (char == null) return false;
    // Mirror CoreBluetooth's return: true iff anyone is subscribed. We
    // always update the cached Value; BlueZ only pushes a notification
    // when `notifying` is true (see GattCharacteristic.setValue).
    final delivered = char.notifying;
    char.setValue(value);
    return delivered;
  }

  @override
  Stream<AttRequest> readRequestStream([
    PeripheralManagerSession? session,
  ]) =>
      _ensureReadRequestController().stream;

  @override
  Stream<List<AttRequest>> writeRequestsStream([
    PeripheralManagerSession? session,
  ]) =>
      _ensureWriteRequestsController().stream;
}

/// Snapshot of the currently registered GATT application so we can
/// rebuild / tear it down on subsequent add/remove calls.
class _GattApplicationRegistration {
  _GattApplicationRegistration({
    required this.root,
    required this.rootPath,
    required this.services,
    required this.delegate,
  });

  final GattApplication root;
  final DBusObjectPath rootPath;
  final List<MutableService> services;
  final _GattDelegate delegate;
}

/// Bridges [GattCharacteristic] D-Bus callbacks back to the
/// [ButaneDartBluez] streams + pending-request maps.
class _GattDelegate implements GattServerDelegate {
  _GattDelegate(this._plugin);

  final ButaneDartBluez _plugin;

  /// Characteristic lookup: `<serviceUuid>/<characteristicUuid>` →
  /// object. UUIDs lowercased so lookups are case-insensitive.
  final Map<String, GattCharacteristic> _characteristics = {};

  void registerCharacteristic(
    String serviceUuid,
    String characteristicUuid,
    GattCharacteristic char,
  ) {
    _characteristics[_key(serviceUuid, characteristicUuid)] = char;
  }

  GattCharacteristic? findCharacteristic(
    String serviceUuid,
    String characteristicUuid,
  ) =>
      _characteristics[_key(serviceUuid, characteristicUuid)];

  String _key(String s, String c) => '${s.toLowerCase()}/${c.toLowerCase()}';

  @override
  int allocateRequestId() => ++_plugin._requestCounter;

  @override
  Future<({AttResult result, Uint8List? value})> onReadRequest(
    AttRequest request,
  ) {
    final completer = Completer<({AttResult result, Uint8List? value})>();
    _plugin._pendingReads[request.requestId] = completer;
    _plugin._ensureReadRequestController().add(request);
    return completer.future;
  }

  @override
  Future<AttResult> onWriteRequest(AttRequest request) {
    final completer = Completer<AttResult>();
    _plugin._pendingWrites[request.requestId] = completer;
    // CoreBluetooth delivers writes as a batch (a single central can
    // queue multiple within one ATT MTU). BlueZ hands us one at a time
    // over D-Bus — emit single-element batches so listeners don't have
    // to special-case either shape.
    _plugin._ensureWriteRequestsController().add([request]);
    return completer.future;
  }

  @override
  void onNotifyingChanged(String characteristicUuid, bool notifying) {
    // No-op for now. The plugin tracks notifying state via
    // GattCharacteristic.notifying directly; this hook exists so future
    // work (e.g. per-characteristic subscribe/unsubscribe streams) has
    // somewhere to land without another round of interface churn.
  }
}
