import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:butane/butane.dart';
import 'package:butane_platform_interface/butane_platform_interface.dart'
    as api;

import 'command_registry.dart';
import 'harness_log.dart';

/// Implements the BLE Central role for the harness app.
///
/// Exposes its command vocabulary (scan, connect, discover
/// services/characteristics, read/write values, subscribe to notifications,
/// disconnect) as [commands] on the registry used by the Leonard extension.
class CentralRole {
  CentralRole({required HarnessLog log}) : _log = log {
    _manager = CentralManager();
  }

  final HarnessLog _log;
  late final CentralManager _manager;

  /// Discovered/connected peripherals keyed by identifier string.
  final Map<String, Peripheral> _peripherals = {};

  /// Active notification subscriptions keyed by "peripheralId:serviceUuid:characteristicUuid".
  final Map<String, StreamSubscription<Uint8List>> _notificationSubscriptions =
      {};

  /// Last adapter state observed by `check_state` (perception cache — the
  /// leonard fragment is a synchronous snapshot).
  String? _lastKnownState;

  /// The most recently scanned peripheral id — the default target when a
  /// command omits `peripheralId` (scripted scenarios are static and cannot
  /// thread the scan result into later steps).
  String? _lastScannedId;

  /// Received notifications keyed by "serviceUuid:characteristicUuid":
  /// count + last base64 value (perception cache + `wait_for_notification`).
  final Map<String, Map<String, Object?>> _notifications = {};

  /// A synchronous snapshot of central-side state, serialized into the
  /// leonard extension's `extensions.butane` perception fragment.
  Map<String, Object?> perceptionSnapshot() => {
        'role': 'central',
        'adapter_state': _lastKnownState,
        'peripherals': [
          for (final entry in _peripherals.entries)
            {'id': entry.key, 'name': entry.value.name},
        ],
        'subscriptions': _notificationSubscriptions.keys.toList(),
        'notifications': {
          for (final entry in _notifications.entries)
            entry.key: Map<String, Object?>.of(entry.value),
        },
      };

  /// The central command vocabulary, in wire order.
  List<HarnessCommand> get commands => [
        HarnessCommand(
          action: 'check_state',
          description: 'Return the BLE adapter state (e.g. poweredOn).',
          handler: _handleCheckState,
        ),
        HarnessCommand(
          action: 'wait_for_state',
          description: 'Poll the adapter until it reaches a state (default '
              'poweredOn; optional state, timeoutMs). BLE ops invoked before '
              'poweredOn hang in CoreBluetooth — call this first.',
          handler: _handleWaitForState,
        ),
        HarnessCommand(
          action: 'scan',
          description: 'Scan for peripherals (optional serviceUuids list), '
              'return the first match, then stop.',
          handler: _handleScan,
        ),
        HarnessCommand(
          action: 'connect',
          description:
              'Connect to a previously discovered peripheral (peripheralId).',
          handler: _handleConnect,
        ),
        HarnessCommand(
          action: 'disconnect',
          description: 'Disconnect from a peripheral (peripheralId), '
              'cleaning up notification subscriptions.',
          handler: _handleDisconnect,
        ),
        HarnessCommand(
          action: 'discover_services',
          description: 'Discover services on a connected peripheral '
              '(peripheralId, optional serviceUuids).',
          handler: _handleDiscoverServices,
        ),
        HarnessCommand(
          action: 'discover_characteristics',
          description: 'Discover characteristics on a service (peripheralId, '
              'serviceUuid, optional characteristicUuids).',
          handler: _handleDiscoverCharacteristics,
        ),
        HarnessCommand(
          action: 'read_characteristic',
          description: 'Read a characteristic value (peripheralId, '
              'serviceUuid, characteristicUuid) → base64.',
          handler: _handleReadCharacteristic,
        ),
        HarnessCommand(
          action: 'write_characteristic',
          description: 'Write a base64 value to a characteristic '
              '(peripheralId, serviceUuid, characteristicUuid, value, '
              'optional withoutResponse).',
          handler: _handleWriteCharacteristic,
        ),
        HarnessCommand(
          action: 'subscribe',
          description: 'Subscribe to characteristic notifications '
              '(peripheralId, serviceUuid, characteristicUuid); events '
              'are recorded in the perception snapshot.',
          handler: _handleSubscribe,
        ),
        HarnessCommand(
          action: 'wait_for_notification',
          description: 'Poll until a notification has been received on a '
              'subscribed characteristic (serviceUuid, characteristicUuid; '
              'optional timeoutMs) → count + last base64 value. Delivery is '
              'async — scripted scenarios gate on this, not a bare observe.',
          handler: _handleWaitForNotification,
        ),
      ];

