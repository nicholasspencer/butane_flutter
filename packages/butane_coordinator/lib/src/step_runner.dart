import 'step_result.dart';

/// Shared helper for executing a single step and wrapping the result.
/// Used by both ScenarioRunner and NusSuite to avoid duplication.
class StepRunner {
  StepRunner._();

  /// Executes a step function, timing it and wrapping success/error into a StepResult.
  static Future<StepResult> runStep(
    String name,
    Future<Map<String, dynamic>> Function() action,
  ) async {
    final stopwatch = Stopwatch()..start();
    try {
      final response = await action();
      stopwatch.stop();
      final success = response['success'] as bool? ?? true;
      return StepResult(
        name: name,
        success: success,
        duration: stopwatch.elapsed,
        error: success ? null : response['error'] as String?,
      );
    } catch (e) {
      stopwatch.stop();
      return StepResult(
        name: name,
        success: false,
        duration: stopwatch.elapsed,
        error: e.toString(),
      );
    }
  }
}
