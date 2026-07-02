/// LIVE-LOCAL proof of the TWO-DRIVE burn-host on ONE box: a REAL peripheral
/// harness stands in as the leased follower (its endpoint hand-threaded as
/// the sibling payload — the fan-out mechanics are proven offline), and the
/// REAL [BurnHostCapability] launches its own LOCAL central harness, attaches
/// TWO real `leonard_drive`s, routes scripted steps by endpoint selector
/// (structured args over the wire), collects a passing [TestReport], and
/// tears down both ends.
///
/// Tagged `integration`: needs `flutter` + the sibling `butane_harness` +
/// a discoverable `leonard_drive`. Self-skips when missing. BLE-mutating
/// steps run against the real adapter (add_service/start_advertising on the
/// peripheral) — this box's harness app needs Bluetooth authorization.
@Tags(['integration'])
library;

import 'dart:io';

import 'package:butane_grid_assets/butane_grid_assets.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/testing.dart' show bead;
import 'package:grid_runtime/grid_runtime.dart'
    show SystemProcessGroupController;
import 'package:test/test.dart';

// The scenario under test is the pack's NAMED smoke scenario — the same one
// `butane_station burn --scenario smoke` drives.

void main() {
  test(
    'the TWO-DRIVE burn drives a REAL peripheral (follower) and a REAL '
    'central (host-local) on one box, and reaps both',
    () async {
      // --- prerequisites (self-skip) ---
      final harnessDir = Directory('../butane_harness').absolute;
      if (!harnessDir.existsSync()) {
        markTestSkipped('butane_harness not found at ${harnessDir.path}');
        return;
      }
      if (await ProcessLeonardDrive.discover() == null) {
        markTestSkipped('leonard_drive not discoverable');
        return;
      }
      final target = Platform.isMacOS
          ? 'macos'
          : Platform.isLinux
              ? 'linux'
              : '';
      if (target.isEmpty) {
        markTestSkipped('unsupported host platform');
        return;
      }

      final log = <String>[];

      // The "leased follower": a REAL peripheral harness on this box.
      final followerRunner = ButaneFollowerRunner(
        launcher: ButaneFollowerLauncher(
          harnessDirectory: harnessDir.path,
          wsPort: 8971,
          onLog: log.add,
        ),
        processes: const SystemProcessGroupController(),
        onLog: log.add,
      );

      // The host's LOCAL central, launched by the order itself.
      final localRunner = ButaneFollowerRunner(
        launcher: ButaneFollowerLauncher(
          harnessDirectory: harnessDir.path,
          wsPort: 8972,
          rebuild: false, // the follower launch above just built it
          onLog: log.add,
        ),
        processes: const SystemProcessGroupController(),
        onLog: log.add,
      );

      final host = BurnHostCapability(
        drive: ProcessLeonardDrive(),
        scenario: kSmokeScenario,
        localRunner: localRunner,
        localSpec: LaunchSpec(
          app: 'butane_harness',
          target: target,
          role: 'central',
        ),
        localDrive: ProcessLeonardDrive(),
        onLog: log.add,
      );

      CapabilityContext? ctx;
      try {
        // Launch the "leased" follower and hand-thread its endpoint as the
        // sibling payload (the bus rendezvous is proven offline + loopback).
        final followerEndpoint = await followerRunner.launch(
          LaunchSpec(app: 'butane_harness', target: target),
        );
        expect(followerEndpoint.isPublished, isTrue);

        ctx = CapabilityContext(
          params: const {},
          bead: bead('tg-burn-live'),
          workspaceDir: harnessDir.path,
          branch: 'grid/tg-burn-live',
          baseBranch: 'main',
          services: const ServiceBundle(),
          cancel: CancelToken(),
          nodePath: 'tg-burn-live/$kBurnHostStep',
          siblings: SiblingView(
            results: {
              'tg-burn-live/$kBurnFollowerStep': {
                'endpoint': followerEndpoint.vmServiceUri,
                'station': followerEndpoint.station,
                'lease': 'live-local',
              },
            },
          ),
        );

        final out = await host.run(ctx);
        final report = host.reportFor(ctx);
        final rendered = report?.steps
            .map(
              (s) => '${s.passed ? "PASS" : "FAIL"} ${s.description} '
                  '→ ${s.observed}',
            )
            .join('\n');
        expect(out, isA<Ok>(),
            reason: 'scenario failed:\n$rendered\nlog: ${log.join(' | ')}');
        expect(report!.passed, isTrue);
        expect(report.total, 7);

        // The host teardown reaps ITS local central (once-only).
        await host.teardown(ctx);
        expect(localRunner.isRunning, isFalse,
            reason: 'the local central is the host teardown\'s reap');
      } finally {
        // Idempotent teardown-of-last-resort for both ends.
        if (ctx != null) await host.teardown(ctx);
        await followerRunner.teardown();
      }
    },
    timeout: const Timeout(Duration(minutes: 15)),
  );
}
