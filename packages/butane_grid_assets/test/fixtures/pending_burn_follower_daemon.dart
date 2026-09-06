import 'dart:async';
import 'dart:io';

import 'package:butane_grid_assets/butane_grid_assets.dart';
import 'package:grid_runtime/grid_runtime.dart';

final class _PendingLauncher implements FollowerLauncher {
  @override
  Future<LaunchedDaemon> launch(LaunchSpec spec) {
    stdout.writeln('launch-started');
    return Completer<LaunchedDaemon>().future;
  }
}

Future<void> main() async {
  final runner = ButaneFollowerRunner(
    launcher: _PendingLauncher(),
    processes: const SystemProcessGroupController(),
  );
  exitCode = await runBurnFollowerDaemon(
    inputs: const BurnFollowerDaemonInputs(
      target: 'ios',
      device: 'device-1',
      harnessDirectory: '/harness',
      leonardDrive: '/drive',
    ),
    runner: runner,
    terminate: ProcessSignal.sigterm.watch().map((_) {}),
    publish: stdout.writeln,
    onLog: stderr.writeln,
    launchTimeout: const Duration(seconds: 30),
  );
}
