import 'package:args/args.dart';

import 'follower.dart';
import 'scenarios.dart';

/// Arguments accepted by the burn-follower supervisor process.
final class BurnFollowerDaemonInputs {
  const BurnFollowerDaemonInputs({
    required this.device,
    required this.harnessDirectory,
    required this.leonardDrive,
  });

  final String device;
  final String harnessDirectory;
  final String leonardDrive;

  static BurnFollowerDaemonInputs parse(List<String> arguments) {
    final parser = ArgParser()
      ..addOption('device', mandatory: true)
      ..addOption('harness-dir', mandatory: true)
      ..addOption('leonard-drive', mandatory: true);
    final result = parser.parse(arguments);
    return BurnFollowerDaemonInputs(
      device: result.option('device')!.trim(),
      harnessDirectory: result.option('harness-dir')!.trim(),
      leonardDrive: result.option('leonard-drive')!.trim(),
    );
  }
}

/// Runs one follower until [terminate] fires, then reaps it exactly once.
Future<int> runBurnFollowerDaemon({
  required BurnFollowerDaemonInputs inputs,
  required ButaneFollowerRunner runner,
  required Stream<void> terminate,
  required void Function(String) publish,
  void Function(String)? onLog,
}) async {
  try {
    final endpoint = await runner.launch(
      LaunchSpec(
        app: 'butane_harness',
        target: 'ios',
        role: 'peripheral',
        scenario: kSmokeScenario.name,
        followerDevice: inputs.device,
        harnessDirectory: inputs.harnessDirectory,
        leonardDrive: inputs.leonardDrive,
      ),
    );
    publish('burn-follower-published ${endpoint.vmServiceUri}');
    await terminate.first;
    return 0;
  } on Object catch (error) {
    onLog?.call('burn follower supervisor failed: $error');
    return 1;
  } finally {
    await runner.teardown();
  }
}
