/// The burn's domain-defined result value types (ADR-0011 D9): a [TestReport]
/// collected by the `burn-host` order after it drives the leased follower app
/// over the DIRECT perception channel.
///
/// Plain immutable value types (predictable-flutter: value types are plain), no
/// codegen — the butane domain owns its own result shape, exactly as the compute
/// domain owns `CommandResult`.
library;

import 'package:meta/meta.dart';

/// The participating device's role in a burn.
enum BurnDeviceRole {
  /// The host-side central harness.
  central('central'),

  /// The leased follower harness.
  follower('follower');

  const BurnDeviceRole(this.wire);

  /// The stable value used in durable burn evidence.
  final String wire;
}

/// Whether a participating device's harness launch was observed.
enum BurnLaunchOutcome {
  /// The harness published an endpoint and was launched.
  launched('launched'),

  /// The harness launch raised an error.
  failed('failed'),

  /// The launch was not entered or its outcome was unavailable.
  notObserved('not-observed');

  const BurnLaunchOutcome(this.wire);

  /// The stable value used in durable burn evidence.
  final String wire;
}

/// Whether teardown of a participating device was confirmed.
enum BurnTeardownConfirmation {
  /// Teardown completed and was confirmed.
  confirmed('confirmed'),

  /// Teardown was entered but failed.
  failed('failed'),

  /// Teardown was not entered or its outcome was unavailable.
  notObserved('not-observed');

  const BurnTeardownConfirmation(this.wire);

  /// The stable value used in durable burn evidence.
  final String wire;
}

/// The observed outcome of one scripted burn step.
enum BurnStepOutcome {
  /// The step ran and satisfied its scripted expectation.
  passed('passed'),

  /// The step ran but did not satisfy its scripted expectation.
  failed('failed'),

  /// The step was not entered.
  notObserved('not-observed');

  const BurnStepOutcome(this.wire);

  /// The stable value used in durable burn evidence.
  final String wire;
}

/// The outcome of ONE scripted drive step (ADR-0011 D9) — what the host
/// observed/invoked over `ext.exploration.*` and whether it satisfied the
/// step's scripted expectation.
@immutable
class DriveStepResult {
  /// Creates a step result: a human [description] (`observe cli` /
  /// `invoke grid.ready`), the [observed] output read over the perception
  /// channel, the device [role], the step [outcome], and its [duration] when
  /// the step was entered.
  const DriveStepResult({
    required this.description,
    required this.observed,
    required this.role,
    required this.outcome,
    required this.duration,
  });

  /// A human-readable description of the step (the action + its target).
  final String description;

  /// The output observed/returned over the direct perception channel.
  final String observed;

  /// The device role whose direct perception channel this step targeted.
  final BurnDeviceRole role;

  /// Whether this step passed, failed, or was not entered.
  final BurnStepOutcome outcome;

  /// How long the step took, or null when it was not entered.
  final Duration? duration;

  /// Whether the step's scripted expectation held.
  bool get passed => outcome == BurnStepOutcome.passed;

  /// JSON form.
  Map<String, dynamic> toJson() => {
    'description': description,
    'observed': observed,
    'passed': passed,
    'role': role.wire,
    'outcome': outcome.wire,
    'durationMs': duration?.inMilliseconds ?? BurnStepOutcome.notObserved.wire,
  };

  @override
  String toString() => 'DriveStepResult($description, passed: $passed)';
}

/// The burn's collected report (ADR-0011 D9) — the domain result the `burn-host`
/// order produces after running a SCRIPTED scenario against the leased follower
/// app. The engine records a summary on the_grid's OWN session bead; the full
/// value type is the domain's to interpret.
@immutable
class TestReport {
  /// Creates a report for [scenario] driven against [endpoint], with the per-step
  /// [steps] results and the aggregate [passed] verdict.
  const TestReport({
    required this.scenario,
    required this.endpoint,
    required this.central,
    required this.follower,
    required this.centralIdentity,
    required this.centralLaunchOutcome,
    required this.centralTeardownConfirmation,
    required this.followerIdentity,
    required this.followerLaunchOutcome,
    required this.followerTeardownConfirmation,
    required this.steps,
    required this.passed,
  });

  /// The scenario name that was driven.
  final String scenario;

  /// The follower VM-service endpoint that was driven (the direct channel).
  final String endpoint;

  /// The platform running the local central harness.
  final String central;

  /// The platform running the leased follower harness.
  final String follower;

  /// The station identity that ran the central harness.
  final String centralIdentity;

  /// The observed launch outcome for the central harness.
  final BurnLaunchOutcome centralLaunchOutcome;

  /// The observed teardown confirmation for the central harness.
  final BurnTeardownConfirmation centralTeardownConfirmation;

  /// The station identity that ran the follower harness.
  final String followerIdentity;

  /// The observed launch outcome for the follower harness.
  final BurnLaunchOutcome followerLaunchOutcome;

