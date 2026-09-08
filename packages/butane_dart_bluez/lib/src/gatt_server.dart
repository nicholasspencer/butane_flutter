import 'dart:async';
import 'dart:typed_data';

import 'package:butane_dart/interface.dart';
import 'package:dbus/dbus.dart';

/// Wrap raw bytes as a D-Bus `ay` value.
DBusArray _byteArray(List<int> bytes) => DBusArray.byte(bytes);

/// Callbacks the [GattCharacteristic] object invokes when BlueZ forwards a
/// remote read/write from a connected central. The butane peripheral
/// manager plumbs these through its [AttRequest] streams so application
/// code can respond via `respondToRequest`.
///
/// Keeping a callback-interface rather than importing `ButaneDartBluez`
/// directly avoids a cycle between this file and the main plugin class.
abstract class GattServerDelegate {
  /// Allocate a monotonic request id. Ids are scoped to the peripheral
  /// manager and are released when the matching [respondToRead] or
  /// [respondToWrite] fires.
  int allocateRequestId();

  /// Called from [GattCharacteristic.ReadValue]. Emits an [AttRequest] to
  /// the app, returns a future that completes with the value (or error)
  /// once the app calls `respondToRequest`.
  Future<({AttResult result, Uint8List? value})> onReadRequest(
    AttRequest request,
  );

  /// Called from [GattCharacteristic.WriteValue]. Same pattern as above
  /// but no return value — just ack/error.
  Future<AttResult> onWriteRequest(AttRequest request);

  /// Called from [GattCharacteristic.StartNotify] / [StopNotify] so the
  /// plugin can track which characteristics have active subscribers.
  /// Used to short-circuit [updateValue] when nothing is listening.
  void onNotifyingChanged(String characteristicUuid, bool notifying);
}

/// Root object implementing `org.freedesktop.DBus.ObjectManager` as
/// required by `GattManager1.RegisterApplication`.
///
/// BlueZ calls `GetManagedObjects` exactly once after registration and
/// materializes our services/characteristics/descriptors from the
/// returned tree. Subsequent changes to our tree do not propagate — a
/// new `RegisterApplication` is required (which is why [addService]
/// unregisters + re-registers on each call).
class GattApplication extends DBusObject {
  GattApplication(DBusObjectPath path) : super(path);

  final List<DBusObject> _children = [];

  void addChild(DBusObject child) => _children.add(child);

  @override
  List<DBusIntrospectInterface> introspect() {
    return [
      DBusIntrospectInterface('org.freedesktop.DBus.ObjectManager'),
    ];
  }

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall methodCall) async {
    if (methodCall.interface == 'org.freedesktop.DBus.ObjectManager' &&
        methodCall.name == 'GetManagedObjects') {
      return _getManagedObjects();
    }
    return DBusMethodErrorResponse.unknownMethod();
  }

  /// Build the nested dict BlueZ expects: path → (interface → (prop → v)).
  Future<DBusMethodResponse> _getManagedObjects() async {
    final managed = <DBusValue, DBusValue>{};
    for (final child in _children) {
      final interfaces = <DBusValue, DBusValue>{};
      for (final iface in child.introspect()) {
        // Skip interfaces without any properties — BlueZ only cares about
        // GattService1 / GattCharacteristic1 / GattDescriptor1 here.
        if (iface.properties.isEmpty) continue;
        final propsResponse = await child.getAllProperties(iface.name);
        if (propsResponse is! DBusGetAllPropertiesResponse) continue;
        final propsDict = <DBusValue, DBusValue>{};
        propsDict.addAll(
          (propsResponse.returnValues.first as DBusDict).children,
        );
        interfaces[DBusString(iface.name)] = DBusDict(
          DBusSignature('s'),
          DBusSignature('v'),
          propsDict,
        );
      }
      managed[child.path] = DBusDict(
        DBusSignature('s'),
        DBusSignature('a{sv}'),
        interfaces,
      );
    }
    return DBusMethodSuccessResponse([
      DBusDict(
        DBusSignature('o'),
        DBusSignature('a{sa{sv}}'),
        managed,
      ),
    ]);
  }
}

