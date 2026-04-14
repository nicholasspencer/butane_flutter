import 'dart:async';
import 'dart:typed_data';

import 'package:bluez/bluez.dart';
import 'package:butane_platform_interface/butane_platform_interface.dart';
import 'package:dbus/dbus.dart';

/// Linux implementation of `butane` backed by BlueZ over D-Bus.
///
/// Central-role scaffolding. Peripheral-role methods remain
/// `UnimplementedError` stubs and are filled in by [butane_flutter-8h5.6] and
/// [butane_flutter-8h5.7].
base class ButaneBluez extends ButanePlatformInterface {
  ButaneBluez({BlueZClient? client}) : _client = client ?? BlueZClient();

  static late ButaneBluez instance;

  final BlueZClient _client;
  BlueZAdapter? _defaultAdapter;
  bool _connected = false;

  /// Per-device subscriptions held by an active [scanStream].
  ///
  /// Keyed by `BlueZDevice` object identity — every time we see a new device
  /// via [BlueZClient.deviceAddedStream] (or the initial snapshot) we attach a
  /// listener to its `propertiesChangedStream` so RSSI / advert-data updates
  /// re-emit. The map is drained in the controller's `onCancel`.
  static const _advertRelevantProps = <String>{
    'RSSI',
    'ManufacturerData',
    'ServiceData',
    'UUIDs',
    'Alias',
    'Name',
    'TxPower',
  };

  static void registerWith() {
    instance = ButaneBluez();
    ButanePlatformInterface.instance = instance;
  }

  Future<void> _ensureConnected() async {
    if (_connected) return;
    await _client.connect();
    _connected = true;
    final adapters = _client.adapters;
    if (adapters.isNotEmpty) {
      _defaultAdapter = adapters.first;
    }
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
              adapter.powered
                  ? ClientState.poweredOn
                  : ClientState.poweredOff,
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
    await _ensureConnected();
    final adapter = _defaultAdapter;
    if (adapter == null) {
      throw StateError('No BlueZ adapter available');
    }

    // BlueZ's SetDiscoveryFilter expects a{sv} — each value is a variant.
    final filter = <String, DBusValue>{
      // Match CoreBluetooth semantics: LE only, no Classic BR/EDR.
      'Transport': DBusVariant(const DBusString('le')),
    };
    if (forServices != null && forServices.isNotEmpty) {
      filter['UUIDs'] = DBusVariant(
        DBusArray(
          DBusSignature('s'),
          forServices.map<DBusValue>(DBusString.new).toList(),
        ),
      );
    }

    await adapter.setDiscoveryFilter(filter);
    if (!adapter.discovering) {
      await adapter.startDiscovery();
    }
  }

  @override
  Stream<ScanResult> scanStream([Session? session]) {
    late StreamController<ScanResult> controller;
    final subs = <StreamSubscription<Object?>>[];

    void watchDevice(BlueZDevice device) {
      // Emit a fresh snapshot whenever an advert-relevant property changes.
      subs.add(
        device.propertiesChangedStream.listen((changed) {
          if (changed.any(_advertRelevantProps.contains)) {
            if (!controller.isClosed) controller.add(_toScanResult(device));
          }
        }),
      );
    }

    controller = StreamController<ScanResult>(
      onListen: () async {
        await _ensureConnected();
        if (_defaultAdapter == null) {
          await controller.close();
          return;
        }
        // Seed with devices BlueZ already knows about (e.g. paired or
        // previously-discovered). The app is expected to dedupe on
        // `peripheralIdentifier` if it doesn't want them.
        for (final device in _client.devices) {
          controller.add(_toScanResult(device));
          watchDevice(device);
        }
        // New discoveries.
        subs.add(
          _client.deviceAddedStream.listen((device) {
            if (!controller.isClosed) controller.add(_toScanResult(device));
            watchDevice(device);
          }),
        );
        // NOTE: deviceRemovedStream intentionally ignored — BlueZ removes
        // stale devices on its own schedule and the platform interface has
        // no "device disappeared" signal for scans. Subscriptions leak until
        // scan cancel; acceptable given typical scan durations.
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
    final adapter = _defaultAdapter;
    if (adapter != null && adapter.discovering) {
      await adapter.stopDiscovery();
    }
  }

  // --- Mapping helpers ------------------------------------------------------

  ScanResult _toScanResult(BlueZDevice device) {
    final session = PeripheralSession(peripheralIdentifier: device.address);
    return ScanResult(
      peripheral: Peripheral(
        session: session,
        state: device.connected
            ? ConnectionState.connected
            : ConnectionState.disconnected,
        name: device.name.isNotEmpty ? device.name : null,
        rssi: device.rssi,
      ),
      advertisementData: AdvertisementData(
        localName: device.alias.isNotEmpty ? device.alias : null,
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

  // --- Unimplemented: Central: connect, GATT, RSSI ---------------------------

  @override
  Future<Iterable<Peripheral>> peripherals({
    Iterable<String> peripheralIdentifiers = const [],
    Session? session,
  }) async =>
      throw UnimplementedError();

  @override
  Future<Iterable<Peripheral>> connectedPeripherals({
    Iterable<String> serviceUuids = const [],
    Session? session,
  }) async =>
      throw UnimplementedError();

  @override
  Future<void> connect({required PeripheralSession session}) async =>
      throw UnimplementedError();

  @override
  Future<void> cancelConnection({required PeripheralSession session}) async =>
      throw UnimplementedError();

  @override
  Future<ConnectionState> connectionState({
    required PeripheralSession session,
  }) async =>
      throw UnimplementedError();

  @override
  Stream<ConnectionState> connectionStateStream({
    required PeripheralSession session,
  }) async* {
    throw UnimplementedError();
  }

  @override
  Future<void> discoverServices({
    required PeripheralSession session,
    Iterable<String>? serviceUuids,
  }) async =>
      throw UnimplementedError();

  @override
  Future<Iterable<Service>> services({
    required PeripheralSession session,
  }) async =>
      throw UnimplementedError();

  @override
  Future<void> discoverCharacteristics({
    required PeripheralSession session,
    required String serviceUuid,
    Iterable<String>? characteristicUuids,
  }) async =>
      throw UnimplementedError();

  @override
  Future<Iterable<Characteristic>> characteristics({
    required PeripheralSession session,
    required String serviceUuid,
  }) async =>
      throw UnimplementedError();

  @override
  Future<Uint8List> readCharacteristic({
    required PeripheralSession session,
    required String serviceUuid,
    required String characteristicUuid,
  }) async =>
      throw UnimplementedError();

  @override
  Future<void> writeCharacteristic({
    required PeripheralSession session,
    required String serviceUuid,
    required String characteristicUuid,
    required Uint8List value,
    bool withoutResponse = false,
  }) async =>
      throw UnimplementedError();

  @override
  Future<void> observeCharacteristic({
    required PeripheralSession session,
    required String serviceUuid,
    required String characteristicUuid,
    bool observe = true,
  }) async =>
      throw UnimplementedError();

  @override
  Stream<Uint8List> characteristicValueStream({
    required PeripheralSession session,
    required String serviceUuid,
    required String characteristicUuid,
  }) async* {
    throw UnimplementedError();
  }

  @override
  Future<int> readRssi({required PeripheralSession session}) async =>
      throw UnimplementedError();

  // --- Unimplemented: Peripheral role (8h5.6 / 8h5.7) ------------------------

  @override
  Future<ClientState> peripheralManagerState([
    PeripheralManagerSession? session,
  ]) async =>
      throw UnimplementedError();

  @override
  Stream<ClientState> peripheralManagerStateStream([
    PeripheralManagerSession? session,
  ]) async* {
    throw UnimplementedError();
  }

  @override
  Future<void> startAdvertising({
    PeripheralManagerSession? session,
    String? localName,
    Iterable<String>? serviceUuids,
  }) async =>
      throw UnimplementedError();

  @override
  Future<void> stopAdvertising({PeripheralManagerSession? session}) async =>
      throw UnimplementedError();

  @override
  Future<void> addService({
    PeripheralManagerSession? session,
    required MutableService service,
  }) async =>
      throw UnimplementedError();

  @override
  Stream<({String serviceUuid, String? error})> serviceAddedStream([
    PeripheralManagerSession? session,
  ]) async* {
    throw UnimplementedError();
  }

  @override
  Future<void> removeService({
    PeripheralManagerSession? session,
    required String serviceUuid,
  }) async =>
      throw UnimplementedError();

  @override
  Future<void> removeAllServices({PeripheralManagerSession? session}) async =>
      throw UnimplementedError();

  @override
  Future<void> respondToRequest({
    PeripheralManagerSession? session,
    required int requestId,
    required AttResult result,
    Uint8List? value,
  }) async =>
      throw UnimplementedError();

  @override
  Future<bool> updateValue({
    PeripheralManagerSession? session,
    required String serviceUuid,
    required String characteristicUuid,
    required Uint8List value,
  }) async =>
      throw UnimplementedError();

  @override
  Stream<AttRequest> readRequestStream([
    PeripheralManagerSession? session,
  ]) async* {
    throw UnimplementedError();
  }

  @override
  Stream<List<AttRequest>> writeRequestsStream([
    PeripheralManagerSession? session,
  ]) async* {
    throw UnimplementedError();
  }
}
