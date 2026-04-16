import 'dart:async';

import 'package:dbus/dbus.dart';

/// D-Bus object implementing `org.bluez.LEAdvertisement1`.
///
/// BlueZ's `LEAdvertisingManager1.RegisterAdvertisement` expects the caller
/// to expose an object implementing this interface; BlueZ reads the
/// properties via `org.freedesktop.DBus.Properties` and broadcasts them.
/// When BlueZ stops using the advertisement (adapter powered off, caller
/// unregisters) it invokes [Release] on our object — we treat that as
/// advisory; actual teardown is driven by the caller via the peripheral
/// manager.
///
/// The bluez Dart package does not wrap this interface (it's central-only),
/// so we register a bare [DBusObject] on the system bus ourselves.
class LEAdvertisement extends DBusObject {
  LEAdvertisement({
    required DBusObjectPath objectPath,
    this.localName,
    this.serviceUuids = const [],
  }) : _path = objectPath;

  static const _interfaceName = 'org.bluez.LEAdvertisement1';

  final DBusObjectPath _path;
  final String? localName;
  final List<String> serviceUuids;

  /// Completes when BlueZ calls `Release` on us — signals a BlueZ-initiated
  /// teardown (e.g., the adapter being powered off). Useful for callers
  /// that want to notice the advertisement going away without having
  /// triggered it themselves.
  final Completer<void> released = Completer<void>();

  @override
  DBusObjectPath get path => _path;

  @override
  List<DBusIntrospectInterface> introspect() {
    return [
      DBusIntrospectInterface(
        _interfaceName,
        methods: [DBusIntrospectMethod('Release')],
        properties: [
          DBusIntrospectProperty(
            'Type',
            DBusSignature('s'),
            access: DBusPropertyAccess.read,
          ),
          DBusIntrospectProperty(
            'ServiceUUIDs',
            DBusSignature('as'),
            access: DBusPropertyAccess.read,
          ),
          if (localName != null)
            DBusIntrospectProperty(
              'LocalName',
              DBusSignature('s'),
              access: DBusPropertyAccess.read,
            ),
        ],
      ),
    ];
  }

  @override
  Future<DBusMethodResponse> handleMethodCall(
    String? sender,
    String? interface,
    String member,
    List<DBusValue> values,
  ) async {
    if (interface != _interfaceName) {
      return DBusMethodErrorResponse.unknownInterface();
    }
    if (member == 'Release') {
      if (!released.isCompleted) released.complete();
      return DBusMethodSuccessResponse();
    }
    return DBusMethodErrorResponse.unknownMethod();
  }

  @override
  Future<DBusMethodResponse> getProperty(
    String interface,
    String member,
  ) async {
    if (interface != _interfaceName) {
      return DBusMethodErrorResponse.unknownInterface();
    }
    switch (member) {
      case 'Type':
        return DBusGetPropertyResponse(const DBusString('peripheral'));
      case 'ServiceUUIDs':
        return DBusGetPropertyResponse(
          DBusArray(
            DBusSignature('s'),
            [for (final u in serviceUuids) DBusString(u)],
          ),
        );
      case 'LocalName':
        if (localName == null) {
          return DBusMethodErrorResponse.unknownProperty();
        }
        return DBusGetPropertyResponse(DBusString(localName!));
    }
    return DBusMethodErrorResponse.unknownProperty();
  }

  @override
  Future<DBusMethodResponse> getAllProperties(String interface) async {
    if (interface != _interfaceName) {
      return DBusMethodErrorResponse.unknownInterface();
    }
    final props = <String, DBusValue>{
      'Type': const DBusString('peripheral'),
      'ServiceUUIDs': DBusArray(
        DBusSignature('s'),
        [for (final u in serviceUuids) DBusString(u)],
      ),
    };
    if (localName != null) {
      props['LocalName'] = DBusString(localName!);
    }
    return DBusGetAllPropertiesResponse(props);
  }
}