/// `org.bluez.GattService1` D-Bus object. Properties-only — no methods.
class GattService extends DBusObject {
  GattService({
    required DBusObjectPath objectPath,
    required this.uuid,
    required this.isPrimary,
  }) : super(objectPath);

  static const _interfaceName = 'org.bluez.GattService1';

  final String uuid;
  final bool isPrimary;

  @override
  List<DBusIntrospectInterface> introspect() {
    return [
      DBusIntrospectInterface(
        _interfaceName,
        properties: [
          DBusIntrospectProperty(
            'UUID',
            DBusSignature('s'),
            access: DBusPropertyAccess.read,
          ),
          DBusIntrospectProperty(
            'Primary',
            DBusSignature('b'),
            access: DBusPropertyAccess.read,
          ),
        ],
      ),
    ];
  }

  @override
  Future<DBusMethodResponse> getProperty(
    String interface,
    String name,
  ) async {
    if (interface != _interfaceName) {
      return DBusMethodErrorResponse.unknownInterface();
    }
    switch (name) {
      case 'UUID':
        return DBusGetPropertyResponse(DBusString(uuid));
      case 'Primary':
        return DBusGetPropertyResponse(DBusBoolean(isPrimary));
    }
    return DBusMethodErrorResponse.unknownProperty();
  }

  @override
  Future<DBusMethodResponse> getAllProperties(String interface) async {
    if (interface != _interfaceName) {
      return DBusMethodErrorResponse.unknownInterface();
    }
    return DBusGetAllPropertiesResponse({
      'UUID': DBusString(uuid),
      'Primary': DBusBoolean(isPrimary),
    });
  }
}

/// `org.bluez.GattCharacteristic1` D-Bus object. Handles incoming
/// ReadValue/WriteValue/StartNotify/StopNotify calls from BlueZ.
class GattCharacteristic extends DBusObject {
  GattCharacteristic({
    required DBusObjectPath objectPath,
    required DBusObjectPath servicePath,
    required this.uuid,
    required this.flags,
    required this.serviceUuid,
    required this.delegate,
    Uint8List? initialValue,
  })  : _servicePath = servicePath,
        _value = initialValue ?? Uint8List(0),
        super(objectPath);

  static const _interfaceName = 'org.bluez.GattCharacteristic1';

  final DBusObjectPath _servicePath;
  final String uuid;
  final String serviceUuid;

  /// BlueZ-style flag strings: 'read', 'write', 'notify', etc. These map
  /// 1:1 to [CharacteristicProperty] booleans — see
  /// [flagsFromCharacteristicProperty].
  final List<String> flags;

  /// The GattServerDelegate routes incoming read/write/notify events
  /// back to the peripheral manager and on to application streams.
  final GattServerDelegate delegate;

  /// Last value written by the app (via `updateValue`) or cached from
  /// boot. Returned as the `Value` property. BlueZ forwards changes to
  /// subscribed centrals when we emit `PropertiesChanged` on this
  /// property (see [emitValueChanged]).
  Uint8List _value;

  /// True between StartNotify and StopNotify. Tracked so [updateValue]
  /// can skip the PropertiesChanged signal when nobody is subscribed
  /// (matches CoreBluetooth's return-bool-indicating-delivery semantic).
  bool _notifying = false;
  bool get notifying => _notifying;

  Uint8List get currentValue => _value;

  void setValue(Uint8List value) {
    _value = value;
    // Notify subscribed centrals. BlueZ translates PropertiesChanged on
    // Value into BLE notifications/indications based on the Flags we
    // advertised at registration time.
    if (!_notifying) return;
    unawaited(
      emitSignal(
        'org.freedesktop.DBus.Properties',
        'PropertiesChanged',
        [
          const DBusString(_interfaceName),
          DBusDict(
            DBusSignature('s'),
            DBusSignature('v'),
            {
              const DBusString('Value'): DBusVariant(
                _byteArray(value),
              ),
            },
          ),
          DBusArray(DBusSignature('s'), const []),
        ],
      ),
    );
  }

