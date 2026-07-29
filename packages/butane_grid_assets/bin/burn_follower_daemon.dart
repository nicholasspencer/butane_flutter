import 'dart:io';

import 'package:butane_grid_assets/butane_grid_assets.dart';
import 'package:grid_runtime/grid_runtime.dart';

Future<void> main(List<String> arguments) async {
  final inputs = BurnFollowerDaemonInputs.parse(arguments);
  final runner = ButaneFollowerRunner(
    launcher: IosFollowerLauncher(
      deviceId: inputs.device,
      harnessDirectory: inputs.harnessDirectory,
      onLog: stderr.writeln,
    ),
    processes: const SystemProcessGroupController(),
    onLog: stderr.writeln,
  );
  exitCode = await runBurnFollowerDaemon(
    inputs: inputs,
    runner: runner,
    terminate: ProcessSignal.sigterm.watch().map((_) {}),
    publish: stdout.writeln,
    onLog: stderr.writeln,
  );
}
