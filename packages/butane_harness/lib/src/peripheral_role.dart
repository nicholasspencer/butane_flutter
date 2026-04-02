import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:butane/butane.dart';

import 'harness_log.dart';
import 'harness_server.dart';

/// Implements the BLE Peripheral role for the harness app.
///
/// Handles WebSocket commands from the coordinator to add services,
/// start/stop advertising, auto-respond to read/write requests,
/// and update characteristic values.
class PeripheralRole {
  PeripheralRole({
    required HarnessServer server,
    required HarnessLog log,
  })  : _server = server,
        _log = log {
    _manager = PeripheralManager();
    server.onCommand(_handleCommand);
    _setupRequestHandlers();
  }

  final HarnessServer _server;
  final HarnessLog _log;
  late final PeripheralManager _manager;

  /// Preconfigured read response values keyed by "serviceUuid:characteristicUuid".
  final Map<String, Uint8List> _readResponses = {};

  /// Last written values from centrals keyed by "serviceUuid:characteristicUuid".
  final Map<String, Uint8List> _writtenValues = {};

  /// Whether to auto-accept write requests from centrals.
  bool _autoAcceptWrites = true;

  StreamSubscription<AttRequest>? _readRequestSub;
  StreamSubscription<List<AttRequest>>? _writeRequestsSub;

  /// Sets up listeners for incoming read and write requests from centrals.
  void _setupRequestHandlers() {
    _readRequestSub = _manager.readRequests.listen(_handleReadRequest);
    _writeRequestsSub = _manager.writeRequests.listen(_handleWriteRequests);
  }

  /// Handles an incoming read request from a central.
  void _handleReadRequest(AttRequest request) {
    final key =
        '${request.serviceUuid}:${request.characteristicUuid}';
    final value = _readResponses[key];

    if (value != null) {
      _manager.respondToRequest(
        requestId: request.requestId,
        result: AttResult.success,
        value: value,
      );
      _log.add(
        'Read request for $key → success (${value.length} bytes)',
      );
      _server.sendEvent(
        event: 'read_request',
        data: {
          'centralIdentifier': request.centralIdentifier,
          'serviceUuid': request.serviceUuid.toString(),
          'characteristicUuid': request.characteristicUuid.toString(),
          'offset': request.offset,
          'result': 'success',
          'value': base64Encode(value),
        },
      );
    } else {
      _manager.respondToRequest(
        requestId: request.requestId,
        result: AttResult.attributeNotFound,
      );
      _log.add('Read request for $key → attributeNotFound');
      _server.sendEvent(
        event: 'read_request',
        data: {
          'centralIdentifier': request.centralIdentifier,
          'serviceUuid': request.serviceUuid.toString(),
          'characteristicUuid': request.characteristicUuid.toString(),
          'offset': request.offset,
          'result': 'attributeNotFound',
        },
      );
    }
  }

  /// Handles incoming write requests from a central.
  void _handleWriteRequests(List<AttRequest> requests) {
    for (final request in requests) {
      final key =
          '${request.serviceUuid}:${request.characteristicUuid}';

      if (_autoAcceptWrites) {
        if (request.value != null) {
          _writtenValues[key] = request.value!;
        }
        _manager.respondToRequest(
          requestId: request.requestId,
          result: AttResult.success,
        );
        _log.add(
          'Write request for $key → accepted'
          '${request.value != null ? ' (${request.value!.length} bytes)' : ''}',
        );
        _server.sendEvent(
          event: 'write_request',
          data: {
            'centralIdentifier': request.centralIdentifier,
            'serviceUuid': request.serviceUuid.toString(),
            'characteristicUuid': request.characteristicUuid.toString(),
            'offset': request.offset,
            'accepted': true,
            'value': request.value != null
                ? base64Encode(request.value!)
                : null,
          },
        );
      } else {
        _manager.respondToRequest(
          requestId: request.requestId,
          result: AttResult.writeNotPermitted,
        );
        _log.add('Write request for $key → rejected (writeNotPermitted)');
        _server.sendEvent(
          event: 'write_request',
          data: {
            'centralIdentifier': request.centralIdentifier,
            'serviceUuid': request.serviceUuid.toString(),
            'characteristicUuid': request.characteristicUuid.toString(),
            'offset': request.offset,
            'accepted': false,
          },
        );
      }
    }
  }

