/// LIVE proof of the iOS follower launcher: [IosFollowerLauncher] runs the
/// butane harness on a REAL tethered iOS device (via `flutter run --profile`),
/// auto-discovers the device VM service, stands up the LAN-exempt loopback
/// relay, and publishes a Dart-reachable endpoint — then the REAL
/// `leonard_drive` attaches over that endpoint, perceives the butane
/// peripheral fragment, reaches a real `poweredOn` radio, and the launch is
/// reaped.
///
/// Tagged `integration`; ORDER metadata is canonical. `BURN_IOS_DEVICE`,
/// `BURN_HARNESS_DIR`, and `LEONARD_DRIVE` are logged compatibility fallbacks.
/// The device must be unlocked.
@Tags(['integration'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:beads_dart/beads_dart.dart';
import 'package:butane_grid_assets/butane_grid_assets.dart';
import 'package:grid_runtime/grid_runtime.dart'
    show SystemProcessGroupController;
import 'package:test/test.dart';

void main() {
  group('iOS launch input resolution', () {
    const orderSpec = LaunchSpec(
      app: 'butane_harness',
      target: 'ios',
      followerDevice: 'order-device',
      harnessDirectory: '/order/harness',
    );

    test('ORDER inputs take precedence over constructor compatibility', () {
      final launcher = IosFollowerLauncher(
        deviceId: 'constructor-device',
        harnessDirectory: '/constructor/harness',
      );

      expect(launcher.resolveIosLaunchInputs(orderSpec), (
        deviceId: 'order-device',
        harnessDirectory: '/order/harness',
      ));
    });

    test('constructor compatibility inputs remain supported', () {
      final launcher = IosFollowerLauncher(
        deviceId: ' constructor-device ',
        harnessDirectory: ' /constructor/harness ',
      );

      expect(
        launcher.resolveIosLaunchInputs(
          const LaunchSpec(app: 'butane_harness', target: 'ios'),
        ),
        (
          deviceId: 'constructor-device',
          harnessDirectory: '/constructor/harness',
        ),
      );
    });

    test('missing device fails loudly before process effects', () {
      final launcher = IosFollowerLauncher(harnessDirectory: '/harness');

      expect(
        () => launcher.resolveIosLaunchInputs(
          const LaunchSpec(app: 'butane_harness', target: 'ios'),
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'iOS burn follower requires burn.follower_device '
                '(or compatibility deviceId)',
          ),
        ),
      );
    });

    test('missing harness directory fails loudly before process effects', () {
      final launcher = IosFollowerLauncher(deviceId: 'device');

      expect(
        () => launcher.resolveIosLaunchInputs(
          const LaunchSpec(app: 'butane_harness', target: 'ios'),
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'iOS burn follower requires burn.harness_dir '
                '(or compatibility harnessDirectory)',
          ),
        ),
      );
    });
  });

  test(
    'IosFollowerLauncher launches the harness on a REAL iOS device, '
    'leonard_drive perceives the peripheral over the relay, and it reaps',
    () async {
      const order = Bead(id: 'live-ios-burn');
      final log = <String>[];
      final inputs = BurnOrderInputs.resolve(
        metadata: order.metadata,
        environment: Platform.environment,
        onLog: log.add,
      );
      if (inputs.followerDevice.isEmpty ||
          inputs.harnessDirectory.isEmpty ||
          inputs.leonardDrive.isEmpty) {
        markTestSkipped('provide ORDER burn metadata or compatibility inputs');
        return;
      }
      final preflight = BurnPreflight(
        directoryExists: (path) => Directory(path).existsSync(),
        fileExists: (path) => File(path).existsSync(),
      );
      try {
        preflight.validate(inputs);
      } on StateError catch (error) {
        markTestSkipped('$error');
        return;
      }
      if (await ProcessLeonardDrive.discover(
            executableOverride: inputs.leonardDrive,
            onLog: log.add,
          ) ==
          null) {
        markTestSkipped('leonard_drive not discoverable');
        return;
      }

      final launcher = IosFollowerLauncher(onLog: log.add);
      final runner = ButaneFollowerRunner(
        launcher: launcher,
        processes: const SystemProcessGroupController(),
        onLog: log.add,
      );

      try {
        // --- launch: flutter run --profile → discover → relay → publish ---
        final endpoint = await runner.launch(
          LaunchSpec(
            app: 'butane_harness',
            target: 'ios',
            role: 'peripheral',
            followerDevice: inputs.followerDevice,
            harnessDirectory: inputs.harnessDirectory,
            leonardDrive: inputs.leonardDrive,
          ),
        );
        expect(
          endpoint.isPublished,
          isTrue,
          reason: 'launcher must publish a reachable endpoint',
        );
        expect(
          endpoint.vmServiceUri,
          startsWith('ws://127.0.0.1:'),
          reason: 'the published endpoint is the Dart-reachable loopback relay',
        );

        // --- drive: the REAL leonard_drive over the relayed endpoint ---
        final drive = ProcessLeonardDrive(
          executableOverride: inputs.leonardDrive,
          onLog: log.add,
        );
        await drive.attach(endpoint);

        final fragment =
            jsonDecode(await drive.observe('extensions.butane.data'))
                as Map<String, Object?>;
        expect(fragment['role'], 'peripheral');

        // A real radio on a real device: the peripheral manager reaches
        // poweredOn (proves BLE is authorized + the tool round-trips).
        final state =
            jsonDecode(
                  await drive.invoke('butane.wait_for_state', {
                    'timeoutMs': 10000,
                  }),
                )
                as Map<String, Object?>;
        expect(state['ok'], isTrue);
        expect(
          (state['value']! as Map)['matched'],
          isTrue,
          reason:
              'iPad Bluetooth must be authorized + poweredOn '
              '(log: ${log.join(' | ')})',
        );
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
