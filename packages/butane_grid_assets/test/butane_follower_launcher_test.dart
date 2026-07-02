/// LIVE-LOCAL proof of the REAL follower launcher (Track H's follower half,
/// on one box): [ButaneFollowerLauncher] builds + launches the actual
/// `butane_harness` app, the harness prints the `GRID_VM_URI=` sentinel
/// after exploration registration, the REAL `leonard_drive` attaches and
/// perceives the butane extension fragment, and the M4 `terminateGroup`
/// reaper actually kills the app.
///
/// Tagged `integration`: needs `flutter` on PATH, the sibling
/// `butane_harness` package, a built (or buildable) debug app for this
/// platform, and a discoverable `leonard_drive` (lenny checkout). Self-skips
/// when any prerequisite is missing.
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
    'ButaneFollowerLauncher launches the REAL harness: sentinel scraped, '
    'leonard_drive perceives the butane fragment, the reaper kills the app',
    () async {
      // --- prerequisites (self-skip, never fail for a missing sibling) ---
      final harnessDir = Directory('../butane_harness').absolute;
      if (!harnessDir.existsSync()) {
        markTestSkipped('butane_harness not found at ${harnessDir.path}');
        return;
      }
      final drivePrefix = await ProcessLeonardDrive.discover();
      if (drivePrefix == null) {
        markTestSkipped('leonard_drive not discoverable (lenny not checked '
            r'out and $LEONARD_DRIVE unset)');
        return;
      }
      final target = Platform.isMacOS
          ? 'macos'
          : Platform.isLinux
              ? 'linux'
              : '';
      if (target.isEmpty) {
        markTestSkipped('unsupported host platform for the harness launch');
        return;
      }

      final log = <String>[];
      final launcher = ButaneFollowerLauncher(
        harnessDirectory: harnessDir.path,
        wsPort: 8971,
        onLog: log.add,
      );
      final runner = ButaneFollowerRunner(
        launcher: launcher,
        processes: const SystemProcessGroupController(),
        onLog: log.add,
      );

      try {
        // --- launch: provision + boot + sentinel rendezvous ---
        final endpoint = await runner.launch(
          LaunchSpec(app: 'butane_harness', target: target),
        );
        expect(endpoint.isPublished, isTrue,
            reason: 'launcher must publish the scraped sentinel URI');
        expect(endpoint.vmServiceUri, startsWith('ws://'));

        // --- drive: the REAL leonard_drive over the DIRECT channel ---
        final drive = ProcessLeonardDrive();
        await drive.attach(endpoint);
        final fragment = jsonDecode(
          await drive.observe('extensions.butane.data'),
        ) as Map<String, Object?>;
        expect(fragment['role'], 'peripheral',
            reason: 'LaunchSpec defaults the follower to the peripheral role');
        expect(fragment, contains('advertising'));

        // A tool round-trip through the registry frontend.
        final stateResult = jsonDecode(
          await drive.invoke('butane.check_state', const {}),
        ) as Map<String, Object?>;
        expect(stateResult['ok'], isTrue);
      } finally {
        // --- teardown: the guaranteed reap (even on the failure path) ---
        final daemon = launcher.lastLaunched;
        final result = await runner.teardown();
        log.add('teardown → ${result.name}');
        if (daemon != null) {
          // The whole point: the app is actually dead. kill -0 races the
          // reap grace, so poll briefly.
          var alive = true;
          for (var i = 0; i < 20 && alive; i++) {
            alive = _isAlive(daemon.pid);
            if (alive) {
              await Future<void>.delayed(const Duration(milliseconds: 250));
            }
          }
          expect(alive, isFalse,
              reason: 'harness pid ${daemon.pid} must be reaped '
                  '(log: ${log.join(' | ')})');
        }
      }
    },
    timeout: const Timeout(Duration(minutes: 15)),
  );
}

/// Whether [pid] is still alive (`kill -0` semantics).
bool _isAlive(int pid) {
  final result = Process.runSync('kill', ['-0', '$pid']);
  return result.exitCode == 0;
}
