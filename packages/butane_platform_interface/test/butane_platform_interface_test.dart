import 'package:butane_dart/butane_dart.dart' show ButaneException;
import 'package:butane_dart/interface.dart';
import 'package:butane_platform_interface/channels.dart';
import 'package:butane_platform_interface/src/channels/api.g.dart' as api;
import 'package:flutter/services.dart';
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

  test('generated and public error vocabularies stay aligned', () {
    expect(
      api.ButaneErrorCode.values.map((code) => code.name),
      ButaneErrorCode.values.map((code) => code.name),
    );
    expect(
      ButaneErrorCode.values.map((code) => code.name),
      [
        'unsupported',
        'unavailable',
        'poweredOff',
        'notFound',
        'notConnected',
        'connectFailed',
        'disconnected',
        'timeout',
        'invalidArgument',
        'operationFailed',
      ],
    );
  });

  for (final code in ButaneErrorCode.values) {
    test('translates ${code.name} platform exceptions', () async {
      final cause = PlatformException(
        code: code.name,
        message: '${code.name} message',
        details: const {
          'platform': 'test-platform',
          'nativeCode': 'native-code',
        },
      );
      hostApi.thrownError = cause;

      final error = await _captureError(
        platform.requestMtu(session: session, mtu: 247),
      );

      expect(error, isA<ButaneException>());
      final exception = error as ButaneException;
      expect(exception.code, code);
      expect(exception.message, '${code.name} message');
      expect(exception.platform, 'test-platform');
      expect(exception.nativeCode, 'native-code');
      expect(exception.cause, same(cause));
    });
  }

  test('translates unknown platform codes to operationFailed', () async {
    final cause = PlatformException(
      code: 'backendSpecificFailure',
      details: const {
        'platform': 'test-platform',
        'nativeCode': 'ignored-native-code',
      },
    );
    hostApi.thrownError = cause;

    final error = await _captureError(
      platform.requestMtu(session: session, mtu: 247),
    );

    expect(error, isA<ButaneException>());
    final exception = error as ButaneException;
    expect(exception.code, ButaneErrorCode.operationFailed);
    expect(exception.message, 'backendSpecificFailure');
    expect(exception.platform, 'test-platform');
    expect(exception.nativeCode, 'backendSpecificFailure');
    expect(exception.cause, same(cause));
  });

  test('does not rewrite non-PlatformException failures', () async {
    final cause = StateError('test failure');
    hostApi.thrownError = cause;

    final error = await _captureError(
      platform.requestMtu(session: session, mtu: 247),
    );

    expect(error, same(cause));
  });
}

Future<Object> _captureError(Future<Object?> future) async {
  try {
    await future;
  } catch (error) {
    return error;
  }
  throw StateError('Expected the future to fail');
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
  Object? thrownError;

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
    if (thrownError case final error?) {
      throw error;
    }
    return effectiveMtu;
  }
}
