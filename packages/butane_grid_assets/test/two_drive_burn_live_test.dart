/// LIVE-LOCAL proof of the TWO-DRIVE burn-host on ONE box: a REAL peripheral
/// harness stands in as the leased follower (its endpoint hand-threaded as
/// the sibling payload — the fan-out mechanics are proven offline), and the
/// REAL [BurnHostCapability] launches its own LOCAL central harness, attaches
/// TWO real `leonard_drive`s, routes scripted steps by endpoint selector
/// (structured args over the wire), collects a passing [TestReport], and
/// tears down both ends.
///
/// Two scenarios run through the same scaffolding:
///  - `smoke` — adapters gated, GATT+advertise, perception both ends;
///  - `nus-round-trip` — the REAL-RADIO gate: scan off the air → connect →
///    discover → write (byte-verified on the peripheral) → subscribe →
///    notification received → disconnect.
///
/// Tagged `integration`: needs `flutter` + the sibling `butane_harness` +
/// a discoverable `leonard_drive`. Self-skips when missing. This box's
/// harness app needs Bluetooth authorization (TCC).
@Tags(['integration'])
library;

import 'dart:io';

import 'package:butane_grid_assets/butane_grid_assets.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/testing.dart' show FakeTreeContext, stepArgs;
import 'package:grid_runtime/grid_runtime.dart'
    show SystemProcessGroupController;
import 'package:test/test.dart';

void main() {
  test(
    'the TWO-DRIVE burn drives a REAL peripheral (follower) and a REAL '
    'central (host-local) on one box, and reaps both [smoke]',
    () async => _runLiveScenario(kSmokeScenario),
    timeout: const Timeout(Duration(minutes: 15)),
  );

  test(
    'the NUS ROUND-TRIP passes on REAL radios: scan off the air → connect → '
    'discover → write (byte-verified) → subscribe → notify → disconnect',
    () async {
      // Same-box physics: a central NEVER discovers its own machine's
      // advertisement (the controller does not loop back its own adv
      // packets), so this scenario needs a SECOND radio. Point
      // BURN_FOLLOWER_ENDPOINT at a peripheral harness on another box
      // (its GRID_VM_URI, reachable — e.g. via an SSH tunnel) and the
      // local central drives the round-trip against it.
      final remote = Platform.environment['BURN_FOLLOWER_ENDPOINT'];
      if (remote == null || remote.isEmpty) {
        markTestSkipped(
          'NUS round-trip needs a second radio: set BURN_FOLLOWER_ENDPOINT '
          "to a remote peripheral harness's GRID_VM_URI",
        );
        return;
      }
      await _runLiveScenario(
        kNusRoundTripScenario,
        remoteFollowerEndpoint: remote,
      );
    },
    timeout: const Timeout(Duration(minutes: 15)),
  );
}

/// Launches the real follower peripheral + runs [scenario] through a real
/// [BurnHostCapability] (which launches the real local central), asserting a
/// fully-passing report and the teardown of both ends. With
/// [remoteFollowerEndpoint], no local follower launches — the scenario
/// drives a peripheral harness already running on another box (real
/// two-radio topology; its teardown belongs to whoever launched it).
Future<void> _runLiveScenario(
  DriveScenario scenario, {
  String? remoteFollowerEndpoint,
}) async {
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

  // The "leased follower": a REAL peripheral harness on this box — unless a
  // remote endpoint was supplied (the two-radio arm).
  final followerRunner = remoteFollowerEndpoint != null
      ? null
      : ButaneFollowerRunner(
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
      // A local follower launch above already built; the remote arm builds.
      rebuild: followerRunner == null,
      onLog: log.add,
    ),
    processes: const SystemProcessGroupController(),
    onLog: log.add,
  );

  final host = BurnHostCapability(
    drive: ProcessLeonardDrive(),
    scenario: scenario,
    localRunner: localRunner,
    localSpec: LaunchSpec(
      app: 'butane_harness',
      target: target,
      role: 'central',
    ),
    localDrive: ProcessLeonardDrive(),
    onLog: log.add,
  );

  ({FakeTreeContext context, StepArgs args})? ctx;
  try {
    // Launch the "leased" follower (or adopt the remote one) and hand-thread
    // its endpoint as the sibling payload (the bus rendezvous is proven
    // offline + loopback).
    final followerEndpoint = followerRunner == null
        ? FollowerEndpoint(
            vmServiceUri: remoteFollowerEndpoint!,
            station: 'remote-follower',
          )
        : await followerRunner.launch(
            LaunchSpec(app: 'butane_harness', target: target),
          );
    expect(followerEndpoint.isPublished, isTrue);

    // The rip-out shape: the SiblingView rendezvous is an AMBIENT value on the
    // (fake) tree; the per-step nodePath/cancel ride the StepArgs.
    ctx = (
      context: FakeTreeContext(
        values: {
          SiblingView: SiblingView(
            results: {
              'tg-burn-live/$kBurnFollowerStep': {
                'endpoint': followerEndpoint.vmServiceUri,
                'station': followerEndpoint.station,
                'lease': 'live-local',
              },
            },
          ),
        },
      ),
      args: stepArgs('tg-burn-live/$kBurnHostStep'),
    );

    final out = await host.run(ctx.context, ctx.args);
    final report = host.reportFor(ctx.args);
    final rendered = report?.steps
        .map(
          (s) => '${s.passed ? "PASS" : "FAIL"} ${s.description} '
              '→ ${s.observed}',
        )
        .join('\n');
    expect(out, isA<Ok>(),
        reason: 'scenario failed:\n$rendered\nlog: ${log.join(' | ')}');
    expect(report!.passed, isTrue);
    expect(report.total, scenario.steps.length);

    // The host teardown reaps ITS local central (once-only).
    await host.teardown(ctx.args);
    expect(localRunner.isRunning, isFalse,
        reason: 'the local central is the host teardown\'s reap');
  } finally {
    // Idempotent teardown-of-last-resort for both ends (a remote follower's
    // teardown belongs to whoever launched it).
    if (ctx != null) await host.teardown(ctx.args);
    await followerRunner?.teardown();
  }
}
