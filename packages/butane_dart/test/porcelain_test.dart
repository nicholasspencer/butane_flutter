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
}

/// A pure-Dart [api.ButanePlatformInterface] test double. The abstraction is an
/// `abstract base class`, so the double must `extends` it (cross-library
/// `implements` is forbidden) and override every member; only the client-state
/// surface is wired up — the rest throw.
final class _FakePlatform extends api.ButanePlatformInterface {
  _FakePlatform({
    this.clientStateValue = api.ClientState.poweredOn,
    Stream<api.ClientState>? clientStates,
  }) : _clientStates = clientStates;

  final api.ClientState clientStateValue;
  final Stream<api.ClientState>? _clientStates;

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
  }) =>
      throw UnimplementedError();

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
  }) =>
      throw UnimplementedError();

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
  }) =>
      throw UnimplementedError();

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
  Future<int> readRssi({required api.PeripheralSession session}) =>
      throw UnimplementedError();

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
