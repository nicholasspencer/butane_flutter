/// Direct live proof for the physical iOS-follower x macOS-central pair.
///
/// The test deliberately composes the launchers, process-backed Leonard
/// channels, and scripted scenarios below the resident burn composition. Its
/// structured stdout receipts are the complete input to the separate governor
/// verdict.
@Tags(['integration'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:butane_grid_assets/src/burn/burn_order_inputs.dart';
import 'package:butane_grid_assets/src/burn/burn_preflight_io.dart';
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

const _beadId = 'butane_flutter-pfey';

typedef _ToolObservation = ({Object observed, bool ok});

void main() {
  test('Darwin pair records smoke and NUS receipts for iOS follower and macOS '
      'central', () async {
    final selectedBead = Platform.environment['DARWIN_PAIR_BEAD'];
    _require(selectedBead == _beadId, 'DARWIN_PAIR_BEAD must equal $_beadId');

    final metadata = await _loadBeadMetadata(selectedBead!);
    for (final key in <String>[
      BurnOrderInputs.followerDeviceKey,
      BurnOrderInputs.harnessDirectoryKey,
      BurnOrderInputs.leonardDriveKey,
      BurnOrderInputs.followerTargetKey,
      BurnOrderInputs.centralTargetKey,
      BurnOrderInputs.preconditionsKey,
    ]) {
      _requireMetadataString(metadata, key);
    }

    final resolutionLog = <String>[];
    final inputs = BurnOrderInputs.resolve(
      metadata: metadata,
      environment: const <String, String>{},
      onLog: resolutionLog.add,
    );
    _require(
      resolutionLog.isEmpty,
      'canonical burn metadata must resolve without environment fallback: '
      '$resolutionLog',
    );
    _require(
      Platform.environment['LEONARD_E2E_DEVICE'] == inputs.followerDevice,
      'LEONARD_E2E_DEVICE must equal the resolved burn.follower_device',
    );
    _require(
      inputs.followerTarget == 'ios',
      'burn.follower_target must equal ios',
    );
    _require(
      inputs.centralTarget == 'macos',
      'burn.central_target must equal macos',
    );
    _require(
      inputs.preconditions.length == 1 &&
          inputs.preconditions.single.kind ==
              BurnPreconditionKind.followerIosAttached,
      'burn.preconditions must contain exactly follower-ios-attached',
    );

    await systemBurnPreflight().validate(inputs);
    _emit('DARWIN_PAIR_PREFLIGHT', <String, Object?>{
      'status': 'PASS',
      'device': inputs.followerDevice,
      'harnessDirectory': inputs.harnessDirectory,
      'leonardDrive': inputs.leonardDrive,
      'precondition': inputs.preconditions.single.declaration,
    });

    final macosLaunch =
        'cd packages/butane_harness && flutter run --profile -d macos '
        '--dart-define=ROLE=central';
    final iosLaunch =
        'cd packages/butane_harness && flutter run --profile '
        '-d ${inputs.followerDevice} --dart-define=ROLE=peripheral';
    _emit('DARWIN_PAIR_COMMANDS', <String, Object?>{
      'macosLaunch': macosLaunch,
      'iosLaunch': iosLaunch,
    });

    void liveLog(String line) => stderr.writeln('[darwin-pair] $line');

    final centralDrive = ProcessLeonardDrive(
      executableOverride: inputs.leonardDrive,
      onLog: liveLog,
    );
    final followerDrive = ProcessLeonardDrive(
      executableOverride: inputs.leonardDrive,
      onLog: liveLog,
    );
    final centralRunner = ButaneFollowerRunner(
      launcher: MacosCentralLauncher(
        readyTimeout: const Duration(minutes: 5),
        onLog: liveLog,
      ),
      processes: const SystemProcessGroupController(),
      onLog: liveLog,
    );
    final followerRunner = ButaneFollowerRunner(
      launcher: IosFollowerLauncher(onLog: liveLog),
      processes: const SystemProcessGroupController(),
      onLog: liveLog,
    );

    FollowerEndpoint? centralEndpoint;
    FollowerEndpoint? followerEndpoint;
    final diagnostics = <String>[];
    final reports = <TestReport>[];
    final scenarioReceipts = <Map<String, Object?>>[];
    final teardownReceipts = <Map<String, Object?>>[];
    var permissionCandidate = false;

    void recordScenario(TestReport report) {
      reports.add(report);
      final receipt = _scenarioReceipt(report);
      scenarioReceipts.add(receipt);
      _emit('DARWIN_PAIR_SCENARIO', receipt);
    }

    try {
      try {
        final endpoint = await centralRunner.launch(
          LaunchSpec(
            app: 'butane_harness',
            target: inputs.centralTarget,
            role: 'central',
            harnessDirectory: inputs.harnessDirectory,
            leonardDrive: inputs.leonardDrive,
          ),
        );
        if (endpoint.isPublished) {
          centralEndpoint = endpoint;
        } else {
          diagnostics.add('macos central published no endpoint');
        }
      } on Object catch (error) {
        diagnostics.add('macos central launch failed: $error');
      }

      try {
        final endpoint = await followerRunner.launch(
          LaunchSpec(
            app: 'butane_harness',
            target: inputs.followerTarget,
            role: 'peripheral',
            followerDevice: inputs.followerDevice,
            harnessDirectory: inputs.harnessDirectory,
            leonardDrive: inputs.leonardDrive,
          ),
        );
        if (endpoint.isPublished) {
          followerEndpoint = endpoint;
        } else {
          diagnostics.add('iOS follower published no endpoint');
        }
      } on Object catch (error) {
        diagnostics.add('iOS follower launch failed: $error');
      }

      if (centralEndpoint == null || followerEndpoint == null) {
        for (final scenario in const <DriveScenario>[
          kSmokeScenario,
          kNusRoundTripScenario,
        ]) {
          recordScenario(
            _unobservedReport(
              scenario: scenario,
              inputs: inputs,
              centralEndpoint: centralEndpoint,
              followerEndpoint: followerEndpoint,
            ),
          );
        }
      } else {
        Object? centralAttachError;
        Object? followerAttachError;
        try {
          await centralDrive.attach(centralEndpoint);
        } on Object catch (error) {
          centralAttachError = error;
          diagnostics.add('macos central drive attach failed: $error');
        }
        try {
          await followerDrive.attach(followerEndpoint);
        } on Object catch (error) {
          followerAttachError = error;
          diagnostics.add('iOS follower drive attach failed: $error');
        }

        if (centralAttachError != null || followerAttachError != null) {
          for (final scenario in const <DriveScenario>[
            kSmokeScenario,
            kNusRoundTripScenario,
          ]) {
            recordScenario(
              _unobservedReport(
                scenario: scenario,
                inputs: inputs,
                centralEndpoint: centralEndpoint,
                followerEndpoint: followerEndpoint,
              ),
            );
          }
        } else {
          final readiness = await _invoke(
            centralDrive,
            'butane.wait_for_state',
            const <String, Object?>{'timeoutMs': 10000},
          );
          if (!_readinessMatched(readiness)) {
            permissionCandidate = true;
            _emit('DARWIN_PAIR_PERMISSION_CANDIDATE', <String, Object?>{
              'observed': readiness.observed,
            });
          } else {
            recordScenario(
              await _runScenario(
                scenario: kSmokeScenario,
                inputs: inputs,
                centralEndpoint: centralEndpoint,
                followerEndpoint: followerEndpoint,
                centralDrive: centralDrive,
                followerDrive: followerDrive,
              ),
            );

            final stopAdvertising = await _invoke(
              followerDrive,
              'butane.stop_advertising',
              const <String, Object?>{},
            );
            final removeService = await _invoke(
              followerDrive,
              'butane.remove_service',
              const <String, Object?>{'uuid': kNusServiceUuid},
            );
            _emit('DARWIN_PAIR_TRANSITION', <String, Object?>{
              'stopAdvertising': stopAdvertising.observed,
              'removeService': removeService.observed,
            });

            if (stopAdvertising.ok && removeService.ok) {
              recordScenario(
                await _runScenario(
                  scenario: kNusRoundTripScenario,
                  inputs: inputs,
                  centralEndpoint: centralEndpoint,
                  followerEndpoint: followerEndpoint,
                  centralDrive: centralDrive,
                  followerDrive: followerDrive,
                ),
              );
            } else {
              diagnostics.add(
                'NUS scenario held: smoke-to-NUS cleanup did not succeed',
              );
              recordScenario(
                _unobservedReport(
                  scenario: kNusRoundTripScenario,
                  inputs: inputs,
                  centralEndpoint: centralEndpoint,
                  followerEndpoint: followerEndpoint,
                ),
              );
            }
          }
        }
      }
    } finally {
      final centralTeardown = await _teardown(
        role: BurnDeviceRole.central,
        drive: centralDrive,
        runner: centralRunner,
      );
      teardownReceipts.add(centralTeardown);
      _emit('DARWIN_PAIR_TEARDOWN', centralTeardown);

      final followerTeardown = await _teardown(
        role: BurnDeviceRole.follower,
        drive: followerDrive,
        runner: followerRunner,
      );
      teardownReceipts.add(followerTeardown);
      _emit('DARWIN_PAIR_TEARDOWN', followerTeardown);
    }

    if (permissionCandidate) {
      _expectTeardownReceipts(teardownReceipts);
      return;
    }

    final allComplete = scenarioReceipts.every(
      (receipt) => receipt['complete'] == true,
    );
    final recommendation = reports.every((report) => report.passed)
        ? 'proven'
        : allComplete
        ? 'experimental'
        : 'held-back';
    final summary = <String, Object?>{
      'recommendation': recommendation,
      'smoke': _reportOutcome(reports, kSmokeScenario.name),
      'nus-round-trip': _reportOutcome(reports, kNusRoundTripScenario.name),
      'ios': _crossScenarioRoleOutcome(reports, BurnDeviceRole.follower),
      'macos': _crossScenarioRoleOutcome(reports, BurnDeviceRole.central),
      'complete': allComplete,
      if (diagnostics.isNotEmpty) 'diagnostics': diagnostics,
    };
    _emit('DARWIN_PAIR_SUMMARY', summary);

    expect(
      scenarioReceipts.map((receipt) => receipt['scenario']).toList(),
      <String>[kSmokeScenario.name, kNusRoundTripScenario.name],
    );
    expect((scenarioReceipts[0]['steps']! as List<Object?>).length, 7);
    expect((scenarioReceipts[1]['steps']! as List<Object?>).length, 14);
    for (final receipt in scenarioReceipts) {
      expect(receipt['complete'], isA<bool>());
      final roleOutcomes = receipt['roleOutcomes']! as Map<String, String>;
      expect(roleOutcomes.keys.toSet(), <String>{'central', 'follower'});
      expect(roleOutcomes.values, everyElement(isIn(<String>['PASS', 'FAIL'])));
    }
    _expectTeardownReceipts(teardownReceipts);
  }, timeout: const Timeout(Duration(minutes: 30)));
}

Future<Map<String, dynamic>> _loadBeadMetadata(String beadId) async {
  final result = await Process.run('bd', <String>['show', beadId, '--json']);
  _require(
    result.exitCode == 0,
    'bd show $beadId --json exited ${result.exitCode}: ${result.stderr}',
  );
  final decoded = jsonDecode(result.stdout as String);
  _require(
    decoded is List<dynamic> && decoded.length == 1,
    'bd show $beadId --json must return exactly one bead',
  );
  final bead = _stringKeyedMap((decoded as List<dynamic>).single, 'bead');
  return _stringKeyedMap(bead['metadata'], 'bead metadata');
}

Map<String, dynamic> _stringKeyedMap(Object? value, String label) {
  _require(value is Map<dynamic, dynamic>, '$label must be a JSON object');
  final source = value as Map<dynamic, dynamic>;
  final result = <String, dynamic>{};
  for (final entry in source.entries) {
    _require(entry.key is String, '$label keys must be strings');
    result[entry.key! as String] = entry.value;
  }
  return result;
}

void _requireMetadataString(Map<String, dynamic> metadata, String key) {
  final value = metadata[key];
  _require(
    value is String && value.trim().isNotEmpty,
    '$key must be a non-empty canonical metadata string',
  );
}

Future<TestReport> _runScenario({
  required DriveScenario scenario,
  required BurnOrderInputs inputs,
  required FollowerEndpoint centralEndpoint,
  required FollowerEndpoint followerEndpoint,
  required ProcessLeonardDrive centralDrive,
  required ProcessLeonardDrive followerDrive,
}) => runDriveScenario(
  drive: followerDrive,
  localDrive: centralDrive,
  scenario: scenario,
  endpoint: followerEndpoint,
  central: inputs.centralTarget,
  follower: inputs.followerTarget,
  centralIdentity: centralEndpoint.station,
  centralLaunchOutcome: BurnLaunchOutcome.launched,
  centralTeardownConfirmation: BurnTeardownConfirmation.notObserved,
  followerIdentity: followerEndpoint.station,
  followerLaunchOutcome: BurnLaunchOutcome.launched,
  followerTeardownConfirmation: BurnTeardownConfirmation.notObserved,
);

TestReport _unobservedReport({
  required DriveScenario scenario,
  required BurnOrderInputs inputs,
  required FollowerEndpoint? centralEndpoint,
  required FollowerEndpoint? followerEndpoint,
}) => unobservedDriveReport(
  scenario: scenario,
  endpoint: followerEndpoint?.vmServiceUri ?? '',
  central: inputs.centralTarget,
  follower: inputs.followerTarget,
  centralIdentity: centralEndpoint?.station ?? '',
  centralLaunchOutcome: centralEndpoint == null
      ? BurnLaunchOutcome.failed
      : BurnLaunchOutcome.launched,
  centralTeardownConfirmation: BurnTeardownConfirmation.notObserved,
  followerIdentity: followerEndpoint?.station ?? '',
  followerLaunchOutcome: followerEndpoint == null
      ? BurnLaunchOutcome.failed
      : BurnLaunchOutcome.launched,
  followerTeardownConfirmation: BurnTeardownConfirmation.notObserved,
);

Map<String, Object?> _scenarioReceipt(TestReport report) {
  final receipt = <String, Object?>{...report.toJson()};
  receipt['complete'] = report.steps.every(
    (step) => step.outcome != BurnStepOutcome.notObserved,
  );
  receipt['roleOutcomes'] = <String, String>{
    BurnDeviceRole.central.wire: _roleOutcome(report, BurnDeviceRole.central),
    BurnDeviceRole.follower.wire: _roleOutcome(report, BurnDeviceRole.follower),
  };
  return receipt;
}

String _roleOutcome(TestReport report, BurnDeviceRole role) {
  final steps = report.steps.where((step) => step.role == role).toList();
  return steps.isNotEmpty &&
          steps.every((step) => step.outcome == BurnStepOutcome.passed)
      ? 'PASS'
      : 'FAIL';
}

String _crossScenarioRoleOutcome(
  List<TestReport> reports,
  BurnDeviceRole role,
) =>
    reports.isNotEmpty &&
        reports.every((report) => _roleOutcome(report, role) == 'PASS')
    ? 'PASS'
    : 'FAIL';

String _reportOutcome(List<TestReport> reports, String scenario) =>
    reports.singleWhere((report) => report.scenario == scenario).passed
    ? 'PASS'
    : 'FAIL';

Future<_ToolObservation> _invoke(
  ProcessLeonardDrive drive,
  String tool,
  Map<String, Object?> args,
) async {
  try {
    final observed = jsonDecode(await drive.invoke(tool, args));
    return (
      observed: observed as Object,
      ok: observed is Map<dynamic, dynamic> && observed['ok'] == true,
    );
  } on Object catch (error) {
    return (observed: <String, Object?>{'error': '$error'}, ok: false);
  }
}

bool _readinessMatched(_ToolObservation observation) {
  if (!observation.ok || observation.observed is! Map<dynamic, dynamic>) {
    return false;
  }
  final outer = observation.observed as Map<dynamic, dynamic>;
  final inner = outer['value'];
  return inner is Map<dynamic, dynamic> && inner['matched'] == true;
}

Future<Map<String, Object?>> _teardown({
  required BurnDeviceRole role,
  required ProcessLeonardDrive drive,
  required ButaneFollowerRunner runner,
}) async {
  String driveClose;
  String runnerReap;
  try {
    await drive.close();
    driveClose = 'confirmed';
  } on Object catch (error) {
    driveClose = 'failed: $error';
  }
  try {
    runnerReap = (await runner.teardown()).name;
  } on Object catch (error) {
    runnerReap = 'failed: $error';
  }
  return <String, Object?>{
    'role': role.wire,
    'attempted': true,
    'driveClose': driveClose,
    'runnerReap': runnerReap,
    'confirmed': driveClose == 'confirmed' && !runnerReap.startsWith('failed:'),
  };
}

void _expectTeardownReceipts(List<Map<String, Object?>> receipts) {
  expect(receipts.length, 2);
  expect(receipts.map((receipt) => receipt['role']).toSet(), <String>{
    'central',
    'follower',
  });
  expect(receipts.map((receipt) => receipt['attempted']), everyElement(isTrue));
}

void _emit(String kind, Map<String, Object?> receipt) {
  stdout.writeln('$kind=${jsonEncode(receipt)}');
}

void _require(bool condition, String message) {
  if (!condition) throw StateError(message);
}
