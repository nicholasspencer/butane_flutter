import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:butane/butane.dart';
import 'package:butane_platform_interface/butane_platform_interface.dart' as api;

import 'harness_connection.dart';
import 'harness_log.dart';

/// Implements the BLE Central role for the harness app.
///
/// Handles WebSocket commands from the coordinator to scan, connect,
/// discover services/characteristics, read/write values, subscribe
/// to notifications, and disconnect from peripherals.
class CentralRole {
  CentralRole({
    required HarnessConnection server,
    required HarnessLog log,
  })  : _server = server,
        _log = log {
    _manager = CentralManager();
    server.onCommand(_handleCommand);
  }

  final HarnessConnection _server;
  final HarnessLog _log;
  late final CentralManager _manager;

  /// Discovered/connected peripherals keyed by identifier string.
  final Map<String, Peripheral> _peripherals = {};

  /// Active notification subscriptions keyed by "peripheralId:serviceUuid:characteristicUuid".
  final Map<String, StreamSubscription<Uint8List>> _notificationSubscriptions =
      {};

  /// Routes incoming commands to the appropriate handler.
  Future<Map<String, dynamic>> _handleCommand(
    Map<String, dynamic> command,
  ) async {
    final action = command['action'] as String?;
    final params = command;

    switch (action) {
      case 'check_state':
        return _handleCheckState(params);
      case 'scan':
        return _handleScan(params);
      case 'connect':
        return _handleConnect(params);
      case 'disconnect':
        return _handleDisconnect(params);
      case 'discover_services':
        return _handleDiscoverServices(params);
      case 'discover_characteristics':
        return _handleDiscoverCharacteristics(params);
      case 'read_characteristic':
        return _handleReadCharacteristic(params);
      case 'write_characteristic':
        return _handleWriteCharacteristic(params);
      case 'subscribe':
        return _handleSubscribe(params);
      default:
        return {'success': false, 'error': 'Unknown action: $action'};
    }
  }

  /// Returns the BLE adapter state.
  Future<Map<String, dynamic>> _handleCheckState(
    Map<String, dynamic> params,
  ) async {
    final state = await _manager.state;
    _log.add('BLE state: ${state.name}');
    return {'state': state.name};
  }

  /// Scans for peripherals, returns the first match, then stops.
  Future<Map<String, dynamic>> _handleScan(
    Map<String, dynamic> params,
  ) async {
    final serviceUuidStrings = (params['serviceUuids'] as List<dynamic>?)
        ?.cast<String>();
    final serviceUuids =
        serviceUuidStrings?.map((s) => UuidIdentifier(s)).toList();

    _log.add('Scanning${serviceUuids != null ? ' for ${serviceUuids.map((u) => u.toString()).join(', ')}' : ''}...');

    final scanStream = _manager.scan(forServices: serviceUuids);
    final result = await scanStream.first;

    final peripheral = result.peripheral;
    final id = peripheral.identifier.toString();
    _peripherals[id] = peripheral;

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
    final peripheralId = _requireParam<String>(params, 'peripheralId');
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
    final peripheralId = _requireParam<String>(params, 'peripheralId');
    final peripheral = _findPeripheral(peripheralId);

    // Cancel all notification subscriptions for this peripheral.
    _cancelNotificationsForPeripheral(peripheralId);

    _log.add('Disconnecting from $peripheralId...');

    await peripheral.cancelConnection();

    _log.add('Disconnected from $peripheralId');

    return {'disconnected': true};
  }

  /// Discovers services on a connected peripheral.
  Future<Map<String, dynamic>> _handleDiscoverServices(
    Map<String, dynamic> params,
  ) async {
    final peripheralId = _requireParam<String>(params, 'peripheralId');
    final peripheral = _findPeripheral(peripheralId);

    final serviceUuidStrings = (params['serviceUuids'] as List<dynamic>?)
        ?.cast<String>();
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
    final peripheralId = _requireParam<String>(params, 'peripheralId');
    final serviceUuid = _requireParam<String>(params, 'serviceUuid');
    final peripheral = _findPeripheral(peripheralId);

    final charUuidStrings = (params['characteristicUuids'] as List<dynamic>?)
        ?.cast<String>();
    final charUuids =
        charUuidStrings?.map((s) => UuidIdentifier(s)).toList();

    final service = await _findService(peripheral, serviceUuid);

    _log.add('Discovering characteristics on service $serviceUuid...');

    await service.discoverCharacteristics(characteristicUuids: charUuids);
    final characteristics = await service.characteristics;

    _log.add('Found ${characteristics.length} characteristics');

    return {
      'characteristics': characteristics
          .map((c) => {'uuid': c.uuid.toString()})
          .toList(),
    };
  }

  /// Reads a characteristic value, returning it as base64.
  Future<Map<String, dynamic>> _handleReadCharacteristic(
    Map<String, dynamic> params,
  ) async {
    final peripheralId = _requireParam<String>(params, 'peripheralId');
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
    final peripheralId = _requireParam<String>(params, 'peripheralId');
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
    final peripheralId = _requireParam<String>(params, 'peripheralId');
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
      _log.add('Notification $characteristicUuid: ${value.length} bytes');
      _server.sendEvent(
        event: 'notification',
        data: {
          'peripheralId': peripheralId,
          'serviceUuid': serviceUuid,
          'characteristicUuid': characteristicUuid,
          'value': encoded,
        },
      );
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
            c.uuid.toString().toLowerCase() ==
            characteristicUuid.toLowerCase(),
      );
    } on StateError {
      throw StateError(
        'Characteristic $characteristicUuid not discovered on service '
        '$serviceUuid. Run discover_characteristics first.',
      );
    }
  }

  /// Cancels all notification subscriptions for a given peripheral.
  void _cancelNotificationsForPeripheral(String peripheralId) {
    final keysToRemove = _notificationSubscriptions.keys
        .where((key) => key.startsWith('$peripheralId:'))
        .toList();
    for (final key in keysToRemove) {
      _notificationSubscriptions[key]?.cancel();
      _notificationSubscriptions.remove(key);
    }
    if (keysToRemove.isNotEmpty) {
      _log.add('Cancelled ${keysToRemove.length} notification subscriptions');
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