  @override
  List<DBusIntrospectInterface> introspect() {
    return [
      DBusIntrospectInterface(
        _interfaceName,
        methods: [
          DBusIntrospectMethod('ReadValue'),
          DBusIntrospectMethod('WriteValue'),
          DBusIntrospectMethod('StartNotify'),
          DBusIntrospectMethod('StopNotify'),
        ],
        properties: [
          DBusIntrospectProperty(
            'UUID',
            DBusSignature('s'),
            access: DBusPropertyAccess.read,
          ),
          DBusIntrospectProperty(
            'Service',
            DBusSignature('o'),
            access: DBusPropertyAccess.read,
          ),
          DBusIntrospectProperty(
            'Flags',
            DBusSignature('as'),
            access: DBusPropertyAccess.read,
          ),
          DBusIntrospectProperty(
            'Value',
            DBusSignature('ay'),
            access: DBusPropertyAccess.read,
          ),
          DBusIntrospectProperty(
            'Notifying',
            DBusSignature('b'),
            access: DBusPropertyAccess.read,
          ),
        ],
      ),
    ];
  }

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall methodCall) async {
    if (methodCall.interface != _interfaceName) {
      return DBusMethodErrorResponse.unknownInterface();
    }
    switch (methodCall.name) {
      case 'ReadValue':
        return _handleReadValue(methodCall.values);
      case 'WriteValue':
        return _handleWriteValue(methodCall.values);
      case 'StartNotify':
        _notifying = true;
        delegate.onNotifyingChanged(uuid, true);
        return DBusMethodSuccessResponse();
      case 'StopNotify':
        _notifying = false;
        delegate.onNotifyingChanged(uuid, false);
        return DBusMethodSuccessResponse();
    }
    return DBusMethodErrorResponse.unknownMethod();
  }

  /// BlueZ invokes ReadValue with a single options dict. Supported keys
  /// include `offset` (uint16) and `device` (object path of the central).
  /// We pass offset + a derived central identifier through to the app.
  Future<DBusMethodResponse> _handleReadValue(List<DBusValue> values) async {
    final options = _extractOptions(values);
    final offset = _intFromOptions(options, 'offset');
    final centralId = _centralIdFromOptions(options);
    final request = AttRequest(
      requestId: delegate.allocateRequestId(),
      centralIdentifier: centralId,
      characteristicUuid: uuid,
      serviceUuid: serviceUuid,
      offset: offset,
    );
    final outcome = await delegate.onReadRequest(request);
    if (outcome.result != AttResult.success) {
      return _attErrorResponse(outcome.result);
    }
    final returned = outcome.value ?? Uint8List(0);
    // Cache the value so subsequent property reads return the latest
    // snapshot. BlueZ reads Value via Properties.Get for debugging.
    _value = returned;
    return DBusMethodSuccessResponse([_byteArray(returned)]);
  }

  Future<DBusMethodResponse> _handleWriteValue(List<DBusValue> values) async {
    if (values.length < 2 || values[0] is! DBusArray) {
      return DBusMethodErrorResponse.invalidArgs();
    }
    final bytes = Uint8List.fromList(
      (values[0] as DBusArray)
          .children
          .map((v) => (v as DBusByte).value)
          .toList(),
    );
    final options = _extractOptions(values);
    final offset = _intFromOptions(options, 'offset');
    final centralId = _centralIdFromOptions(options);
    final request = AttRequest(
      requestId: delegate.allocateRequestId(),
      centralIdentifier: centralId,
      characteristicUuid: uuid,
      serviceUuid: serviceUuid,
      offset: offset,
      value: bytes,
    );
    final result = await delegate.onWriteRequest(request);
    if (result != AttResult.success) {
      return _attErrorResponse(result);
    }
    // Per BlueZ GATT API, a write-with-response must have its Value
    // property reflect the last-received payload — keep ours in sync.
    _value = bytes;
    return DBusMethodSuccessResponse();
  }

  Map<DBusValue, DBusValue> _extractOptions(List<DBusValue> values) {
    // Options dict is always the last arg per BlueZ's GATT spec.
    for (var i = values.length - 1; i >= 0; i--) {
      if (values[i] is DBusDict) {
        return (values[i] as DBusDict).children;
      }
    }
    return const {};
  }

  int _intFromOptions(Map<DBusValue, DBusValue> opts, String key) {
    final entry = opts[DBusString(key)];
    if (entry is DBusVariant) {
      final inner = entry.value;
      if (inner is DBusUint16) return inner.value;
      if (inner is DBusUint32) return inner.value;
      if (inner is DBusUint64) return inner.value;
    }
    return 0;
  }

  /// The central identifier in CoreBluetooth is a UUID; BlueZ provides
  /// the central's D-Bus object path (e.g. `/org/bluez/hci0/dev_XX_YY`).
  /// We surface the tail as the identifier since app code typically
  /// treats it as an opaque string.
  String _centralIdFromOptions(Map<DBusValue, DBusValue> opts) {
    final entry = opts[const DBusString('device')];
    if (entry is DBusVariant) {
      final inner = entry.value;
      if (inner is DBusObjectPath) {
        final segments = inner.value.split('/');
        if (segments.isNotEmpty) return segments.last;
      }
    }
    return '';
  }

  DBusMethodResponse _attErrorResponse(AttResult result) {
    // BlueZ expects org.bluez.Error.* names for GATT failures. See
    // doc/gatt-api.txt in the BlueZ tree for the canonical set.
    const mapping = <AttResult, String>{
      AttResult.readNotPermitted: 'org.bluez.Error.NotPermitted',
      AttResult.writeNotPermitted: 'org.bluez.Error.NotPermitted',
      AttResult.invalidHandle: 'org.bluez.Error.InvalidArgs',
      AttResult.invalidOffset: 'org.bluez.Error.InvalidOffset',
      AttResult.attributeNotFound: 'org.bluez.Error.NotSupported',
      AttResult.unlikelyError: 'org.bluez.Error.Failed',
    };
    return DBusMethodErrorResponse(
      mapping[result] ?? 'org.bluez.Error.Failed',
    );
  }

  @override
  Future<DBusMethodResponse> getProperty(
    String interface,
    String name,
  ) async {
    if (interface != _interfaceName) {
      return DBusMethodErrorResponse.unknownInterface();
    }
    switch (name) {
      case 'UUID':
        return DBusGetPropertyResponse(DBusString(uuid));
      case 'Service':
        return DBusGetPropertyResponse(_servicePath);
      case 'Flags':
        return DBusGetPropertyResponse(
          DBusArray(
            DBusSignature('s'),
            [for (final f in flags) DBusString(f)],
          ),
        );
      case 'Value':
        return DBusGetPropertyResponse(_byteArray(_value));
      case 'Notifying':
        return DBusGetPropertyResponse(DBusBoolean(_notifying));
    }
    return DBusMethodErrorResponse.unknownProperty();
  }

  @override
  Future<DBusMethodResponse> getAllProperties(String interface) async {
    if (interface != _interfaceName) {
      return DBusMethodErrorResponse.unknownInterface();
    }
    return DBusGetAllPropertiesResponse({
      'UUID': DBusString(uuid),
      'Service': _servicePath,
      'Flags': DBusArray(
        DBusSignature('s'),
        [for (final f in flags) DBusString(f)],
      ),
      'Value': _byteArray(_value),
      'Notifying': DBusBoolean(_notifying),
    });
  }
}

