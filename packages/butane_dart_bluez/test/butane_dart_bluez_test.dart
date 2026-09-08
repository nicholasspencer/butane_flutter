// The Flutter analyzer excludes dart:mirrors even though these VM-only tests
// run with `dart test`, where it is available.
// ignore_for_file: uri_does_not_exist, undefined_function, cast_to_non_type, undefined_identifier

import 'dart:async';
import 'dart:io';
import 'dart:mirrors';
import 'dart:typed_data';

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
const _forcedErrorName = 'org.bluez.Error.Failed';
const _forcedErrorMessage = 'forced failure';
const _mutableService = MutableService(
  uuid: _serviceUuid,
  characteristics: [
    MutableCharacteristic(
      uuid: _characteristicUuid,
      properties: CharacteristicProperty(write: true, notify: true),
      permissions: CharacteristicPermission(writeable: true),
    ),
  ],
);

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

  test('writeCharacteristic reports the WriteValue D-Bus error', () async {
    final fixture = await _BlueZFixture.start(
      withDevice: true,
      withGatt: true,
    );
    addTearDown(fixture.close);
    fixture.characteristic.methodErrors['WriteValue'] = _forcedMethodError();

    await expectLater(
      fixture.backend.writeCharacteristic(
        session: const PeripheralSession(peripheralIdentifier: _address),
        serviceUuid: _serviceUuid,
        characteristicUuid: _characteristicUuid,
        value: Uint8List.fromList([1, 2, 3]),
      ),
      throwsA(
        _stateErrorContaining([
          'WriteValue',
          _characteristicPath.value,
          _forcedErrorName,
          _forcedErrorMessage,
        ]),
      ),
    );
    expect(fixture.characteristic.methodNames, ['WriteValue']);
  });

  test('observeCharacteristic reports the StartNotify D-Bus error', () async {
    final fixture = await _BlueZFixture.start(
      withDevice: true,
      withGatt: true,
    );
    addTearDown(fixture.close);
    fixture.characteristic.methodErrors['StartNotify'] = _forcedMethodError();

    await expectLater(
      fixture.backend.observeCharacteristic(
        session: const PeripheralSession(peripheralIdentifier: _address),
        serviceUuid: _serviceUuid,
        characteristicUuid: _characteristicUuid,
      ),
      throwsA(
        _stateErrorContaining([
          'StartNotify',
          _characteristicPath.value,
          _forcedErrorName,
          _forcedErrorMessage,
        ]),
      ),
    );
    expect(fixture.characteristic.methodNames, ['StartNotify']);
  });

  test('observeCharacteristic reports the StopNotify D-Bus error', () async {
    final fixture = await _BlueZFixture.start(
      withDevice: true,
      withGatt: true,
    );
    addTearDown(fixture.close);
    fixture.characteristic.methodErrors['StopNotify'] = _forcedMethodError();

    await expectLater(
      fixture.backend.observeCharacteristic(
        session: const PeripheralSession(peripheralIdentifier: _address),
        serviceUuid: _serviceUuid,
        characteristicUuid: _characteristicUuid,
        observe: false,
      ),
      throwsA(
        _stateErrorContaining([
          'StopNotify',
          _characteristicPath.value,
          _forcedErrorName,
          _forcedErrorMessage,
        ]),
      ),
    );
    expect(fixture.characteristic.methodNames, ['StopNotify']);
  });

  test('addService reports the RegisterApplication D-Bus error', () async {
    final fixture = await _BlueZFixture.start();
    addTearDown(fixture.close);
    fixture.adapter.methodErrors['RegisterApplication'] = _forcedMethodError();

    await expectLater(
      fixture.backend.addService(service: _mutableService),
      throwsA(
        _stateErrorContaining([
          'RegisterApplication',
          _forcedErrorName,
          _forcedErrorMessage,
        ]),
      ),
    );
    expect(
      await fixture.backend.updateValue(
        serviceUuid: _serviceUuid,
        characteristicUuid: _characteristicUuid,
        value: Uint8List.fromList([1]),
      ),
      isFalse,
    );
  });

  test('startAdvertising clears state after RegisterAdvertisement error',
      () async {
    final fixture = await _BlueZFixture.start();
    addTearDown(fixture.close);
    fixture.adapter.methodErrors['RegisterAdvertisement'] =
        _forcedMethodError();

    await expectLater(
      fixture.backend.startAdvertising(serviceUuids: const [_serviceUuid]),
      throwsA(
        _stateErrorContaining([
          'RegisterAdvertisement',
          _forcedErrorName,
          _forcedErrorMessage,
        ]),
      ),
    );
    await fixture.backend.stopAdvertising();
    expect(
      fixture.adapter.managerMethodNames,
      ['RegisterAdvertisement'],
    );

    fixture.adapter.methodErrors.remove('RegisterAdvertisement');
    await fixture.backend.startAdvertising(serviceUuids: const [_serviceUuid]);

    expect(
      fixture.adapter.managerObjectPaths,
      [
        const DBusObjectPath.unchecked(
          '/com/nicospencer/butane/advertisement1',
        ),
        const DBusObjectPath.unchecked(
          '/com/nicospencer/butane/advertisement2',
        ),
      ],
    );
  });

  test('stopAdvertising swallows UnregisterAdvertisement error', () async {
    final fixture = await _BlueZFixture.start();
    addTearDown(fixture.close);

    await fixture.backend.startAdvertising(serviceUuids: const [_serviceUuid]);
    fixture.adapter.methodErrors['UnregisterAdvertisement'] =
        _forcedMethodError();
    await fixture.backend.stopAdvertising();
    await fixture.backend.stopAdvertising();

    expect(
      fixture.adapter.managerMethodNames
          .where((name) => name == 'UnregisterAdvertisement'),
      hasLength(1),
    );
    fixture.adapter.methodErrors.remove('UnregisterAdvertisement');
    await fixture.backend.startAdvertising(serviceUuids: const [_serviceUuid]);
    expect(
      fixture.adapter.managerObjectPaths,
      [
        const DBusObjectPath.unchecked(
          '/com/nicospencer/butane/advertisement1',
        ),
        const DBusObjectPath.unchecked(
          '/com/nicospencer/butane/advertisement1',
        ),
        const DBusObjectPath.unchecked(
          '/com/nicospencer/butane/advertisement2',
        ),
      ],
    );
  });

  test('removeAllServices swallows UnregisterApplication error', () async {
    final fixture = await _BlueZFixture.start();
    addTearDown(fixture.close);

    await fixture.backend.addService(service: _mutableService);
    expect(
      fixture.adapter.managerObjectPaths.single,
      const DBusObjectPath.unchecked('/com/nicospencer/butane/app1'),
    );
    fixture.adapter.methodErrors['UnregisterApplication'] =
        _forcedMethodError();
    await fixture.backend.removeAllServices();
    await fixture.backend.removeAllServices();

    expect(
      fixture.adapter.managerMethodNames
          .where((name) => name == 'UnregisterApplication'),
      hasLength(1),
    );
    expect(
      await fixture.backend.updateValue(
        serviceUuid: _serviceUuid,
        characteristicUuid: _characteristicUuid,
        value: Uint8List.fromList([1]),
      ),
      isFalse,
    );
    fixture.adapter.methodErrors.remove('UnregisterApplication');
    await fixture.backend.addService(service: _mutableService);
    expect(
      fixture.adapter.managerObjectPaths,
      [
        const DBusObjectPath.unchecked('/com/nicospencer/butane/app1'),
        const DBusObjectPath.unchecked('/com/nicospencer/butane/app1'),
        const DBusObjectPath.unchecked('/com/nicospencer/butane/app2'),
      ],
    );
  });

  test('startAdvertising reports a GetManagedObjects D-Bus error', () async {
    final fixture = await _BlueZFixture.start();
    addTearDown(fixture.close);

    expect(await fixture.backend.clientState(), ClientState.poweredOn);
    await fixture.installFailingObjectManager();

    await expectLater(
      fixture.backend.startAdvertising(serviceUuids: const [_serviceUuid]),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'BlueZ GetManagedObjects returned no data',
        ),
      ),
    );
  });

  test('characteristicValueStream emits Value property changes', () async {
    final fixture = await _BlueZFixture.start(
      withDevice: true,
      withGatt: true,
    );
    addTearDown(fixture.close);
    const session = PeripheralSession(peripheralIdentifier: _address);

    await fixture.backend.observeCharacteristic(
      session: session,
      serviceUuid: _serviceUuid,
      characteristicUuid: _characteristicUuid,
    );
    final values = <Uint8List>[];
    final received = Completer<void>();
    fixture.track(
      fixture.backend
          .characteristicValueStream(
            session: session,
            serviceUuid: _serviceUuid,
            characteristicUuid: _characteristicUuid,
          )
          .timeout(const Duration(seconds: 3))
          .listen(
        (value) {
          values.add(value);
          if (!received.isCompleted) received.complete();
        },
        onError: received.completeError,
      ),
    );
    await fixture.peripheralBus.ping();

    await fixture.characteristic.change(
      'Value',
      DBusArray.byte([1, 2, 3]),
    );

    await received.future;
    expect(values, [
      Uint8List.fromList([1, 2, 3]),
    ]);
  });
}

