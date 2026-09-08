import 'dart:async';
import 'dart:io';

import 'package:bluez/bluez.dart';
import 'package:butane_dart/interface.dart';
import 'package:butane_dart_bluez/butane_dart_bluez.dart';
import 'package:dbus/dbus.dart';
import 'package:test/test.dart';

const _adapterPath = DBusObjectPath.unchecked('/org/bluez/hci0');
const _devicePath =
    DBusObjectPath.unchecked('/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF');
const _servicePath = DBusObjectPath.unchecked(
  '/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF/service0001',
);
const _characteristicPath = DBusObjectPath.unchecked(
  '/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF/service0001/char0001',
);
const _descriptorPath = DBusObjectPath.unchecked(
  '/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF/service0001/char0001/desc0001',
);
const _address = 'AA:BB:CC:DD:EE:FF';
const _serviceUuid = '12345678-1234-5678-1234-56789abcdef0';
const _characteristicUuid = '12345678-1234-5678-1234-56789abcdef1';
const _descriptorUuid = '12345678-1234-5678-1234-56789abcdef2';

void main() {
  test('property changes drive client, scan, and connection streams', () async {
    final fixture = await _BlueZFixture.start(withDevice: true);
    addTearDown(fixture.close);
    final backend = fixture.backend;
    final session = const PeripheralSession(peripheralIdentifier: _address);

    expect(await backend.clientState(), ClientState.poweredOn);

    final clientStates = <ClientState>[];
    final scanResults = <ScanResult>[];
    final connectionStates = <ConnectionState>[];
    fixture.track(backend.clientStateStream().listen(clientStates.add));
    fixture.track(backend.scanStream().listen(scanResults.add));
    fixture.track(
      backend
          .connectionStateStream(session: session)
          .listen(connectionStates.add),
    );

    await _waitUntil(
      () => clientStates.length == 1 && connectionStates.length == 1,
    );
    await backend.scan();
    await fixture.clientBus.ping();

    await fixture.adapter.change('Powered', const DBusBoolean(false));
    await fixture.device!.change('RSSI', const DBusInt16(-55));
    await fixture.device!.change('Connected', const DBusBoolean(true));

    await _waitUntil(
      () =>
          clientStates.length == 2 &&
          scanResults.length == 1 &&
          connectionStates.length == 2,
    );
    expect(
      clientStates,
      [ClientState.poweredOn, ClientState.poweredOff],
    );
    expect(scanResults.single.peripheral.rssi, -55);
    expect(
      connectionStates,
      [ConnectionState.disconnected, ConnectionState.connected],
    );
  });

  test('an InterfacesAdded device is emitted while scanning', () async {
    final fixture = await _BlueZFixture.start();
    addTearDown(fixture.close);
    final results = <ScanResult>[];

    expect(await fixture.backend.clientState(), ClientState.poweredOn);
    fixture.track(fixture.backend.scanStream().listen(results.add));
    await fixture.backend.scan();
    await fixture.clientBus.ping();

    await fixture.addDevice();

    await _waitUntil(() => results.length == 1);
    expect(results.single.peripheral.session.peripheralIdentifier, _address);
    expect(results.single.advertisementData.serviceUuids, [_serviceUuid]);
  });

  test('scan sends only the LE transport discovery filter', () async {
    final fixture = await _BlueZFixture.start();
    addTearDown(fixture.close);

    await fixture.backend.scan(forServices: const [_serviceUuid]);

    expect(
      fixture.adapter.discoveryFilter,
      {'Transport': const DBusString('le')},
    );
  });

  test('GATT hierarchy maps canonical UUIDs and all eight flags', () async {
    final fixture = await _BlueZFixture.start(
      withDevice: true,
      withGatt: true,
    );
    addTearDown(fixture.close);
    final session = const PeripheralSession(peripheralIdentifier: _address);

    final services =
        (await fixture.backend.services(session: session)).toList();
    final characteristics = (await fixture.backend.characteristics(
      session: session,
      serviceUuid: _serviceUuid,
    ))
        .toList();

    expect(services.single.uuid, _serviceUuid);
    expect(services.single.isPrimary, isTrue);
    expect(characteristics.single.uuid, _characteristicUuid);
    expect(characteristics.single.descriptors!.single.uuid, _descriptorUuid);
    final properties = characteristics.single.properties!;
    expect(properties.broadcast, isTrue);
    expect(properties.read, isTrue);
    expect(properties.writeWithoutResponse, isTrue);
    expect(properties.write, isTrue);
    expect(properties.notify, isTrue);
    expect(properties.indicate, isTrue);
    expect(properties.authenticatedSignedWrites, isTrue);
    expect(properties.extendedProperties, isTrue);
    expect(properties.notifyEncryptionRequired, isFalse);
    expect(properties.indicateEncryptionRequired, isFalse);
  });
}

Future<void> _waitUntil(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 3));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Timed out waiting for an in-process D-Bus event');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

final class _BlueZFixture {
  _BlueZFixture._({
    required this.server,
    required this.serviceBus,
    required this.clientBus,
    required this.bluezClient,
    required this.backend,
    required this.adapter,
    required this.device,
  });

  final DBusServer server;
  final DBusClient serviceBus;
  final DBusClient clientBus;
  final BlueZClient bluezClient;
  final ButaneDartBluez backend;
  final _FakeAdapter adapter;
  _FakeDevice? device;
  final List<Future<void> Function()> _cancelers = [];

