import 'step_result.dart';

/// Aggregate result of one bench scenario. A scenario wraps multiple
/// harness calls (each captured as a `StepResult`). The outer
/// `success`/`duration`/`error` give the suite roll-up; `steps` and
/// `diagnostics` give detail for failure analysis.
class ScenarioResult {
  ScenarioResult({
    required this.name,
    required this.success,
    required this.duration,
    this.error,
    List<StepResult>? steps,
    Map<String, dynamic>? diagnostics,
  })  : steps = steps ?? const <StepResult>[],
        diagnostics = diagnostics ?? const <String, dynamic>{};

  final String name;
  final bool success;
  final Duration duration;
  final String? error;
  final List<StepResult> steps;
  final Map<String, dynamic> diagnostics;

  @override
  String toString() {
    final status = success ? 'PASS' : 'FAIL';
    final ms = duration.inMilliseconds;
    final errSfx = error != null ? ' ($error)' : '';
    return '$status  ${ms}ms  $name$errSfx';
  }
}
