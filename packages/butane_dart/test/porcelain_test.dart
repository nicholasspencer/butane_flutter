import 'dart:async';
import 'dart:typed_data';

import 'package:butane_dart/butane_dart.dart';
import 'package:butane_dart/interface.dart' as api;
import 'package:test/test.dart';

void main() {
  group('PeerManagerState.fromApi', () {
    test('maps every ClientState', () {
      expect(
        PeerManagerState.fromApi(api.ClientState.unknown),
        PeerManagerState.unknown,
      );
      expect(
        PeerManagerState.fromApi(api.ClientState.resetting),
        PeerManagerState.resetting,
      );
      expect(
        PeerManagerState.fromApi(api.ClientState.unsupported),
        PeerManagerState.unsupported,
      );
      expect(
        PeerManagerState.fromApi(api.ClientState.unauthorized),
        PeerManagerState.unauthorized,
      );
      expect(
        PeerManagerState.fromApi(api.ClientState.poweredOff),
        PeerManagerState.poweredOff,
      );
      expect(
        PeerManagerState.fromApi(api.ClientState.poweredOn),
        PeerManagerState.poweredOn,
      );
    });
  });

  group('CentralManager with an injected pure-Dart platform', () {
    test('state reads platform.clientState', () async {
      final manager = CentralManager(
        platform: _FakePlatform(clientStateValue: api.ClientState.poweredOn),
      );

      expect(await manager.state, PeerManagerState.poweredOn);

      manager.dispose();
    });

    test('stateStream maps platform events via PlatformStreamController',
        () async {
      final source = StreamController<api.ClientState>();
      final manager = CentralManager(
        platform: _FakePlatform(
          clientStateValue: api.ClientState.poweredOff,
          clientStates: source.stream,
        ),
      );

      final emitted = <PeerManagerState>[];
      final subscription = manager.stateStream.listen(emitted.add);

      // Let onListen_ run (seeds the stream with the sinkValue).
      await Future<void>.delayed(Duration.zero);
      source.add(api.ClientState.poweredOn);
      source.add(api.ClientState.unauthorized);
      await Future<void>.delayed(Duration.zero);

      await subscription.cancel();
      await source.close();
      manager.dispose();

      expect(emitted, contains(PeerManagerState.poweredOff)); // sinkValue seed
      expect(emitted, contains(PeerManagerState.poweredOn));
      expect(emitted, contains(PeerManagerState.unauthorized));
    });
  });

  group('Peripheral descriptor and MTU operations', () {
    test('forward the discovered attribute chain to the platform', () async {
      final readValue = Uint8List.fromList([1, 2, 3]);
      final writeValue = Uint8List.fromList([4, 5, 6]);
      final platform = _FakePlatform(
        peripheralsValue: const [
          api.Peripheral(
            session: api.PeripheralSession(
              peripheralIdentifier: 'peripheral-id',
            ),
            name: 'test peripheral',
            rssi: -42,
            state: api.ConnectionState.connected,
          ),
        ],
        servicesValue: const [
          api.Service(uuid: 'service-uuid', isPrimary: true),
        ],
        characteristicsValue: const [
          api.Characteristic(
            uuid: 'characteristic-uuid',
            descriptors: [
              api.Descriptor(uuid: 'descriptor-uuid'),
            ],
          ),
        ],
        descriptorReadValue: readValue,
        effectiveMtu: 185,
      );
      final manager = CentralManager(
        clientIdentifier: 'client-id',
        restorationIdentifier: 'restoration-id',
        platform: platform,
      );

      final peripheral = (await manager.peripherals()).single;
      final service = (await peripheral.services).single;
      final characteristic = (await service.characteristics).single;
      final descriptor = characteristic.descriptors.single;

      expect(characteristic.descriptors, same(characteristic.descriptors));
      expect(descriptor.characteristic, same(characteristic));
      expect(await descriptor.read(), readValue);
      await descriptor.write(value: writeValue);
      expect(await peripheral.requestMtu(517), 185);

      final readInvocation = platform.readDescriptorInvocation!;
      expect(readInvocation.session.peripheralIdentifier, 'peripheral-id');
      expect(readInvocation.session.clientIdentifier, 'client-id');
      expect(readInvocation.session.restorationIdentifier, 'restoration-id');
      expect(readInvocation.serviceUuid, 'service-uuid');
      expect(readInvocation.characteristicUuid, 'characteristic-uuid');
      expect(readInvocation.descriptorUuid, 'descriptor-uuid');

      final writeInvocation = platform.writeDescriptorInvocation!;
      expect(writeInvocation.session.peripheralIdentifier, 'peripheral-id');
      expect(writeInvocation.session.clientIdentifier, 'client-id');
      expect(writeInvocation.session.restorationIdentifier, 'restoration-id');
      expect(writeInvocation.serviceUuid, 'service-uuid');
      expect(writeInvocation.characteristicUuid, 'characteristic-uuid');
      expect(writeInvocation.descriptorUuid, 'descriptor-uuid');
      expect(writeInvocation.value, same(writeValue));

      final mtuInvocation = platform.requestMtuInvocation!;
      expect(mtuInvocation.session.peripheralIdentifier, 'peripheral-id');
      expect(mtuInvocation.session.clientIdentifier, 'client-id');
      expect(mtuInvocation.session.restorationIdentifier, 'restoration-id');
      expect(mtuInvocation.mtu, 517);

      manager.dispose();
    });

    test('detached descriptor read fails loudly', () {
      const descriptor = Descriptor(uuid: UuidIdentifier('descriptor-uuid'));

      expect(
        descriptor.read,
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'Cannot access descriptor descriptor-uuid without a characteristic, service, and peripheral',
          ),
        ),
      );
    });

    test('detached descriptor write fails loudly', () {
      const descriptor = Descriptor(uuid: UuidIdentifier('descriptor-uuid'));

      expect(
        () => descriptor.write(value: Uint8List(0)),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'Cannot access descriptor descriptor-uuid without a characteristic, service, and peripheral',
          ),
        ),
      );
    });
  });
}

