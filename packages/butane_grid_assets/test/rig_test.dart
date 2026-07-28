import 'dart:convert';

import 'package:beads_dart/beads_dart.dart' show Bead, IssueType;
import 'package:butane_grid_assets/butane_grid_assets.dart';
import 'package:test/test.dart';

const rigId = 'nico-ipad-mini';
const liveIpadId = '00008110-001651523CE3801E';
const liveIpad = FlutterDevice(
  id: liveIpadId,
  name: "Nico's iPad mini",
  targetPlatform: 'ios',
  emulator: false,
);

Map<String, Object?> rigMetadata({
  String udid = liveIpadId,
  String platform = 'ios',
  String kind = 'physical',
  String host = 'macos',
  Object? capabilities = '["ble","flutter-profile"]',
}) => <String, Object?>{
  'rig.device_udid': udid,
  'rig.target_platform': platform,
  'rig.device_kind': kind,
  'rig.host_platform': host,
  'rig.capabilities': capabilities,
};

Bead rigBead({Map<String, Object?>? metadata, bool correctType = true}) => Bead(
  id: rigId,
  issueType: correctType ? IssueType.rig : IssueType.role,
  metadata: metadata ?? rigMetadata(),
);

final class _FakeCatalog implements FlutterDeviceCatalog {
  _FakeCatalog(this.result);

  final List<FlutterDevice> result;
  var calls = 0;

  @override
  Future<List<FlutterDevice>> listDevices() async {
    calls += 1;
    return result;
  }
}

final class _ThrowingCatalog implements FlutterDeviceCatalog {
  @override
  Future<List<FlutterDevice>> listDevices() {
    throw Exception('discovery unavailable');
  }
}

Matcher stateErrorContaining(String text) => isA<StateError>().having(
  (error) => error.message,
  'message',
  contains(text),
);