  /// Returns the BLE adapter state.
  Future<Map<String, dynamic>> _handleCheckState(
    Map<String, dynamic> params,
  ) async {
    final state = await _manager.state;
    _lastKnownState = state.name;
    _log.add('BLE state: ${state.name}');
    return {'state': state.name};
  }

  /// Polls the adapter until it reaches the wanted state (default
  /// `poweredOn`) or the timeout elapses. Returns the final state either way
  /// — the caller asserts. BLE operations issued before `poweredOn` hang in
  /// CoreBluetooth (no delegate callback), so scripted scenarios gate on
  /// this first.
  Future<Map<String, dynamic>> _handleWaitForState(
    Map<String, dynamic> params,
  ) async {
    final want = params['state'] as String? ?? 'poweredOn';
    final timeoutMs = params['timeoutMs'] as int? ?? 10000;
    final deadline = DateTime.now().add(Duration(milliseconds: timeoutMs));
    var state = (await _manager.state).name;
    while (state != want && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      state = (await _manager.state).name;
    }
    _lastKnownState = state;
    _log.add('Waited for $want → $state');
    return {'state': state, 'matched': state == want};
  }

  /// Polls until a notification for the characteristic has arrived (or the
  /// timeout elapses); returns the received count + last base64 value either
  /// way — the caller asserts. Notification delivery is asynchronous, so
  /// scripted scenarios gate on this rather than racing an observe.
  Future<Map<String, dynamic>> _handleWaitForNotification(
    Map<String, dynamic> params,
  ) async {
    final serviceUuid = _requireParam<String>(params, 'serviceUuid');
    final characteristicUuid =
        _requireParam<String>(params, 'characteristicUuid');
    final timeoutMs = params['timeoutMs'] as int? ?? 10000;
    final key = '$serviceUuid:$characteristicUuid'.toLowerCase();
    final deadline = DateTime.now().add(Duration(milliseconds: timeoutMs));
    while (_notifications[key] == null && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    final entry = _notifications[key];
    _log.add(
      'Waited for notification on $key → '
      '${entry == null ? 'none' : 'count=${entry['count']}'}',
    );
    return {
      'received': entry != null,
      'count': entry?['count'] ?? 0,
      'last_value': entry?['last_value'],
    };
  }

  /// Scans for peripherals, returns the first match, then stops.
  Future<Map<String, dynamic>> _handleScan(
    Map<String, dynamic> params,
  ) async {
    final serviceUuidStrings =
        (params['serviceUuids'] as List<dynamic>?)?.cast<String>();
    final serviceUuids =
        serviceUuidStrings?.map((s) => UuidIdentifier(s)).toList();

    final timeoutMs = params['timeoutMs'] as int? ?? 15000;

    _log.add(
        'Scanning${serviceUuids != null ? ' for ${serviceUuids.map((u) => u.toString()).join(', ')}' : ''}...');

    // Bounded: an empty airspace returns found:false instead of hanging the
    // caller's drive channel (the same-box lesson — a central never sees its
    // own machine's advertisement).
    final scanStream = _manager.scan(forServices: serviceUuids);
    final ScanResult result;
    try {
      result = await scanStream.first.timeout(
        Duration(milliseconds: timeoutMs),
      );
    } on TimeoutException {
      _log.add('Scan timed out after ${timeoutMs}ms (nothing found)');
      return {'found': false, 'timeoutMs': timeoutMs};
    }

    final peripheral = result.peripheral;
    final id = peripheral.identifier.toString();
    _peripherals[id] = peripheral;
    _lastScannedId = id;

    _log.add('Found peripheral: $id (${peripheral.name ?? 'unnamed'})');

    return {
      'peripheral': {
        'id': id,
        'name': peripheral.name,
      },
    };
  }

  /// Connects to a previously discovered peripheral.
  Future<Map<String, dynamic>> _handleConnect(
    Map<String, dynamic> params,
  ) async {
    final peripheralId = _peripheralIdFrom(params);
    final peripheral = _findPeripheral(peripheralId);

    _log.add('Connecting to $peripheralId...');

    await peripheral.connect();

    // Wait for the connected state confirmation.
    await peripheral.stateStream.firstWhere(
      (state) => state == ConnectionState.connected,
    );

    _log.add('Connected to $peripheralId');

    return {'connected': true};
  }

  /// Disconnects from a peripheral, cleaning up notification subscriptions.
  Future<Map<String, dynamic>> _handleDisconnect(
    Map<String, dynamic> params,
  ) async {
    final peripheralId = _peripheralIdFrom(params);
    final peripheral = _findPeripheral(peripheralId);

    // Disable BLE notifications before cancelling stream subscriptions.
    await _disableNotificationsForPeripheral(peripheralId);

    _log.add('Disconnecting from $peripheralId...');

    await peripheral.cancelConnection();

    _log.add('Disconnected from $peripheralId');

    return {'disconnected': true};
  }

  /// Discovers services on a connected peripheral.
  Future<Map<String, dynamic>> _handleDiscoverServices(
    Map<String, dynamic> params,
  ) async {
    final peripheralId = _peripheralIdFrom(params);
    final peripheral = _findPeripheral(peripheralId);

    final serviceUuidStrings =
        (params['serviceUuids'] as List<dynamic>?)?.cast<String>();
    final serviceUuids =
        serviceUuidStrings?.map((s) => UuidIdentifier(s)).toList();

    _log.add('Discovering services on $peripheralId...');

    await peripheral.discoverServices(serviceUuids: serviceUuids);
    final services = await peripheral.services;

    _log.add('Found ${services.length} services');

    return {
      'services': services
          .map((s) => {
                'uuid': s.uuid.toString(),
                'isPrimary': s.isPrimary,
              })
          .toList(),
    };
  }

  /// Discovers characteristics on a specific service.
  Future<Map<String, dynamic>> _handleDiscoverCharacteristics(
    Map<String, dynamic> params,
  ) async {
    final peripheralId = _peripheralIdFrom(params);
    final serviceUuid = _requireParam<String>(params, 'serviceUuid');
    final peripheral = _findPeripheral(peripheralId);

    final charUuidStrings =
        (params['characteristicUuids'] as List<dynamic>?)?.cast<String>();
    final charUuids = charUuidStrings?.map((s) => UuidIdentifier(s)).toList();

    final service = await _findService(peripheral, serviceUuid);

    _log.add('Discovering characteristics on service $serviceUuid...');

    await service.discoverCharacteristics(characteristicUuids: charUuids);
    final characteristics = await service.characteristics;

    _log.add('Found ${characteristics.length} characteristics');

    return {
      'characteristics':
          characteristics.map((c) => {'uuid': c.uuid.toString()}).toList(),
    };
  }

  /// Reads a characteristic value, returning it as base64.
  Future<Map<String, dynamic>> _handleReadCharacteristic(
    Map<String, dynamic> params,
  ) async {
    final peripheralId = _peripheralIdFrom(params);
    final serviceUuid = _requireParam<String>(params, 'serviceUuid');
    final characteristicUuid =
        _requireParam<String>(params, 'characteristicUuid');

    final characteristic = await _findCharacteristic(
      peripheralId,
      serviceUuid,
      characteristicUuid,
    );

    final value = await characteristic.read();
    final encoded = base64Encode(value);

    _log.add('Read $characteristicUuid: ${value.length} bytes');

    return {'value': encoded};
  }

  /// Writes a base64-encoded value to a characteristic.
  Future<Map<String, dynamic>> _handleWriteCharacteristic(
    Map<String, dynamic> params,
  ) async {
    final peripheralId = _peripheralIdFrom(params);
    final serviceUuid = _requireParam<String>(params, 'serviceUuid');
    final characteristicUuid =
        _requireParam<String>(params, 'characteristicUuid');
    final valueStr = _requireParam<String>(params, 'value');
    final withoutResponse = params['withoutResponse'] as bool? ?? false;

    final characteristic = await _findCharacteristic(
      peripheralId,
      serviceUuid,
      characteristicUuid,
    );

    final data = Uint8List.fromList(base64Decode(valueStr));
    await characteristic.write(
      value: data,
      withoutResponse: withoutResponse,
    );

    _log.add('Wrote $characteristicUuid: ${data.length} bytes'
        '${withoutResponse ? ' (no response)' : ''}');

    return {'written': true};
  }

  /// Subscribes to characteristic notifications, streaming events to the
  /// coordinator via unsolicited WebSocket events.
  ///
  /// Uses the platform interface directly to enable notifications and listen
  /// to value updates, bypassing the porcelain `observe()` which emits an
  /// initial sinkValue read that can interfere with the test flow.
  Future<Map<String, dynamic>> _handleSubscribe(
    Map<String, dynamic> params,
  ) async {
    final peripheralId = _peripheralIdFrom(params);
    final serviceUuid = _requireParam<String>(params, 'serviceUuid');
    final characteristicUuid =
        _requireParam<String>(params, 'characteristicUuid');

    final characteristic = await _findCharacteristic(
      peripheralId,
      serviceUuid,
      characteristicUuid,
    );

    final key = '$peripheralId:$serviceUuid:$characteristicUuid';

    // Cancel existing subscription if any.
    await _notificationSubscriptions[key]?.cancel();

    // Use the normalized (uppercase) UUID from discovered characteristic
    // to match CoreBluetooth's format in stream events.
    final normalizedCharUuid = characteristic.uuid.toString();
    final normalizedServiceUuid =
        characteristic.service?.uuid.toString() ?? serviceUuid;

    // Build a PeripheralSession matching the one used by the platform.
    final session = api.PeripheralSession(
      peripheralIdentifier: peripheralId,
      clientIdentifier: _manager.clientIdentifier,
    );

    // Explicitly enable notifications and await completion.
    // The porcelain observe() does this internally but doesn't
    // expose the await to the caller.
    final platform = api.ButanePlatformInterface.instance;
    await platform.observeCharacteristic(
      observe: true,
      session: session,
      serviceUuid: normalizedServiceUuid,
      characteristicUuid: normalizedCharUuid,
    );

    _log.add('Notifications enabled for $normalizedCharUuid');

    // Listen to the raw characteristic value stream from the platform.
    final subscription = platform
        .characteristicValueStream(
      session: session,
      serviceUuid: normalizedServiceUuid,
      characteristicUuid: normalizedCharUuid,
    )
        .listen((value) {
      if (value.isEmpty) return;

      final encoded = base64Encode(value);
      final notifKey = '$serviceUuid:$characteristicUuid'.toLowerCase();
      final entry = _notifications.putIfAbsent(
        notifKey,
        () => <String, Object?>{'count': 0, 'last_value': ''},
      );
      entry['count'] = (entry['count']! as int) + 1;
      entry['last_value'] = encoded;
      _log.add('Notification $characteristicUuid: ${value.length} bytes');
    });

    _notificationSubscriptions[key] = subscription;

    _log.add('Subscribed to $characteristicUuid notifications');

    return {'subscribed': true};
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Requires a parameter to be present and of the expected type.
  T _requireParam<T>(Map<String, dynamic> params, String name) {
    final value = params[name];
    if (value == null) {
      throw ArgumentError('Missing required param: $name');
    }
    if (value is! T) {
      throw ArgumentError(
        'Param "$name" must be ${T.toString()}, got ${value.runtimeType}',
      );
    }
    return value;
  }

  /// Resolves the target peripheral id: an explicit `peripheralId` param, or
  /// the most recently scanned peripheral (scripted scenarios are static and
  /// cannot thread the scan result forward). Throws when neither exists.
  String _peripheralIdFrom(Map<String, dynamic> params) {
    final explicit = params['peripheralId'] as String?;
    final id = explicit ?? _lastScannedId;
    if (id == null) {
      throw StateError('No peripheralId given and nothing scanned yet.');
    }
    return id;
  }

  /// Looks up a peripheral by ID. Throws if not found.
  Peripheral _findPeripheral(String peripheralId) {
    final peripheral = _peripherals[peripheralId];
    if (peripheral == null) {
      throw StateError(
        'No peripheral with ID: $peripheralId. Run scan first.',
      );
    }
    return peripheral;
  }

  /// Finds a service by UUID on a peripheral. Throws if not found.
  Future<Service> _findService(
    Peripheral peripheral,
    String serviceUuid,
  ) async {
    final services = await peripheral.services;
    try {
      return services.firstWhere(
        (s) => s.uuid.toString().toLowerCase() == serviceUuid.toLowerCase(),
      );
    } on StateError {
      throw StateError(
        'Service $serviceUuid not discovered on peripheral '
        '${peripheral.identifier}. Run discover_services first.',
      );
    }
  }

  /// Navigates peripheral → service → characteristic. Throws with context
  /// at each level if the target is not found.
  Future<Characteristic> _findCharacteristic(
    String peripheralId,
    String serviceUuid,
    String characteristicUuid,
  ) async {
    final peripheral = _findPeripheral(peripheralId);
    final service = await _findService(peripheral, serviceUuid);
    final characteristics = await service.characteristics;
    try {
      return characteristics.firstWhere(
        (c) =>
            c.uuid.toString().toLowerCase() == characteristicUuid.toLowerCase(),
      );
    } on StateError {
      throw StateError(
        'Characteristic $characteristicUuid not discovered on service '
        '$serviceUuid. Run discover_characteristics first.',
      );
    }
  }

  /// Disables BLE notifications and cancels stream subscriptions for a peripheral.
  Future<void> _disableNotificationsForPeripheral(String peripheralId) async {
    final keysToRemove = _notificationSubscriptions.keys
        .where((key) => key.startsWith('$peripheralId:'))
        .toList();

    final platform = api.ButanePlatformInterface.instance;
    final session = api.PeripheralSession(
      peripheralIdentifier: peripheralId,
      clientIdentifier: _manager.clientIdentifier,
    );

    for (final key in keysToRemove) {
      // Extract serviceUuid and characteristicUuid from the key.
      final parts = key.split(':');
      if (parts.length >= 3) {
        final serviceUuid = parts[1];
        final characteristicUuid = parts[2];
        try {
          await platform.observeCharacteristic(
            observe: false,
            session: session,
            serviceUuid: serviceUuid,
            characteristicUuid: characteristicUuid,
          );
        } catch (_) {
          // Ignore errors during cleanup — the peripheral may already
          // be disconnected.
        }
      }
      await _notificationSubscriptions[key]?.cancel();
      _notificationSubscriptions.remove(key);
    }
    if (keysToRemove.isNotEmpty) {
      _log.add('Disabled ${keysToRemove.length} notification subscriptions');
    }
  }

  /// Cleans up all resources.
  void dispose() {
    for (final sub in _notificationSubscriptions.values) {
      sub.cancel();
    }
    _notificationSubscriptions.clear();
    _manager.dispose();
  }
}