/// `org.bluez.GattDescriptor1` D-Bus object. We support static-value
/// descriptors only (no ReadValue/WriteValue dispatch) since the
/// platform interface's [MutableDescriptor] exposes no handler hooks.
class GattDescriptor extends DBusObject {
  GattDescriptor({
    required DBusObjectPath objectPath,
    required DBusObjectPath characteristicPath,
    required this.uuid,
    Uint8List? value,
  })  : _characteristicPath = characteristicPath,
        _value = value ?? Uint8List(0),
        super(objectPath);

  static const _interfaceName = 'org.bluez.GattDescriptor1';

  final DBusObjectPath _characteristicPath;
  final String uuid;
  final Uint8List _value;

  @override
  List<DBusIntrospectInterface> introspect() {
    return [
      DBusIntrospectInterface(
        _interfaceName,
        methods: [
          DBusIntrospectMethod('ReadValue'),
          DBusIntrospectMethod('WriteValue'),
        ],
        properties: [
          DBusIntrospectProperty(
            'UUID',
            DBusSignature('s'),
            access: DBusPropertyAccess.read,
          ),
          DBusIntrospectProperty(
            'Characteristic',
            DBusSignature('o'),
            access: DBusPropertyAccess.read,
          ),
          DBusIntrospectProperty(
            'Value',
            DBusSignature('ay'),
            access: DBusPropertyAccess.read,
          ),
        ],
      ),
    ];
  }

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall methodCall) async {
    if (methodCall.interface != _interfaceName) {
      return DBusMethodErrorResponse.unknownInterface();
    }
    switch (methodCall.name) {
      case 'ReadValue':
        return DBusMethodSuccessResponse([_byteArray(_value)]);
      case 'WriteValue':
        // Descriptors are read-only from remote clients in this
        // implementation — callers setting up read/write descriptors
        // should instead use a characteristic.
        return DBusMethodErrorResponse('org.bluez.Error.NotPermitted');
    }
    return DBusMethodErrorResponse.unknownMethod();
  }

  @override
  Future<DBusMethodResponse> getProperty(
    String interface,
    String name,
  ) async {
    if (interface != _interfaceName) {
      return DBusMethodErrorResponse.unknownInterface();
    }
    switch (name) {
      case 'UUID':
        return DBusGetPropertyResponse(DBusString(uuid));
      case 'Characteristic':
        return DBusGetPropertyResponse(_characteristicPath);
      case 'Value':
        return DBusGetPropertyResponse(_byteArray(_value));
    }
    return DBusMethodErrorResponse.unknownProperty();
  }

  @override
  Future<DBusMethodResponse> getAllProperties(String interface) async {
    if (interface != _interfaceName) {
      return DBusMethodErrorResponse.unknownInterface();
    }
    return DBusGetAllPropertiesResponse({
      'UUID': DBusString(uuid),
      'Characteristic': _characteristicPath,
      'Value': _byteArray(_value),
    });
  }
}

/// Map a [CharacteristicProperty] to the BlueZ Flags string list used in
/// `org.bluez.GattCharacteristic1.Flags`. Inverse of the mapping in
/// ButaneDartBluez._flagsToProperties.
List<String> flagsFromCharacteristicProperty(CharacteristicProperty? props) {
  if (props == null) return const ['read'];
  final flags = <String>[];
  if (props.broadcast) flags.add('broadcast');
  if (props.read) flags.add('read');
  if (props.writeWithoutResponse) flags.add('write-without-response');
  if (props.write) flags.add('write');
  if (props.notify) flags.add('notify');
  if (props.indicate) flags.add('indicate');
  if (props.authenticatedSignedWrites) flags.add('authenticated-signed-writes');
  if (props.extendedProperties) flags.add('extended-properties');
  // BlueZ insists on at least one flag — default to 'read' if the app
  // gave us nothing, so RegisterApplication doesn't reject us.
  if (flags.isEmpty) flags.add('read');
  return flags;
}