void main() {
  group('RigPreflight', () {
    test(
      'successful resolution preserves every rig and device field',
      () async {
        final catalog = _FakeCatalog(const [liveIpad]);
        final resolved = await RigPreflight(
          lookupRig: (id) async => id == rigId ? rigBead() : null,
          devices: catalog,
        ).resolve(const {'burn.rig': rigId});
        expect(resolved.rig.id, rigId);
        expect(resolved.rig.deviceUdid, liveIpad.id);
        expect(resolved.rig.targetPlatform, 'ios');
        expect(resolved.rig.deviceKind, RigDeviceKind.physical);
        expect(resolved.rig.hostPlatform, 'macos');
        expect(resolved.rig.capabilities, {'ble', 'flutter-profile'});
        expect(resolved.device, same(liveIpad));
        expect(catalog.calls, 1);
      },
    );

    for (final referenceCase in <(String, Map<String, Object?>)>[
      ('missing burn.rig', const {}),
      ('whitespace-only burn.rig', const {'burn.rig': '   '}),
    ]) {
      test(referenceCase.$1, () async {
        var lookupCalls = 0;
        final catalog = _FakeCatalog(const [liveIpad]);
        final preflight = RigPreflight(
          lookupRig: (id) async {
            lookupCalls += 1;
            return rigBead();
          },
          devices: catalog,
        );

        await expectLater(
          preflight.resolve(referenceCase.$2),
          throwsA(stateErrorContaining('burn.rig')),
        );
        expect(lookupCalls, 0);
        expect(catalog.calls, 0);
      });
    }

    test('missing bead', () async {
      final preflight = RigPreflight(
        lookupRig: (id) async => null,
        devices: _FakeCatalog(const [liveIpad]),
      );
      await expectLater(
        preflight.resolve(const {'burn.rig': rigId}),
        throwsA(stateErrorContaining(rigId)),
      );
    });

    test('role-typed bead', () async {
      final preflight = RigPreflight(
        lookupRig: (id) async => rigBead(correctType: false),
        devices: _FakeCatalog(const [liveIpad]),
      );
      await expectLater(
        preflight.resolve(const {'burn.rig': rigId}),
        throwsA(stateErrorContaining(rigId)),
      );
    });

    for (final key in const [
      'rig.device_udid',
      'rig.target_platform',
      'rig.device_kind',
      'rig.host_platform',
    ]) {
      for (final valueCase in const <(String, Object?)>[
        ('missing', null),
        ('empty', ''),
        ('non-string', 7),
      ]) {
        test('${valueCase.$1} value for $key', () async {
          final metadata = rigMetadata();
          if (valueCase.$1 == 'missing') {
            metadata.remove(key);
          } else {
            metadata[key] = valueCase.$2;
          }
          final preflight = RigPreflight(
            lookupRig: (id) async => rigBead(metadata: metadata),
            devices: _FakeCatalog(const [liveIpad]),
          );
          await expectLater(
            preflight.resolve(const {'burn.rig': rigId}),
            throwsA(stateErrorContaining(rigId)),
          );
        });
      }
    }

    for (final valueCase in const <(String, Object?)>[
      ('missing rig.capabilities', null),
      ('empty rig.capabilities', ''),
      ('non-string rig.capabilities', 7),
    ]) {
      test(valueCase.$1, () async {
        final metadata = rigMetadata();
        if (valueCase.$2 == null) {
          metadata.remove('rig.capabilities');
        } else {
          metadata['rig.capabilities'] = valueCase.$2;
        }
        final preflight = RigPreflight(
          lookupRig: (id) async => rigBead(metadata: metadata),
          devices: _FakeCatalog(const [liveIpad]),
        );
        await expectLater(
          preflight.resolve(const {'burn.rig': rigId}),
          throwsA(stateErrorContaining(rigId)),
        );
      });
    }

    for (final capabilitiesCase in const <(String, String)>[
      ('malformed capability JSON', 'not-json'),
      ('capability JSON decoding to a non-list', '{}'),
      ('capability JSON containing a non-string', '["ble",7]'),
    ]) {
      test(capabilitiesCase.$1, () async {
        final preflight = RigPreflight(
          lookupRig: (id) async =>
              rigBead(metadata: rigMetadata(capabilities: capabilitiesCase.$2)),
          devices: _FakeCatalog(const [liveIpad]),
        );
        await expectLater(
          preflight.resolve(const {'burn.rig': rigId}),
          throwsA(stateErrorContaining(rigId)),
        );
      });
    }

    test('invalid device kind', () async {
      final preflight = RigPreflight(
        lookupRig: (id) async =>
            rigBead(metadata: rigMetadata(kind: 'teleporter')),
        devices: _FakeCatalog(const [liveIpad]),
      );
      await expectLater(
        preflight.resolve(const {'burn.rig': rigId}),
        throwsA(stateErrorContaining(rigId)),
      );
    });

    test('detached UDID', () async {
      final preflight = RigPreflight(
        lookupRig: (id) async => rigBead(),
        devices: _FakeCatalog(const []),
      );
      await expectLater(
        preflight.resolve(const {'burn.rig': rigId}),
        throwsA(
          allOf(stateErrorContaining(rigId), stateErrorContaining(liveIpad.id)),
        ),
      );
    });

    test('duplicate live UDID', () async {
      final preflight = RigPreflight(
        lookupRig: (id) async => rigBead(),
        devices: _FakeCatalog(const [liveIpad, liveIpad]),
      );
      await expectLater(
        preflight.resolve(const {'burn.rig': rigId}),
        throwsA(stateErrorContaining(rigId)),
      );
    });

    test('target-platform mismatch', () async {
      final preflight = RigPreflight(
        lookupRig: (id) async => rigBead(),
        devices: _FakeCatalog(const [
          FlutterDevice(
            id: liveIpadId,
            name: "Nico's iPad mini",
            targetPlatform: 'android',
            emulator: false,
          ),
        ]),
      );
      await expectLater(
        preflight.resolve(const {'burn.rig': rigId}),
        throwsA(stateErrorContaining(rigId)),
      );
    });

    test('physical/emulator mismatch', () async {
      final preflight = RigPreflight(
        lookupRig: (id) async => rigBead(),
        devices: _FakeCatalog(const [
          FlutterDevice(
            id: liveIpadId,
            name: "Nico's iPad mini",
            targetPlatform: 'ios',
            emulator: true,
          ),
        ]),
      );
      await expectLater(
        preflight.resolve(const {'burn.rig': rigId}),
        throwsA(stateErrorContaining(rigId)),
      );
    });

    test('catalog exception wrapped with the rig id', () async {
      final preflight = RigPreflight(
        lookupRig: (id) async => rigBead(),
        devices: _ThrowingCatalog(),
      );
      await expectLater(
        preflight.resolve(const {'burn.rig': rigId}),
        throwsA(stateErrorContaining(rigId)),
      );
    });
  });

  group('ProcessFlutterDeviceCatalog', () {
    test(
      'invokes flutter devices --machine and preserves all fields',
      () async {
        var calls = 0;
        late String executable;
        late List<String> arguments;
        final catalog = ProcessFlutterDeviceCatalog(
          command: (actualExecutable, actualArguments) async {
            calls += 1;
            executable = actualExecutable;
            arguments = actualArguments;
            return (
              exitCode: 0,
              stdout: jsonEncode(const [
                {
                  'id': liveIpadId,
                  'name': "Nico's iPad mini",
                  'targetPlatform': 'ios',
                  'emulator': false,
                },
              ]),
              stderr: '',
            );
          },
        );

        final devices = await catalog.listDevices();

        expect(executable, 'flutter');
        expect(arguments, ['devices', '--machine']);
        expect(calls, 1);
        expect(devices, hasLength(1));
        expect(devices.single.id, liveIpad.id);
        expect(devices.single.name, liveIpad.name);
        expect(devices.single.targetPlatform, liveIpad.targetPlatform);
        expect(devices.single.emulator, isFalse);
      },
    );

    test('exit code 1 includes stderr', () async {
      final catalog = ProcessFlutterDeviceCatalog(
        command: (executable, arguments) async =>
            (exitCode: 1, stdout: '', stderr: 'flutter broke'),
      );
      await expectLater(
        catalog.listDevices(),
        throwsA(stateErrorContaining('flutter broke')),
      );
    });

    for (final payloadCase in const <(String, String, String)>[
      ('{} is refused as non-list', '{}', 'non-list'),
      ('not-json is refused as malformed JSON', 'not-json', 'malformed JSON'),
      (
        '[{}] is refused as a malformed entry',
        '[{}]',
        'malformed device entry',
      ),
    ]) {
      test(payloadCase.$1, () async {
        final catalog = ProcessFlutterDeviceCatalog(
          command: (executable, arguments) async =>
              (exitCode: 0, stdout: payloadCase.$2, stderr: ''),
        );
        await expectLater(
          catalog.listDevices(),
          throwsA(stateErrorContaining(payloadCase.$3)),
        );
      });
    }
  });
}
