import 'dart:async';

import 'package:args/args.dart';

import 'follower.dart';
import 'scenarios.dart';

/// Arguments accepted by the burn-follower supervisor process.
final class BurnFollowerDaemonInputs {
  const BurnFollowerDaemonInputs({
    required this.target,
    required this.device,
    required this.harnessDirectory,
    required this.leonardDrive,
  });

  final String target;
  final String device;
  final String harnessDirectory;
  final String leonardDrive;

  static BurnFollowerDaemonInputs parse(List<String> arguments) {
    final parser = ArgParser()
      ..addOption('target', mandatory: true)
      ..addOption('device', mandatory: true)
      ..addOption('harness-dir', mandatory: true)
      ..addOption('leonard-drive', mandatory: true);
    final result = parser.parse(arguments);
    return BurnFollowerDaemonInputs(
      target: result.option('target')!.trim(),
      device: result.option('device')!.trim(),
      harnessDirectory: result.option('harness-dir')!.trim(),
      leonardDrive: result.option('leonard-drive')!.trim(),
    );
  }
}

/// Runs one follower until termination, bounding launch and teardown.
Future<int> runBurnFollowerDaemon({
  required BurnFollowerDaemonInputs inputs,
  required ButaneFollowerRunner runner,
  required Stream<void> terminate,
  required void Function(String) publish,
  void Function(String)? onLog,
  Duration launchTimeout = const Duration(minutes: 15),
  Duration teardownTimeout = const Duration(seconds: 30),
}) async {
  var result = 1;
  final termination = Completer<void>();
  final terminationSubscription = terminate.listen(
    (_) {
      if (!termination.isCompleted) termination.complete();
    },
    onError: (Object error, StackTrace stackTrace) {
      if (!termination.isCompleted) {
        termination.completeError(error, stackTrace);
      }
    },
  );
  try {
    final launchResult = Completer<FollowerEndpoint>();
    runner
        .launch(
          LaunchSpec(
            app: 'butane_harness',
            target: inputs.target,
            role: 'peripheral',
            scenario: kSmokeScenario.name,
            followerDevice: inputs.device,
            harnessDirectory: inputs.harnessDirectory,
            leonardDrive: inputs.leonardDrive,
          ),
        )
        .then<void>(
          (endpoint) {
            if (!launchResult.isCompleted) launchResult.complete(endpoint);
          },
          onError: (Object error, StackTrace stackTrace) {
            if (!launchResult.isCompleted) {
              launchResult.completeError(error, stackTrace);
            }
          },
        );
    final launchTimer = Timer(launchTimeout, () {
      if (!launchResult.isCompleted) {
        launchResult.completeError(
          TimeoutException(
            'burn follower launch timed out after '
            '${launchTimeout.inMilliseconds}ms',
            launchTimeout,
          ),
        );
      }
    });
    late final FollowerEndpoint? endpoint;
    try {
      endpoint = await Future.any<FollowerEndpoint?>([
        launchResult.future.then<FollowerEndpoint?>((endpoint) => endpoint),
        termination.future.then<FollowerEndpoint?>((_) => null),
      ]);
    } finally {
      launchTimer.cancel();
    }
    if (endpoint == null) {
      onLog?.call('termination-receipt: burn follower daemon launch aborted');
      result = 0;
    } else {
      publish('burn-follower-published ${endpoint.vmServiceUri}');
      final residentExit =
          runner.residentExit ??
          (throw StateError(
            'burn follower runner lost its resident after launch',
          ));
      await Future.any<void>([
        termination.future,
        residentExit.then<void>(
          (_) => throw StateError('burn follower child exited while resident'),
        ),
      ]);
      result = 0;
    }
  } on Object catch (error) {
    onLog?.call('burn follower supervisor failed: $error');
    result = 1;
  }

  try {
    await runner.teardown().timeout(
      teardownTimeout,
      onTimeout: () => throw TimeoutException(
        'burn follower teardown timed out after '
        '${teardownTimeout.inMilliseconds}ms',
        teardownTimeout,
      ),
    );
    onLog?.call('teardown-receipt: burn follower daemon reaped');
  } on Object catch (error) {
    onLog?.call(
      'teardown-receipt: burn follower daemon teardown failed: $error',
    );
    result = 1;
  }
  await terminationSubscription.cancel();
  return result;
}
