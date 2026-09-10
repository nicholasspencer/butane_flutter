/// LIVE proof of the default iOS follower launcher: [IosFollowerLauncher]
/// builds the signed profile harness, installs and launches it through
/// `devicectl --console`, binds the authenticated VM service to the device's
/// network interfaces, resolves its engine-published record, stands up the
/// LAN-exempt loopback relay, and publishes a Dart-reachable endpoint — then
/// the REAL `leonard_drive` attaches over that endpoint, perceives the butane
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
    'default devicectl launch reaches a REAL iOS peripheral and reaps',
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
      try {
        await systemBurnPreflight().validate(inputs);
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
        // --- launch: build → devicectl install/console → relay → publish ---
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
          reason:
              'the devicectl-owned launch must publish the Dart-reachable '
              'loopback relay',
        );
        expect(
          log,
          contains(
            startsWith(
              'ios launcher: xcrun devicectl device install app --device ',
            ),
          ),
          reason: 'the default route must install with devicectl',
        );
        expect(
          log.where(
            (line) =>
                line.startsWith(
                  'ios launcher: xcrun devicectl device process launch '
                  '--console --terminate-existing --device ',
                ) &&
                line.endsWith(
                  'com.nicospencer.butaneHarness '
                  '--vm-service-host=0.0.0.0 --enable-dart-profiling',
                ),
          ),
          hasLength(1),
          reason: 'the default route must own the console launch',
        );
        expect(
          log.where((line) => line.contains('flutter run --profile')),
          isEmpty,
          reason: 'the resident route must not use grant-bound flutter run',
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
        // --- teardown: reaps devicectl + relay + the on-device app ---
        final result = await runner.teardown();
        log.add('teardown → ${result.name}');
        expect(runner.isRunning, isFalse);
      }
    },
    timeout: const Timeout(Duration(minutes: 15)),
  );
}