/// A pure-Dart [api.ButanePlatformInterface] test double. The abstraction is an
/// `abstract base class`, so the double must `extends` it (cross-library
/// `implements` is forbidden) and override every member; only the surfaces
/// exercised here are wired up — the rest throw.
final class _FakePlatform extends api.ButanePlatformInterface {
  _FakePlatform({
    this.clientStateValue = api.ClientState.poweredOn,
    Stream<api.ClientState>? clientStates,
    this.peripheralsValue = const [],
    this.servicesValue = const [],
    this.characteristicsValue = const [],
    Uint8List? descriptorReadValue,
    this.effectiveMtu = 23,
  })  : _clientStates = clientStates,
        descriptorReadValue = descriptorReadValue ?? Uint8List(0);

  final api.ClientState clientStateValue;
  final Stream<api.ClientState>? _clientStates;
  final Iterable<api.Peripheral> peripheralsValue;
  final Iterable<api.Service> servicesValue;
  final Iterable<api.Characteristic> characteristicsValue;
  final Uint8List descriptorReadValue;
  final int effectiveMtu;

  ({
    api.PeripheralSession session,
    String serviceUuid,
    String characteristicUuid,
    String descriptorUuid,
  })? readDescriptorInvocation;

  ({
    api.PeripheralSession session,
    String serviceUuid,
    String characteristicUuid,
    String descriptorUuid,
    Uint8List value,
  })? writeDescriptorInvocation;

  ({api.PeripheralSession session, int mtu})? requestMtuInvocation;

  @override
  Future<api.ClientState> clientState([api.Session? session]) async =>
      clientStateValue;

  @override
  Stream<api.ClientState> clientStateStream([api.Session? session]) =>
      _clientStates ?? const Stream<api.ClientState>.empty();

  // --- Unused by these tests ------------------------------------------------

  @override
  Future<void> scan({Iterable<String>? forServices, api.Session? session}) =>
      throw UnimplementedError();

  @override
  Stream<api.ScanResult> scanStream([api.Session? session]) =>
      throw UnimplementedError();

  @override
  Future<void> cancelScan({api.Session? session}) => throw UnimplementedError();

  @override
  Future<Iterable<api.Peripheral>> peripherals({
    Iterable<String> peripheralIdentifiers = const [],
    api.Session? session,
  }) async =>
      peripheralsValue;