DBusMethodErrorResponse _forcedMethodError() => DBusMethodErrorResponse(
      _forcedErrorName,
      [const DBusString(_forcedErrorMessage)],
    );

Matcher _stateErrorContaining(List<String> fragments) =>
    isA<StateError>().having(
      (error) => error.message,
      'message',
      allOf(fragments.map(contains).toList()),
    );

void _injectPeripheralBus(ButaneDartBluez backend, DBusClient bus) {
  final instance = reflect(backend);
  final library = instance.type.owner as LibraryMirror;
  instance.setField(
    MirrorSystem.getSymbol('_peripheralBus', library),
    bus,
  );
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
    required this.peripheralBus,
    required this.bluezClient,
    required this.backend,
    required this.root,
    required this.adapter,
    required this.device,
    required this.characteristic,
  });

  final DBusServer server;
  final DBusClient serviceBus;
  final DBusClient clientBus;
  final DBusClient peripheralBus;
  final BlueZClient bluezClient;
  final ButaneDartBluez backend;
  final _FakeBlueZRoot root;
  final _FakeAdapter adapter;
  _FakeDevice? device;
  final _FakeGattCharacteristic characteristic;
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
    final peripheralBus = DBusClient(
      address,
      authClient: DBusAuthClient(uid: '0', requestUnixFd: false),
    );
    await serviceBus.requestName('org.bluez');
    final root = _FakeBlueZRoot();
    await serviceBus.registerObject(root);
    final adapter = _FakeAdapter();
    await serviceBus.registerObject(adapter);

    _FakeDevice? device;
    if (withDevice) {
      device = _FakeDevice();
      await serviceBus.registerObject(device);
    }
    final characteristic = _FakeGattCharacteristic();
    if (withGatt) {
      await serviceBus.registerObject(_FakeGattService());
      await serviceBus.registerObject(characteristic);
      await serviceBus.registerObject(_FakeGattDescriptor());
    }

    final bluezClient = BlueZClient(bus: clientBus);
    final backend = ButaneDartBluez(client: bluezClient);
    _injectPeripheralBus(backend, peripheralBus);
    return _BlueZFixture._(
      server: server,
      serviceBus: serviceBus,
      clientBus: clientBus,
      peripheralBus: peripheralBus,
      bluezClient: bluezClient,
      backend: backend,
      root: root,
      adapter: adapter,
      device: device,
      characteristic: characteristic,
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

  Future<void> installFailingObjectManager() async {
    await serviceBus.unregisterObject(root);
    await serviceBus.registerObject(_FailingObjectManager());
  }

  Future<void> close() async {
    for (final cancel in _cancelers.reversed) {
      await cancel();
    }
    await bluezClient.close();
    await clientBus.close();
    await peripheralBus.close();
    await serviceBus.close();
    await server.close();
  }
}

