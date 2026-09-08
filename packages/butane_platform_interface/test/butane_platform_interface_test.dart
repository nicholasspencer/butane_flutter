import 'dart:typed_data';

import 'package:butane_dart/interface.dart';
import 'package:butane_platform_interface/channels.dart';
import 'package:butane_platform_interface/src/channels/api.g.dart' as api;
import 'package:test/test.dart';

void main() {
  late _FakeHostApi hostApi;
  late _TestButanePlatform platform;
  late PeripheralSession session;

  setUp(() {
    hostApi = _FakeHostApi();
    platform = _TestButanePlatform(hostApi);
    session = const PeripheralSession(
      peripheralIdentifier: 'peripheral',
      clientIdentifier: 'client',
      adapterIdentifier: 'adapter',
      restorationIdentifier: 'restoration',
    );
  });

  test('bridges descriptor reads without changing arguments', () async {
    hostApi.descriptorValue = Uint8List.fromList([1, 2, 3]);

    final value = await platform.readDescriptor(
      session: session,
      serviceUuid: 'service',
      characteristicUuid: 'characteristic',
      descriptorUuid: 'descriptor',
    );

    expect(value, hostApi.descriptorValue);
    expect(hostApi.readDescriptorCall?.session, _expectedSession);
    expect(hostApi.readDescriptorCall?.serviceUuid, 'service');
    expect(hostApi.readDescriptorCall?.characteristicUuid, 'characteristic');
    expect(hostApi.readDescriptorCall?.descriptorUuid, 'descriptor');
  });

  test('bridges descriptor writes without changing arguments', () async {
    final value = Uint8List.fromList([4, 5, 6]);

    await platform.writeDescriptor(
      session: session,
      serviceUuid: 'service',
      characteristicUuid: 'characteristic',
      descriptorUuid: 'descriptor',
      value: value,
    );

    expect(hostApi.writeDescriptorCall?.session, _expectedSession);
    expect(hostApi.writeDescriptorCall?.serviceUuid, 'service');
    expect(hostApi.writeDescriptorCall?.characteristicUuid, 'characteristic');
    expect(hostApi.writeDescriptorCall?.descriptorUuid, 'descriptor');
    expect(hostApi.writeDescriptorCall?.value, value);
  });

  test('returns the effective MTU from the host', () async {
    hostApi.effectiveMtu = 185;

    final effectiveMtu = await platform.requestMtu(session: session, mtu: 247);

    expect(effectiveMtu, 185);
    expect(hostApi.requestMtuCall?.session, _expectedSession);
    expect(hostApi.requestMtuCall?.mtu, 247);
  });
}

final _expectedSession = api.PeripheralSession(
  peripheralIdentifier: 'peripheral',
  clientIdentifier: 'client',
  adapterIdentifier: 'adapter',
  restorationIdentifier: 'restoration',
);

final class _TestButanePlatform extends ButanePlatform {
  _TestButanePlatform(this._hostApi);

  final api.ButaneHostApi _hostApi;

  @override
  api.ButaneHostApi get hostApi => _hostApi;
}

final class _FakeHostApi extends api.ButaneHostApi {
  Uint8List descriptorValue = Uint8List(0);
  int effectiveMtu = 23;

  ({
    api.PeripheralSession session,
    String serviceUuid,
    String characteristicUuid,
    String descriptorUuid,
  })? readDescriptorCall;

  ({
    api.PeripheralSession session,
    String serviceUuid,
    String characteristicUuid,
    String descriptorUuid,
    Uint8List value,
  })? writeDescriptorCall;

  ({api.PeripheralSession session, int mtu})? requestMtuCall;

  @override
  Future<Uint8List> readDescriptor({
    required api.PeripheralSession session,
    required String serviceUuid,
    required String characteristicUuid,
    required String descriptorUuid,
  }) async {
    readDescriptorCall = (
      session: session,
      serviceUuid: serviceUuid,
      characteristicUuid: characteristicUuid,
      descriptorUuid: descriptorUuid,
    );
    return descriptorValue;
  }

  @override
  Future<void> writeDescriptor({
    required api.PeripheralSession session,
    required String serviceUuid,
    required String characteristicUuid,
    required String descriptorUuid,
    required Uint8List value,
  }) async {
    writeDescriptorCall = (
      session: session,
      serviceUuid: serviceUuid,
      characteristicUuid: characteristicUuid,
      descriptorUuid: descriptorUuid,
      value: value,
    );
  }

  @override
  Future<int> requestMtu({
    required api.PeripheralSession session,
    required int mtu,
  }) async {
    requestMtuCall = (session: session, mtu: mtu);
    return effectiveMtu;
  }
}
