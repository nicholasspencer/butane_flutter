/// Receipt mapping for the direct iOS-follower x macOS-central proof.
library;

import 'burn_order_inputs.dart';
import 'burn_report.dart';
import 'burn_scenario.dart';
import 'follower.dart';

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