  /// The observed teardown confirmation for the follower harness.
  final BurnTeardownConfirmation followerTeardownConfirmation;

  /// The per-step results, in execution order.
  final List<DriveStepResult> steps;

  /// Whether EVERY step passed (and at least one ran).
  final bool passed;

  /// The total number of steps that ran.
  int get total => steps.length;

  /// The number of steps whose scripted assertion failed.
  int get failures =>
      steps.where((s) => s.outcome == BurnStepOutcome.failed).length;

  /// The number of declared steps whose outcome was observed.
  int get observedSteps =>
      steps.where((s) => s.outcome != BurnStepOutcome.notObserved).length;

  /// The zero-based index of the first failed step, or null when none failed.
  int? get failingStepIndex {
    final index = steps.indexWhere(
      (step) => step.outcome == BurnStepOutcome.failed,
    );
    return index < 0 ? null : index;
  }

  /// Stable single-line receipt recorded for a passing resident burn.
  String get receipt =>
      'burn-receipt: scenario=$scenario; passed=$passed; '
      'central=$central; follower=$follower';

  /// JSON form.
  Map<String, dynamic> toJson() => {
    'scenario': scenario,
    'endpoint': endpoint,
    'central': central,
    'follower': follower,
    'passed': passed,
    'total': total,
    'failures': failures,
    'observedSteps': observedSteps,
    'devices': [
      {
        'identity': centralIdentity,
        'role': BurnDeviceRole.central.wire,
        'target': central,
        'launchOutcome': centralLaunchOutcome.wire,
        'teardownConfirmation': centralTeardownConfirmation.wire,
      },
      {
        'identity': followerIdentity,
        'role': BurnDeviceRole.follower.wire,
        'target': follower,
        'launchOutcome': followerLaunchOutcome.wire,
        'teardownConfirmation': followerTeardownConfirmation.wire,
      },
    ],
    'steps': [for (final s in steps) s.toJson()],
  };

  @override
  String toString() =>
      'TestReport($scenario, passed: $passed, $failures/$total failed)';
}

/// Returns the bounded, prose-free burn evidence persisted on a passing step.
///
/// Keys stay dot-free because the engine persists the payload field after its
/// final metadata dot. The projection deliberately excludes endpoints,
/// descriptions, observations, logs, and rationale.
Map<String, String> burnResultPayload(TestReport report) {
  final payload = <String, String>{
    'scenario': report.scenario,
    'passed': '${report.passed}',
    'central': report.central,
    'follower': report.follower,
    'steps': '${report.total}',
    'failures': '${report.failures}',
    'observedSteps': '${report.observedSteps}',
    'centralIdentity': _observedValue(report.centralIdentity),
    'centralRole': BurnDeviceRole.central.wire,
    'centralTarget': _observedValue(report.central),
    'centralLaunchOutcome': report.centralLaunchOutcome.wire,
    'centralTeardownConfirmation': report.centralTeardownConfirmation.wire,
    'followerIdentity': _observedValue(report.followerIdentity),
    'followerRole': BurnDeviceRole.follower.wire,
    'followerTarget': _observedValue(report.follower),
    'followerLaunchOutcome': report.followerLaunchOutcome.wire,
    'followerTeardownConfirmation': report.followerTeardownConfirmation.wire,
  };
  for (var index = 0; index < report.steps.length; index++) {
    final step = report.steps[index];
    payload['step${index}Role'] = step.role.wire;
    payload['step${index}Outcome'] = step.outcome.wire;
    payload['step${index}DurationMs'] =
        step.duration?.inMilliseconds.toString() ??
        BurnStepOutcome.notObserved.wire;
  }
  return payload;
}

/// Returns the bounded evidence suffix used when a failed burn is supervised.
///
/// The digest is a single CR/LF-free line containing device launch evidence and
/// the first failed step index. Unknown values are explicit rather than empty.
String burnFailureDigest(TestReport report) =>
    'burn-evidence: scenario=${_digestValue(report.scenario)}; '
    'centralIdentity=${_digestValue(report.centralIdentity)}; '
    'centralRole=${BurnDeviceRole.central.wire}; '
    'centralTarget=${_digestValue(report.central)}; '
    'centralLaunchOutcome=${report.centralLaunchOutcome.wire}; '
    'followerIdentity=${_digestValue(report.followerIdentity)}; '
    'followerRole=${BurnDeviceRole.follower.wire}; '
    'followerTarget=${_digestValue(report.follower)}; '
    'followerLaunchOutcome=${report.followerLaunchOutcome.wire}; '
    'failingStepIndex=${report.failingStepIndex?.toString() ?? BurnStepOutcome.notObserved.wire}';

String _observedValue(String value) =>
    value.isEmpty ? BurnStepOutcome.notObserved.wire : value;

String _digestValue(String value) =>
    _observedValue(value).replaceAll(RegExp(r'[\r\n]'), ' ');