final class _FakeBlueZRoot extends DBusObject {
  _FakeBlueZRoot()
      : super(const DBusObjectPath.unchecked('/'), isObjectManager: true);
}

final class _FailingObjectManager extends DBusObject {
  _FailingObjectManager() : super(const DBusObjectPath.unchecked('/'));

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall methodCall) async {
    if (methodCall.interface == 'org.freedesktop.DBus.ObjectManager' &&
        methodCall.name == 'GetManagedObjects') {
      return _forcedMethodError();
    }
    return DBusMethodErrorResponse.unknownMethod();
  }
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
  final Map<String, DBusMethodErrorResponse> methodErrors = {};
  final List<String> managerMethodNames = [];
  final List<DBusObjectPath> managerObjectPaths = [];

  @override
  Map<String, Map<String, DBusValue>> get interfacesAndProperties => {
        ...super.interfacesAndProperties,
        'org.bluez.LEAdvertisingManager1': {},
        'org.bluez.GattManager1': {},
      };

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall methodCall) async {
    if (methodCall.interface == interfaceName) {
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
    if (methodCall.interface == 'org.bluez.LEAdvertisingManager1' ||
        methodCall.interface == 'org.bluez.GattManager1') {
      managerMethodNames.add(methodCall.name);
      if (methodCall.values.isNotEmpty &&
          methodCall.values.first is DBusObjectPath) {
        managerObjectPaths.add(methodCall.values.first as DBusObjectPath);
      }
      final error = methodErrors[methodCall.name];
      if (error != null) return error;
      switch (methodCall.name) {
        case 'RegisterAdvertisement':
        case 'UnregisterAdvertisement':
        case 'RegisterApplication':
        case 'UnregisterApplication':
          return DBusMethodSuccessResponse();
      }
      return DBusMethodErrorResponse.unknownMethod();
    }
    return DBusMethodErrorResponse.unknownInterface();
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

  final Map<String, DBusMethodErrorResponse> methodErrors = {};
  final List<String> methodNames = [];

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall methodCall) async {
    if (methodCall.interface != interfaceName) {
      return DBusMethodErrorResponse.unknownInterface();
    }
    methodNames.add(methodCall.name);
    final error = methodErrors[methodCall.name];
    if (error != null) return error;
    switch (methodCall.name) {
      case 'WriteValue':
      case 'StartNotify':
      case 'StopNotify':
        return DBusMethodSuccessResponse();
    }
    return DBusMethodErrorResponse.unknownMethod();
  }
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