  static Future<_BlueZFixture> start({
    bool withDevice = false,
    bool withGatt = false,
  }) async {
    final server = DBusServer();
    final address = await server.listenAddress(
      DBusAddress.unix(dir: Directory.systemTemp),
    );
    final serviceBus = DBusClient(
      address,
      authClient: DBusAuthClient(uid: '0', requestUnixFd: false),
    );
    final clientBus = DBusClient(
      address,
      authClient: DBusAuthClient(uid: '0', requestUnixFd: false),
    );
    await serviceBus.requestName('org.bluez');
    await serviceBus.registerObject(_FakeBlueZRoot());
    final adapter = _FakeAdapter();
    await serviceBus.registerObject(adapter);

    _FakeDevice? device;
    if (withDevice) {
      device = _FakeDevice();
      await serviceBus.registerObject(device);
    }
    if (withGatt) {
      await serviceBus.registerObject(_FakeGattService());
      await serviceBus.registerObject(_FakeGattCharacteristic());
      await serviceBus.registerObject(_FakeGattDescriptor());
    }

    final bluezClient = BlueZClient(bus: clientBus);
    return _BlueZFixture._(
      server: server,
      serviceBus: serviceBus,
      clientBus: clientBus,
      bluezClient: bluezClient,
      backend: ButaneDartBluez(client: bluezClient),
      adapter: adapter,
      device: device,
    );
  }

  void track<T>(StreamSubscription<T> subscription) {
    _cancelers.add(subscription.cancel);
  }

  Future<_FakeDevice> addDevice() async {
    final added = _FakeDevice();
    device = added;
    await serviceBus.registerObject(added);
    return added;
  }

  Future<void> close() async {
    for (final cancel in _cancelers.reversed) {
      await cancel();
    }
    await bluezClient.close();
    await clientBus.close();
    await serviceBus.close();
    await server.close();
  }
}

final class _FakeBlueZRoot extends DBusObject {
  _FakeBlueZRoot()
      : super(const DBusObjectPath.unchecked('/'), isObjectManager: true);
}

abstract base class _FakePropertiesObject extends DBusObject {
  _FakePropertiesObject(super.path, this.interfaceName, this.properties);

  final String interfaceName;
  final Map<String, DBusValue> properties;

  @override
  Map<String, Map<String, DBusValue>> get interfacesAndProperties => {
        interfaceName: properties,
      };

  Future<void> change(String name, DBusValue value) async {
    properties[name] = value;
    await emitPropertiesChanged(
      interfaceName,
      changedProperties: {name: value},
    );
  }
}

final class _FakeAdapter extends _FakePropertiesObject {
  _FakeAdapter()
      : super(
          _adapterPath,
          'org.bluez.Adapter1',
          {
            'Address': const DBusString('00:11:22:33:44:55'),
            'Powered': const DBusBoolean(true),
            'Discovering': const DBusBoolean(false),
          },
        );

  Map<String, DBusValue>? discoveryFilter;

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall methodCall) async {
    if (methodCall.interface != interfaceName) {
      return DBusMethodErrorResponse.unknownInterface();
    }
    switch (methodCall.name) {
      case 'SetDiscoveryFilter':
        discoveryFilter = methodCall.values.single.asStringVariantDict();
        return DBusMethodSuccessResponse();
      case 'StartDiscovery':
        properties['Discovering'] = const DBusBoolean(true);
        return DBusMethodSuccessResponse();
      case 'StopDiscovery':
        properties['Discovering'] = const DBusBoolean(false);
        return DBusMethodSuccessResponse();
      case 'RemoveDevice':
        return DBusMethodSuccessResponse();
    }
    return DBusMethodErrorResponse.unknownMethod();
  }
}

final class _FakeDevice extends _FakePropertiesObject {
  _FakeDevice()
      : super(
          _devicePath,
          'org.bluez.Device1',
          {
            'Adapter': _adapterPath,
            'Address': const DBusString(_address),
            'AddressType': const DBusString('random'),
            'Alias': const DBusString('Butane peer'),
            'Name': const DBusString('Butane peer'),
            'Connected': const DBusBoolean(false),
            'RSSI': const DBusInt16(-70),
            'TxPower': const DBusInt16(4),
            'UUIDs': DBusArray.string(const [_serviceUuid]),
            'ServicesResolved': const DBusBoolean(true),
          },
        );
}

final class _FakeGattService extends _FakePropertiesObject {
  _FakeGattService()
      : super(
          _servicePath,
          'org.bluez.GattService1',
          {
            'UUID': const DBusString(_serviceUuid),
            'Primary': const DBusBoolean(true),
            'Device': _devicePath,
          },
        );
}

final class _FakeGattCharacteristic extends _FakePropertiesObject {
  _FakeGattCharacteristic()
      : super(
          _characteristicPath,
          'org.bluez.GattCharacteristic1',
          {
            'UUID': const DBusString(_characteristicUuid),
            'Service': _servicePath,
            'Flags': DBusArray.string(const [
              'broadcast',
              'read',
              'write-without-response',
              'write',
              'notify',
              'indicate',
              'authenticated-signed-writes',
              'extended-properties',
            ]),
          },
        );
}

final class _FakeGattDescriptor extends _FakePropertiesObject {
  _FakeGattDescriptor()
      : super(
          _descriptorPath,
          'org.bluez.GattDescriptor1',
          {
            'UUID': const DBusString(_descriptorUuid),
            'Characteristic': _characteristicPath,
          },
        );
}
