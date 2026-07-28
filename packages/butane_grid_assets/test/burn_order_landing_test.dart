import 'dart:io';

import 'package:beads_dart/beads_dart.dart' show Bead, IssueType;
import 'package:butane_grid_assets/butane_grid_assets.dart';
import 'package:test/test.dart';

final class _FakeCatalog implements FlutterDeviceCatalog {
  _FakeCatalog(this.devices);
  final List<FlutterDevice> devices;
  var calls = 0;
  @override
  Future<List<FlutterDevice>> listDevices() async {
    calls += 1;
    return devices;
  }
}

String skipName(BurnOrderSkipReason reason) => switch (reason) {
  BurnOrderSkipReason.noPlatformDiff => 'noPlatformDiff',
  BurnOrderSkipReason.noAttachedMatchingRig => 'noAttachedMatchingRig',
};

Bead rig(String id, String platform, {String? deviceId}) => Bead(
  id: id,
  issueType: IssueType.rig,
  metadata: {
    'rig.device_udid': deviceId ?? 'device-$id',
    'rig.target_platform': platform,
    'rig.device_kind': 'physical',
    'rig.host_platform': 'macos',
    'rig.capabilities': '[]',
  },
);

FlutterDevice device(String id, String platform) =>
    FlutterDevice(id: id, name: id, targetPlatform: platform, emulator: false);

BurnOrderLandingRequest request(List<String> paths) => BurnOrderLandingRequest(
  orderId: 'burn-order-1',
  sourceBeadId: 'source-1',
  changedPaths: paths,
  harnessDirectory: '/checkout/butane_harness',
  leonardDrive: '/opt/leonard_drive',
);

void main() {
  group('platform path mapping', () {
    for (final mapping in const <(String, String)>[
      (r'packages\butane_android\lib\bridge.dart', 'android'),
      ('packages/butane_harness/android/app/build.gradle', 'android'),
      ('packages/butane_core_bluetooth/lib/core.dart', 'ios'),
      ('packages/butane_core_bluetooth/lib/core.dart', 'macos'),
      ('packages/butane_dart_bluez/lib/bluez.dart', 'linux'),
      ('packages/butane_bluez/lib/bluez.dart', 'linux'),
      ('packages/butane_harness/linux/CMakeLists.txt', 'linux'),
      ('packages/butane_windows/lib/windows.dart', 'windows'),
      ('packages/butane_harness/ios/Runner/AppDelegate.swift', 'ios'),
      ('packages/butane_harness/macos/Runner/AppDelegate.swift', 'macos'),
    ]) {
      test('${mapping.$1} maps to ${mapping.$2}', () async {
        final candidate = rig('rig-1', mapping.$2, deviceId: 'device-1');
        final landing = BurnOrderLanding(
          lookupRigs: () async => [candidate],
          devices: _FakeCatalog([device('device-1', mapping.$2)]),
          onLog: (_) {},
        );

        final result = await landing.file(request([mapping.$1]));

        expect(result.order!.metadata['burn.target_platform'], mapping.$2);
      });
    }
  });

  test('files the lower-id valid iOS rig with complete inputs', () async {
    final catalog = _FakeCatalog([
      device('device-z', 'ios'),
      device('device-a', 'ios'),
    ]);
    final landing = BurnOrderLanding(
      lookupRigs: () async => [
        rig('rig-z', 'ios', deviceId: 'device-z'),
        rig('rig-a', 'ios', deviceId: 'device-a'),
      ],
      devices: catalog,
      onLog: (_) {},
    );

    final result = await landing.file(
      request(['packages/butane_harness/ios/Runner.xcodeproj/project.pbxproj']),
    );
    final order = result.order!;

    expect(order.id, 'burn-order-1');
    expect(order.title, 'Burn source-1 on rig-a');
    expect(order.issueType, IssueType.task);
    expect(order.metadata, {
      'grid.circuit.formula': 'burn',
      'burn.rig': 'rig-a',
      BurnOrderInputs.followerDeviceKey: 'device-a',
      BurnOrderInputs.harnessDirectoryKey: '/checkout/butane_harness',
      BurnOrderInputs.leonardDriveKey: '/opt/leonard_drive',
      'burn.target_platform': 'ios',
      'burn.source_bead': 'source-1',
    });
  });

  test('continues after a detached lexical-first matching rig', () async {
    final logs = <String>[];
    final landing = BurnOrderLanding(
      lookupRigs: () async => [
        rig('rig-b', 'ios', deviceId: 'device-b'),
        rig('rig-a', 'ios', deviceId: 'detached-a'),
      ],
      devices: _FakeCatalog([device('device-b', 'ios')]),
      onLog: logs.add,
    );

    final result = await landing.file(
      request(['packages/butane_harness/ios/Runner/AppDelegate.swift']),
    );

    expect(result.order!.metadata['burn.rig'], 'rig-b');
    expect(logs.first, startsWith('burn rig rig-a refused:'));
  });

  test('non-platform diff skips without looking up rigs or devices', () async {
    var lookupCalls = 0;
    final logs = <String>[];
    final catalog = _FakeCatalog(const []);
    final landing = BurnOrderLanding(
      lookupRigs: () async {
        lookupCalls += 1;
        return [];
      },
      devices: catalog,
      onLog: logs.add,
    );

    final result = await landing.file(request(['README.md']));

    expect(lookupCalls, 0);
    expect(catalog.calls, 0);
    expect(result.order, isNull);
    expect(skipName(result.skipReason!), 'noPlatformDiff');
    expect(logs, ['burn order skipped: no-platform-diff']);
  });

  test('non-matching rig skips without listing devices', () async {
    final catalog = _FakeCatalog(const []);
    final landing = BurnOrderLanding(
      lookupRigs: () async => [rig('rig-linux', 'linux')],
      devices: catalog,
      onLog: (_) {},
    );

    final result = await landing.file(
      request(['packages/butane_harness/ios/Runner/AppDelegate.swift']),
    );

    expect(result.order, isNull);
    expect(result.skipReason, BurnOrderSkipReason.noAttachedMatchingRig);
    expect(catalog.calls, 0);
  });

  test('detached iOS and macOS rigs log sorted targets', () async {
    final logs = <String>[];
    final landing = BurnOrderLanding(
      lookupRigs: () async => [
        rig('rig-ios', 'ios'),
        rig('rig-macos', 'macos'),
      ],
      devices: _FakeCatalog(const []),
      onLog: logs.add,
    );

    final result = await landing.file(
      request(['packages/butane_core_bluetooth/lib/core.dart']),
    );

    expect(result.order, isNull);
    expect(result.skipReason, BurnOrderSkipReason.noAttachedMatchingRig);
    expect(logs.last, 'burn order skipped: no-attached-matching-rig:ios,macos');
  });

  test('uses only the existing static burn circuit', () {
    final source = File(
      'lib/src/burn/burn_order_landing.dart',
    ).readAsStringSync();
    expect(source, contains('kBurnCircuit.id'));
    for (final forbidden in [
      'Circuit(',
      '.pour(',
      'reconcile',
      'proveFresh',
      'freshness',
    ]) {
      expect(source, isNot(contains(forbidden)), reason: forbidden);
    }
  });
}
