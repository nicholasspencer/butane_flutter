import 'package:butane_dart/butane_dart.dart' show ButaneException;
import 'package:butane_dart/interface.dart';
import 'package:butane_platform_interface/channels.dart';
import 'package:butane_platform_interface/src/channels/api.g.dart' as api;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:test/test.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

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

  test('bridges bonding calls and maps every current state', () async {
    await platform.bond(session: session);

    expect(hostApi.bondCall?.peripheralIdentifier, 'peripheral');
    expect(hostApi.bondCall?.clientIdentifier, 'client');
    expect(hostApi.bondCall?.adapterIdentifier, 'adapter');
    expect(hostApi.bondCall?.restorationIdentifier, 'restoration');

    const mappings = {
      api.BondState.none: BondState.none,
      api.BondState.bonding: BondState.bonding,
      api.BondState.bonded: BondState.bonded,
    };
    for (final MapEntry(key: channelState, value: expected)
        in mappings.entries) {
      hostApi.bondStateValue = channelState;
      expect(await platform.bondState(session: session), expected);
    }

    expect(hostApi.bondStateCall?.peripheralIdentifier, 'peripheral');
    expect(hostApi.bondStateCall?.clientIdentifier, 'client');
    expect(hostApi.bondStateCall?.adapterIdentifier, 'adapter');
    expect(hostApi.bondStateCall?.restorationIdentifier, 'restoration');
  });

  test('filters bond callbacks by client and peripheral identifiers', () async {
    final flutterApi = _TestFlutterApi();
    platform = _TestButanePlatform(hostApi, flutterApi: flutterApi);
    final states = platform.bondStateStream(session: session).take(1).toList();

    flutterApi.emitBondState(
      api.PeripheralSession(
        peripheralIdentifier: 'peripheral',
        clientIdentifier: 'other-client',
      ),
      api.BondState.none,
    );
    flutterApi.emitBondState(
      api.PeripheralSession(
        peripheralIdentifier: 'other-peripheral',
        clientIdentifier: 'client',
      ),
      api.BondState.bonded,
    );
    flutterApi.emitBondState(_expectedSession, api.BondState.bonding);

    expect(await states, [BondState.bonding]);
  });

  test('connect notFound surfaces as ButaneException', () async {
    final cause = PlatformException(
      code: 'notFound',
      message: 'No peripheral found',
      details: const {'platform': 'test-platform'},
    );
    hostApi.thrownError = cause;

    final error = await _captureError(platform.connect(session: session));

    expect(error, isA<ButaneException>());
    final exception = error as ButaneException;
    expect(exception.code, ButaneErrorCode.notFound);
    expect(exception.cause, same(cause));
  });

  test('scan awaits unavailable platform failures', () async {
    final cause = PlatformException(
      code: 'unavailable',
      message: 'Bluetooth is unavailable',
      details: const {'platform': 'test-platform'},
    );
    hostApi.thrownError = cause;

    final error = await _captureError(platform.scan());

    expect(error, isA<ButaneException>());
    final exception = error as ButaneException;
    expect(exception.code, ButaneErrorCode.unavailable);
    expect(exception.cause, same(cause));
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
  _TestButanePlatform(this._hostApi, {ButaneFlutterApi? flutterApi})
      : _flutterApi = flutterApi;

  final api.ButaneHostApi _hostApi;
  ButaneFlutterApi? _flutterApi;

  @override
  api.ButaneHostApi get hostApi => _hostApi;

  @override
  ButaneFlutterApi get flutterApi => _flutterApi ??= ButaneFlutterApi();
}

final class _TestFlutterApi extends ButaneFlutterApi {
  void emitBondState(api.PeripheralSession session, api.BondState state) {
    onBondState(session, state);
  }
}

final class _FakeHostApi extends api.ButaneHostApi {
  Uint8List descriptorValue = Uint8List(0);
  int effectiveMtu = 23;
  api.BondState bondStateValue = api.BondState.none;
  Object? thrownError;

  api.PeripheralSession? bondCall;
  api.PeripheralSession? bondStateCall;

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

  void _throwConfiguredError() {
    if (thrownError case final error?) {
      throw error;
    }
  }

  @override
  Future<void> scan({
    api.ClientSession? session,
    List<String>? forServices,
  }) async {
    _throwConfiguredError();
  }

  @override
  Future<void> connect({required api.PeripheralSession session}) async {
    _throwConfiguredError();
  }

  @override
  Future<void> bond({required api.PeripheralSession session}) async {
    bondCall = session;
  }

  @override
  Future<api.BondState> bondState({
    required api.PeripheralSession session,
  }) async {
    bondStateCall = session;
    return bondStateValue;
  }

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
    _throwConfiguredError();
    return effectiveMtu;
  }
}
