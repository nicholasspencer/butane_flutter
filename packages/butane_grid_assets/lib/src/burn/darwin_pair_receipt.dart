/// Receipt mapping for the direct iOS-follower x macOS-central proof.
library;

import 'burn_order_inputs.dart';
import 'burn_report.dart';
import 'burn_scenario.dart';
import 'follower.dart';

/// Canonical metadata keys for the direct Darwin-pair proof.
///
/// These keys are deliberately isolated from the resident `burn.*` routing
/// namespace so that a physical-pair receipt cannot allocate the burn circuit.
abstract final class DarwinPairMetadataKeys {
  /// Physical iOS follower device identifier.
  static const String followerDevice = 'darwin_pair.follower_device';

  /// Absolute directory containing the dual-role Flutter harness.
  static const String harnessDirectory = 'darwin_pair.harness_dir';

  /// Absolute path to the Leonard drive entry point.
  static const String leonardDrive = 'darwin_pair.leonard_drive';

  /// Flutter target name used for the follower role.
  static const String followerTarget = 'darwin_pair.follower_target';

  /// Flutter target name used for the central role.
  static const String centralTarget = 'darwin_pair.central_target';

  /// JSON-encoded list of physical-pair preconditions.
  static const String preconditions = 'darwin_pair.preconditions';
}

/// Resolves isolated Darwin-pair [metadata] as resident burn inputs.
///
/// Every Darwin key must contain a non-empty string. Unrelated metadata,
/// including resident `burn.*` values, is ignored and the source map is never
/// mutated.
BurnOrderInputs resolveDarwinPairInputs(Map<String, dynamic> metadata) {
  String read(String key) {
    final value = metadata[key];
    if (value is! String || value.trim().isEmpty) {
      throw StateError('$key must be a non-empty string');
    }
    return value;
  }

  final resolutionLog = <String>[];
  final inputs = BurnOrderInputs.resolve(
    metadata: <String, dynamic>{
      BurnOrderInputs.followerDeviceKey: read(
        DarwinPairMetadataKeys.followerDevice,
      ),
      BurnOrderInputs.harnessDirectoryKey: read(
        DarwinPairMetadataKeys.harnessDirectory,
      ),
      BurnOrderInputs.leonardDriveKey: read(
        DarwinPairMetadataKeys.leonardDrive,
      ),
      BurnOrderInputs.followerTargetKey: read(
        DarwinPairMetadataKeys.followerTarget,
      ),
      BurnOrderInputs.centralTargetKey: read(
        DarwinPairMetadataKeys.centralTarget,
      ),
      BurnOrderInputs.preconditionsKey: read(
        DarwinPairMetadataKeys.preconditions,
      ),
    },
    environment: const <String, String>{},
    onLog: resolutionLog.add,
  );
  if (resolutionLog.isNotEmpty) {
    throw StateError(
      'Darwin pair metadata unexpectedly used an environment fallback: '
      '$resolutionLog',
    );
  }
  return inputs;
}

/// Maps [role]'s steps in [report] to `PASS` only when the non-empty subset all
/// passed.
String darwinPairRoleOutcome(TestReport report, BurnDeviceRole role) {
  final steps = report.steps.where((step) => step.role == role).toList();
  return steps.isNotEmpty &&
          steps.every((step) => step.outcome == BurnStepOutcome.passed)
      ? 'PASS'
      : 'FAIL';
}

/// Maps [role] across [reports] to `PASS` only when every non-empty report set
/// passes that role.
String darwinPairCrossScenarioRoleOutcome(
  List<TestReport> reports,
  BurnDeviceRole role,
) =>
    reports.isNotEmpty &&
        reports.every((report) => darwinPairRoleOutcome(report, role) == 'PASS')
    ? 'PASS'
    : 'FAIL';

/// Maps the unique report named [scenario] to its aggregate `PASS` or `FAIL`.
String darwinPairScenarioOutcome(List<TestReport> reports, String scenario) =>
    reports.singleWhere((report) => report.scenario == scenario).passed
    ? 'PASS'
    : 'FAIL';

/// Projects [report] as durable JSON with completeness and per-role outcomes.
Map<String, Object?> darwinPairScenarioReceipt(TestReport report) =>
    <String, Object?>{
      ...report.toJson(),
      'complete': report.steps.every(
        (step) => step.outcome != BurnStepOutcome.notObserved,
      ),
      'roleOutcomes': <String, String>{
        BurnDeviceRole.central.wire: darwinPairRoleOutcome(
          report,
          BurnDeviceRole.central,
        ),
        BurnDeviceRole.follower.wire: darwinPairRoleOutcome(
          report,
          BurnDeviceRole.follower,
        ),
      },
    };

/// Recommends the Darwin bridge verdict from exactly two scenario reports.
///
/// Both passing reports are `proven`; fully observed reports with at least one
/// failure are `experimental`; any incomplete evidence is `held-back`.
String darwinPairRecommendation(List<TestReport> reports) {
  if (reports.length != 2) {
    throw ArgumentError.value(
      reports.length,
      'reports',
      'Darwin pair evidence requires exactly two reports',
    );
  }
  if (reports.every((report) => report.passed)) return 'proven';
  if (reports.every(
    (report) => report.steps.every(
      (step) => step.outcome != BurnStepOutcome.notObserved,
    ),
  )) {
    return 'experimental';
  }
  return 'held-back';
}

/// Builds a report retaining every unobserved [scenario] step after launch or
/// attach failure.
///
/// A published endpoint records a launched role; a null endpoint records its
/// launch as failed.
TestReport darwinPairUnobservedReport({
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
