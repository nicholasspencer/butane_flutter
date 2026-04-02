/// The result of a single scenario step.
class StepResult {
  StepResult({
    required this.name,
    required this.success,
    required this.duration,
    this.error,
  });

  /// Human-readable name of the step.
  final String name;

  /// Whether the step completed successfully.
  final bool success;

  /// Wall-clock duration of the step.
  final Duration duration;

  /// Error message if the step failed.
  final String? error;

  @override
  String toString() {
    final status = success ? 'PASS' : 'FAIL';
    final ms = duration.inMilliseconds;
    final errorSuffix = error != null ? ' ($error)' : '';
    return '$status  ${ms}ms  $name$errorSuffix';
  }
}
