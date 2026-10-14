/// Direct live run of any attached central × peripheral pair, below the
/// resident burn composition: launch both harnesses, attach two
/// `leonard_drive`s, drive the selected scenarios, and reap both ends.
///
///     PAIR_CENTRAL=android PAIR_CENTRAL_DEVICE=<adb serial> \
///     PAIR_FOLLOWER=ios PAIR_FOLLOWER_DEVICE=<udid> \
///     dart test -t integration test/pair_live_test.dart
///
/// Targets are `macos`, `ios`, and `android`; `macos` needs no device id.
/// `PAIR_SCENARIOS` is a comma list (default
/// `nus-round-trip,central-features`). Self-skips without `PAIR_CENTRAL`.
@Tags(['integration'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:butane_grid_assets/src/burn/android_follower_launcher.dart';
import 'package:butane_grid_assets/src/burn/burn_report.dart';
import 'package:butane_grid_assets/src/burn/burn_scenario.dart';
import 'package:butane_grid_assets/src/burn/follower.dart';
import 'package:butane_grid_assets/src/burn/ios_follower_launcher.dart';
import 'package:butane_grid_assets/src/burn/macos_central_launcher.dart';
import 'package:butane_grid_assets/src/burn/process_leonard_drive.dart';
import 'package:butane_grid_assets/src/burn/scenarios.dart';
import 'package:grid_runtime/grid_runtime.dart'
    show SystemProcessGroupController;
import 'package:test/test.dart';

void main() {
  test(
    'pair drives the selected scenarios across two attached devices',
    () async {
      final env = Platform.environment;
      final centralTarget = env['PAIR_CENTRAL'] ?? '';
      if (centralTarget.isEmpty) {
        markTestSkipped(
          'set PAIR_CENTRAL and PAIR_FOLLOWER to run a live pair',
        );
        return;
      }
      final centralDevice = env['PAIR_CENTRAL_DEVICE'] ?? '';
      final followerTarget = env['PAIR_FOLLOWER'] ?? '';
      final followerDevice = env['PAIR_FOLLOWER_DEVICE'] ?? '';
      final scenarioNames =
          (env['PAIR_SCENARIOS'] ?? 'nus-round-trip,central-features')
              .split(',')
              .map((name) => name.trim())
              .where((name) => name.isNotEmpty)
              .toList();
      final scenarios = [
        for (final name in scenarioNames)
          name == 'central-features'
              ? centralFeaturesScenario(centralTarget: centralTarget)
              : kButaneScenarios[name] ??
                    (throw ArgumentError.value(name, 'PAIR_SCENARIOS')),
      ];
      final harnessDirectory = Directory('../butane_harness').absolute.path;

      void log(String line) => stderr.writeln('[pair] $line');

      final centralRunner = ButaneFollowerRunner(
        launcher: _launcherFor(
          centralTarget,
          centralDevice,
          harnessDirectory,
          log,
        ),
        processes: const SystemProcessGroupController(),
        onLog: log,
      );
      final followerRunner = ButaneFollowerRunner(
        launcher: _launcherFor(
          followerTarget,
          followerDevice,
          harnessDirectory,
          log,
        ),
        processes: const SystemProcessGroupController(),
        onLog: log,
      );
      final centralDrive = ProcessLeonardDrive(onLog: log);
      final followerDrive = ProcessLeonardDrive(onLog: log);
      final reports = <TestReport>[];

      try {
        final centralEndpoint = await centralRunner.launch(
          LaunchSpec(
            app: 'butane_harness',
            target: centralTarget,
            role: 'central',
            followerDevice: centralDevice,
            harnessDirectory: harnessDirectory,
          ),
        );
        final followerEndpoint = await followerRunner.launch(
          LaunchSpec(
            app: 'butane_harness',
            target: followerTarget,
            followerDevice: followerDevice,
            harnessDirectory: harnessDirectory,
          ),
        );
        expect(centralEndpoint.isPublished, isTrue, reason: 'central endpoint');
        expect(
          followerEndpoint.isPublished,
          isTrue,
          reason: 'follower endpoint',
        );
        await centralDrive.attach(centralEndpoint);
        await followerDrive.attach(followerEndpoint);

        for (final scenario in scenarios) {
          final report = await runDriveScenario(
            drive: followerDrive,
            localDrive: centralDrive,
            scenario: scenario,
            endpoint: followerEndpoint,
            central: centralTarget,
            follower: followerTarget,
            centralIdentity: centralEndpoint.station,
            centralLaunchOutcome: BurnLaunchOutcome.launched,
            centralTeardownConfirmation: BurnTeardownConfirmation.notObserved,
            followerIdentity: followerEndpoint.station,
            followerLaunchOutcome: BurnLaunchOutcome.launched,
            followerTeardownConfirmation: BurnTeardownConfirmation.notObserved,
          );
          reports.add(report);
          _printReport(report);
          // Each scenario publishes the NUS service; clear it for the next.
          await _bestEffort(
            () => followerDrive.invoke('butane.stop_advertising', const {}),
          );
          await _bestEffort(
            () => followerDrive.invoke('butane.remove_service', const {
              'uuid': kNusServiceUuid,
            }),
          );
        }
      } finally {
        await _bestEffort(centralRunner.teardown);
        await _bestEffort(followerRunner.teardown);
      }

      expect(
        [
          for (final report in reports)
            if (!report.passed) report.scenario,
        ],
        isEmpty,
        reason: 'failing scenarios',
      );
    },
    timeout: const Timeout(Duration(minutes: 40)),
  );
}

FollowerLauncher _launcherFor(
  String target,
  String device,
  String harnessDirectory,
  void Function(String) log,
) => switch (target) {
  'macos' => MacosCentralLauncher(
    readyTimeout: const Duration(minutes: 5),
    onLog: log,
  ),
  'ios' => IosFollowerLauncher(
    deviceId: device,
    harnessDirectory: harnessDirectory,
    onLog: log,
  ),
  'android' => AndroidFollowerLauncher(
    deviceId: device,
    harnessDirectory: harnessDirectory,
    onLog: log,
  ),
  _ => throw ArgumentError.value(target, 'target', 'macos|ios|android'),
};

void _printReport(TestReport report) {
  stdout.writeln(
    'PAIR_SCENARIO ${report.scenario}: '
    '${report.passed ? 'PASS' : 'FAIL'} '
    '(${report.total - report.failures}/${report.total})',
  );
  for (final step in report.steps) {
    stdout.writeln(
      '  ${step.outcome.name.padRight(11)} ${step.role.name.padRight(8)} '
      '${step.description}',
    );
    if (!step.passed) {
      stdout.writeln('      observed: ${_clip(step.observed)}');
    }
  }
  stdout.writeln('PAIR_REPORT ${jsonEncode(report.toJson())}');
}

String _clip(String text) =>
    text.length <= 400 ? text : '${text.substring(0, 400)}…';

Future<void> _bestEffort(Future<Object?> Function() action) async {
  try {
    await action();
  } on Object catch (error) {
    stderr.writeln('[pair] cleanup: $error');
  }
}