  @override
  Future<Iterable<api.Peripheral>> connectedPeripherals({
    Iterable<String> serviceUuids = const [],
    api.Session? session,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> connect({required api.PeripheralSession session}) =>
      throw UnimplementedError();

  @override
  Future<void> cancelConnection({required api.PeripheralSession session}) =>
      throw UnimplementedError();

  @override
  Future<api.ConnectionState> connectionState({
    required api.PeripheralSession session,
  }) =>
      throw UnimplementedError();

  @override
  Stream<api.ConnectionState> connectionStateStream({
    required api.PeripheralSession session,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> discoverServices({
    required api.PeripheralSession session,
    Iterable<String>? serviceUuids,
  }) =>
      throw UnimplementedError();

  @override
  Future<Iterable<api.Service>> services({
    required api.PeripheralSession session,
  }) async =>
      servicesValue;

  @override
  Future<void> discoverCharacteristics({
    required api.PeripheralSession session,
    required String serviceUuid,
    Iterable<String>? characteristicUuids,
  }) =>
      throw UnimplementedError();

  @override
  Future<Iterable<api.Characteristic>> characteristics({
    required api.PeripheralSession session,
    required String serviceUuid,
  }) async =>
      characteristicsValue;

  @override
  Future<Uint8List> readCharacteristic({
    required api.PeripheralSession session,
    required String serviceUuid,
    required String characteristicUuid,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> writeCharacteristic({
    required api.PeripheralSession session,
    required String serviceUuid,
    required String characteristicUuid,
    required Uint8List value,
    bool withoutResponse = false,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> observeCharacteristic({
    required api.PeripheralSession session,
    required String serviceUuid,
    required String characteristicUuid,
    bool observe = true,
  }) =>
      throw UnimplementedError();

  @override
  Stream<Uint8List> characteristicValueStream({
    required api.PeripheralSession session,
    required String serviceUuid,
    required String characteristicUuid,
  }) =>
      throw UnimplementedError();

  @override
  Future<Uint8List> readDescriptor({
    required api.PeripheralSession session,
    required String serviceUuid,
    required String characteristicUuid,
    required String descriptorUuid,
  }) async {
    readDescriptorInvocation = (
      session: session,
      serviceUuid: serviceUuid,
      characteristicUuid: characteristicUuid,
      descriptorUuid: descriptorUuid,
    );
    return descriptorReadValue;
  }

  @override
  Future<void> writeDescriptor({
    required api.PeripheralSession session,
    required String serviceUuid,
    required String characteristicUuid,
    required String descriptorUuid,
    required Uint8List value,
  }) async {
    writeDescriptorInvocation = (
      session: session,
      serviceUuid: serviceUuid,
      characteristicUuid: characteristicUuid,
      descriptorUuid: descriptorUuid,
      value: value,
    );
  }

  @override
  Future<int> readRssi({required api.PeripheralSession session}) =>
      throw UnimplementedError();

  @override
  Future<int> requestMtu({
    required api.PeripheralSession session,
    required int mtu,
  }) async {
    requestMtuInvocation = (session: session, mtu: mtu);
    return effectiveMtu;
  }

  @override
  Future<api.ClientState> peripheralManagerState([
    api.PeripheralManagerSession? session,
  ]) =>
      throw UnimplementedError();

  @override
  Stream<api.ClientState> peripheralManagerStateStream([
    api.PeripheralManagerSession? session,
  ]) =>
      throw UnimplementedError();

  @override
  Future<void> startAdvertising({
    api.PeripheralManagerSession? session,
    String? localName,
    Iterable<String>? serviceUuids,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> stopAdvertising({api.PeripheralManagerSession? session}) =>
      throw UnimplementedError();

  @override
  Future<void> addService({
    api.PeripheralManagerSession? session,
    required api.MutableService service,
  }) =>
      throw UnimplementedError();

  @override
  Stream<({String serviceUuid, String? error})> serviceAddedStream([
    api.PeripheralManagerSession? session,
  ]) =>
      throw UnimplementedError();

  @override
  Future<void> removeService({
    api.PeripheralManagerSession? session,
    required String serviceUuid,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> removeAllServices({api.PeripheralManagerSession? session}) =>
      throw UnimplementedError();

  @override
  Future<void> respondToRequest({
    api.PeripheralManagerSession? session,
    required int requestId,
    required api.AttResult result,
    Uint8List? value,
  }) =>
      throw UnimplementedError();

  @override
  Future<bool> updateValue({
    api.PeripheralManagerSession? session,
    required String serviceUuid,
    required String characteristicUuid,
    required Uint8List value,
  }) =>
      throw UnimplementedError();

  @override
  Stream<api.AttRequest> readRequestStream([
    api.PeripheralManagerSession? session,
  ]) =>
      throw UnimplementedError();

  @override
  Stream<List<api.AttRequest>> writeRequestsStream([
    api.PeripheralManagerSession? session,
  ]) =>
      throw UnimplementedError();
}
