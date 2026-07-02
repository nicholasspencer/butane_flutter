/// LIVE proof of the iOS follower launcher: [IosFollowerLauncher] runs the
/// butane harness on a REAL tethered iOS device (via `flutter run --profile`),
/// auto-discovers the device VM service, stands up the LAN-exempt loopback
/// relay, and publishes a Dart-reachable endpoint — then the REAL
/// `leonard_drive` attaches over that endpoint, perceives the butane
/// peripheral fragment, reaches a real `poweredOn` radio, and the launch is
/// reaped.
///
/// Tagged `integration`; self-skips unless `BURN_IOS_DEVICE=<udid>` names a
/// tethered device (and `flutter` + the sibling `butane_harness` + a
/// discoverable `leonard_drive` are present). The device must be unlocked.
@Tags(['integration'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:butane_grid_assets/butane_grid_assets.dart';
import 'package:grid_runtime/grid_runtime.dart'
    show SystemProcessGroupController;
import 'package:test/test.dart';

void main() {
  test(
    'IosFollowerLauncher launches the harness on a REAL iOS device, '
    'leonard_drive perceives the peripheral over the relay, and it reaps',
    () async {
      final udid = Platform.environment['BURN_IOS_DEVICE'];
      if (udid == null || udid.isEmpty) {
        markTestSkipped('set BURN_IOS_DEVICE=<udid> to run the iOS launch test');
        return;
      }
      final harnessDir = Directory('../butane_harness').absolute;
      if (!harnessDir.existsSync()) {
        markTestSkipped('butane_harness not found at ${harnessDir.path}');
        return;
      }
      if (await ProcessLeonardDrive.discover() == null) {
        markTestSkipped('leonard_drive not discoverable');
        return;
      }

      final log = <String>[];
      final launcher = IosFollowerLauncher(
        deviceId: udid,
        harnessDirectory: harnessDir.path,
        onLog: log.add,
      );
      final runner = ButaneFollowerRunner(
        launcher: launcher,
        processes: const SystemProcessGroupController(),
        onLog: log.add,
      );

      try {
        // --- launch: flutter run --profile → discover → relay → publish ---
        final endpoint = await runner.launch(
          const LaunchSpec(
            app: 'butane_harness',
            target: 'ios',
            role: 'peripheral',
          ),
        );
        expect(endpoint.isPublished, isTrue,
            reason: 'launcher must publish a reachable endpoint');
        expect(endpoint.vmServiceUri, startsWith('ws://127.0.0.1:'),
            reason: 'the published endpoint is the Dart-reachable loopback relay');

        // --- drive: the REAL leonard_drive over the relayed endpoint ---
        final drive = ProcessLeonardDrive();
        await drive.attach(endpoint);

        final fragment = jsonDecode(
          await drive.observe('extensions.butane.data'),
        ) as Map<String, Object?>;
        expect(fragment['role'], 'peripheral');

        // A real radio on a real device: the peripheral manager reaches
        // poweredOn (proves BLE is authorized + the tool round-trips).
        final state = jsonDecode(
          await drive.invoke('butane.wait_for_state', {'timeoutMs': 10000}),
        ) as Map<String, Object?>;
        expect(state['ok'], isTrue);
        expect((state['value']! as Map)['matched'], isTrue,
            reason: 'iPad Bluetooth must be authorized + poweredOn '
                '(log: ${log.join(' | ')})');
      } finally {
        // --- teardown: reaps flutter run + the relay + the on-device app ---
        final result = await runner.teardown();
        log.add('teardown → ${result.name}');
        expect(runner.isRunning, isFalse);
      }
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
