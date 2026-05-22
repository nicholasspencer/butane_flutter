import 'package:butane_coordinator/butane_coordinator.dart';
import 'package:test/test.dart';

void main() {
  test('NusSuite.scenarioNames returns ordered list of 7 scenarios', () {
    // Mock harness clients (not used in this test).
    // We're testing the orchestration structure, not actual execution.
    final suite = NusSuite(
      central: _MockHarnessClient(),
      peripheral: _MockHarnessClient(),
    );

    final names = suite.scenarioNames;
    expect(names, hasLength(7));
    expect(
      names,
      [
        'round-trip',
        'notify-lifecycle',
        'large-write',
        'burst-writes',
        'reconnect',
        'peripheral-vanishes',
        'cancel-mid-discovery',
      ],
    );
  });

  test('NusSuite.runOne throws ArgumentError on unknown scenario', () async {
    final suite = NusSuite(
      central: _MockHarnessClient(),
      peripheral: _MockHarnessClient(),
    );

    expect(
      () => suite.runOne('unknown-scenario'),
      throwsA(
        isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          contains('Unknown NUS scenario'),
        ),
      ),
    );
  });

  test('StepRunner.runStep wraps success response correctly', () async {
    final result = await StepRunner.runStep(
      'test-step',
      () async => {'success': true, 'data': 'ok'},
    );

    expect(result.name, 'test-step');
    expect(result.success, isTrue);
    expect(result.error, isNull);
    expect(result.duration, greaterThan(Duration.zero));
  });

  test('StepRunner.runStep wraps failure response correctly', () async {
    final result = await StepRunner.runStep(
      'failing-step',
      () async => {'success': false, 'error': 'something went wrong'},
    );

    expect(result.name, 'failing-step');
    expect(result.success, isFalse);
    expect(result.error, 'something went wrong');
  });

  test('StepRunner.runStep catches exceptions and wraps in StepResult',
      () async {
    final result = await StepRunner.runStep(
      'throwing-step',
      () async => throw StateError('boom'),
    );

    expect(result.name, 'throwing-step');
    expect(result.success, isFalse);
    expect(result.error, isNotNull);
    expect(result.error, contains('boom'));
  });

  test('StepRunner.runStep defaults success to true when not in response',
      () async {
    final result = await StepRunner.runStep(
      'no-success-key',
      () async => {'data': 'ok'},
    );

    expect(result.success, isTrue);
    expect(result.error, isNull);
  });
}

/// Minimal mock of HarnessClient for testing orchestration logic.
class _MockHarnessClient extends HarnessClient {
  _MockHarnessClient()
      : super(
          role: 'mock',
          host: '127.0.0.1',
          port: 8080,
        );

  @override
  Future<Map<String, dynamic>> sendCommand(
    String action, {
    Map<String, dynamic> params = const {},
    Duration? timeout,
  }) async {
    // Mock implementation: return a success response for any command.
    return <String, dynamic>{'success': true, 'data': <String, dynamic>{}};
  }

  @override
  Stream<Map<String, dynamic>> get events {
    // Mock implementation: return an empty stream.
    return Stream.empty();
  }
}