  /// Routes incoming commands to the appropriate handler.
  Future<Map<String, dynamic>> _handleCommand(
    Map<String, dynamic> command,
  ) async {
    final action = command['action'] as String?;
    final params = command;

    switch (action) {
      case 'check_state':
        return _handleCheckState(params);
      case 'add_service':
        return _handleAddService(params);
      case 'remove_service':
        return _handleRemoveService(params);
      case 'start_advertising':
        return _handleStartAdvertising(params);
      case 'stop_advertising':
        return _handleStopAdvertising(params);
      case 'set_read_response':
        return _handleSetReadResponse(params);
      case 'set_write_handler':
        return _handleSetWriteHandler(params);
      case 'get_written_value':
        return _handleGetWrittenValue(params);
      case 'update_value':
        return _handleUpdateValue(params);
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

  /// Adds a GATT service with characteristics to the local database.
  Future<Map<String, dynamic>> _handleAddService(
    Map<String, dynamic> params,
  ) async {
    final uuid = _requireParam<String>(params, 'uuid');
    final isPrimary = params['isPrimary'] as bool? ?? true;
    final characteristicsList =
        (params['characteristics'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ??
            <Map<String, dynamic>>[];

    final characteristics = characteristicsList.map((charMap) {
      final charUuid = charMap['uuid'] as String;
      final propsMap = charMap['properties'] as Map<String, dynamic>?;
      final permsMap = charMap['permissions'] as Map<String, dynamic>?;
      final valueStr = charMap['value'] as String?;
      final descriptorsList =
          (charMap['descriptors'] as List<dynamic>?)?.cast<Map<String, dynamic>>();

      CharacteristicProperties? properties;
      if (propsMap != null) {
        properties = CharacteristicProperties(
          broadcast: propsMap['broadcast'] as bool? ?? false,
          read: propsMap['read'] as bool? ?? false,
          writeWithoutResponse:
              propsMap['writeWithoutResponse'] as bool? ?? false,
          write: propsMap['write'] as bool? ?? false,
          notify: propsMap['notify'] as bool? ?? false,
          indicate: propsMap['indicate'] as bool? ?? false,
          authenticatedSignedWrites:
              propsMap['authenticatedSignedWrites'] as bool? ?? false,
          extendedProperties:
              propsMap['extendedProperties'] as bool? ?? false,
          notifyEncryptionRequired:
              propsMap['notifyEncryptionRequired'] as bool? ?? false,
          indicateEncryptionRequired:
              propsMap['indicateEncryptionRequired'] as bool? ?? false,
        );
      }

      CharacteristicPermissions? permissions;
      if (permsMap != null) {
        permissions = CharacteristicPermissions(
          readable: permsMap['readable'] as bool? ?? false,
          writeable: permsMap['writeable'] as bool? ?? false,
          readEncryptionRequired:
              permsMap['readEncryptionRequired'] as bool? ?? false,
          writeEncryptionRequired:
              permsMap['writeEncryptionRequired'] as bool? ?? false,
        );
      }

      Uint8List? value;
      if (valueStr != null) {
        value = Uint8List.fromList(base64Decode(valueStr));
      }

      List<MutableDescriptor>? descriptors;
      if (descriptorsList != null) {
        descriptors = descriptorsList.map((descMap) {
          final descValueStr = descMap['value'] as String?;
          return MutableDescriptor(
            uuid: UuidIdentifier(descMap['uuid'] as String),
            value: descValueStr != null
                ? Uint8List.fromList(base64Decode(descValueStr))
                : null,
          );
        }).toList();
      }

      return MutableCharacteristic(
        uuid: UuidIdentifier(charUuid),
        properties: properties,
        permissions: permissions,
        value: value,
        descriptors: descriptors,
      );
    }).toList();

    final service = MutableService(
      uuid: UuidIdentifier(uuid),
      isPrimary: isPrimary,
      characteristics: characteristics,
    );

    await _manager.addService(service);
    _log.add('Added service: $uuid (${characteristics.length} characteristics)');

    return {'added': true, 'serviceUuid': uuid};
  }

  /// Removes a service from the local GATT database.
  Future<Map<String, dynamic>> _handleRemoveService(
    Map<String, dynamic> params,
  ) async {
    final uuid = _requireParam<String>(params, 'uuid');
    await _manager.removeService(UuidIdentifier(uuid));
    _log.add('Removed service: $uuid');
    return {'removed': true};
  }

  /// Starts advertising the local peripheral.
  Future<Map<String, dynamic>> _handleStartAdvertising(
    Map<String, dynamic> params,
  ) async {
    final localName = params['localName'] as String?;
    final serviceUuidStrings =
        (params['serviceUuids'] as List<dynamic>?)?.cast<String>();
    final serviceUuids =
        serviceUuidStrings?.map((s) => UuidIdentifier(s)).toList();

    await _manager.startAdvertising(
      localName: localName,
      serviceUuids: serviceUuids,
    );

    _log.add(
      'Advertising started'
      '${localName != null ? ' as "$localName"' : ''}'
      '${serviceUuids != null ? ' (${serviceUuids.length} services)' : ''}',
    );

    return {'advertising': true};
  }

  /// Stops advertising.
  Future<Map<String, dynamic>> _handleStopAdvertising(
    Map<String, dynamic> params,
  ) async {
    await _manager.stopAdvertising();
    _log.add('Advertising stopped');
    return {'stopped': true};
  }

  /// Stores a preconfigured read response value for a characteristic.
  Future<Map<String, dynamic>> _handleSetReadResponse(
    Map<String, dynamic> params,
  ) async {
    final serviceUuid = _requireParam<String>(params, 'serviceUuid');
    final characteristicUuid =
        _requireParam<String>(params, 'characteristicUuid');
    final valueStr = _requireParam<String>(params, 'value');

    final key = '$serviceUuid:$characteristicUuid';
    final value = Uint8List.fromList(base64Decode(valueStr));
    _readResponses[key] = value;

    _log.add('Set read response for $key (${value.length} bytes)');

    return {'set': true};
  }

  /// Toggles auto-accept behavior for incoming write requests.
  Future<Map<String, dynamic>> _handleSetWriteHandler(
    Map<String, dynamic> params,
  ) async {
    final autoAccept = params['autoAccept'] as bool? ?? true;
    _autoAcceptWrites = autoAccept;

    _log.add('Write handler: autoAccept=$_autoAcceptWrites');

    return {'autoAcceptWrites': _autoAcceptWrites};
  }

  /// Returns the last value written by a central for a characteristic.
  Future<Map<String, dynamic>> _handleGetWrittenValue(
    Map<String, dynamic> params,
  ) async {
    final serviceUuid = _requireParam<String>(params, 'serviceUuid');
    final characteristicUuid =
        _requireParam<String>(params, 'characteristicUuid');

    final key = '$serviceUuid:$characteristicUuid';
    final value = _writtenValues[key];

    return {
      'value': value != null ? base64Encode(value) : null,
    };
  }

  /// Updates a characteristic value and notifies subscribed centrals.
  Future<Map<String, dynamic>> _handleUpdateValue(
    Map<String, dynamic> params,
  ) async {
    final serviceUuid = _requireParam<String>(params, 'serviceUuid');
    final characteristicUuid =
        _requireParam<String>(params, 'characteristicUuid');
    final valueStr = _requireParam<String>(params, 'value');

    final value = Uint8List.fromList(base64Decode(valueStr));

    final sent = await _manager.updateValue(
      serviceUuid: UuidIdentifier(serviceUuid),
      characteristicUuid: UuidIdentifier(characteristicUuid),
      value: value,
    );

    _log.add(
      'Updated value for $serviceUuid:$characteristicUuid'
      ' (${value.length} bytes, sent=$sent)',
    );

    return {'updated': true, 'sent': sent};
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

  /// Cleans up all resources.
  void dispose() {
    _readRequestSub?.cancel();
    _writeRequestsSub?.cancel();
    _manager.dispose();
  }
}
