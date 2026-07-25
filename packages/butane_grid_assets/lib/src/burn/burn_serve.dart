/// The burn LESSOR wiring — what a follower box plugs into the generic
/// `serve` core command (ADR-0011 D3: the core owns the lessor lifecycle,
/// the domain owns the use AND the reap of what it launched).
///
/// `butane_station serve --kind burn --harness-dir <path>`: a dispatched
/// launch builds + boots the harness via [ButaneFollowerLauncher]; the
/// lease's end (explicit release OR any reap) fires `onLeaseEnded` → the
/// runner reaps the launched app through the M4 `terminateGroup` reaper —
/// the guaranteed teardown crossing the bus, no leaked follower.
library;

import 'dart:async';

import 'package:args/args.dart';
import 'package:grid_federation/grid_federation.dart' show DispatchHandler;
import 'package:grid_runtime/grid_runtime.dart'
    show SystemProcessGroupController;

import 'burn_dispatch_handler.dart';
import 'butane_follower_launcher.dart';
import 'follower.dart';

/// The burn-domain flags on the generic serve command.
void configureBurnServeFlags(ArgParser parser) => parser
  ..addOption(
    'harness-dir',
    help: 'The butane_harness checkout on this box — built (--debug) and '
        'launched as the follower app-under-test.',
  )
  ..addOption(
    'follower-ws-port',
    defaultsTo: '8971',
    help: "The launched harness's WS control-plane port.",
  );

/// Builds the burn lessor pieces from the parsed serve flags: the
/// `burn`-kind dispatch handler over a [ButaneFollowerRunner], and the
/// lease-end teardown that reaps the launched follower app.
({
  DispatchHandler handler,
  String? banner,
  void Function(String leaseId)? onLeaseEnded,
}) butaneBurnServeHandler(ArgResults args, void Function(String) log) {
  final dir = args.option('harness-dir');
  if (dir == null || dir.isEmpty) {
    throw StateError('serve --kind burn requires --harness-dir');
  }
  final runner = ButaneFollowerRunner(
    launcher: ButaneFollowerLauncher(
      harnessDirectory: dir,
      wsPort: int.parse(args.option('follower-ws-port')!),
      onLog: log,
    ),
    processes: const SystemProcessGroupController(),
    onLog: log,
  );
  return (
    handler: burnDispatchHandler(runner: runner, onLog: log),
    banner: '  burn lessor: follower harness at $dir '
        '(reaped on lease end)',
    onLeaseEnded: (leaseId) {
      log('lease $leaseId ended → reaping the follower app');
      unawaited(runner.teardown());
    },
  );
}
