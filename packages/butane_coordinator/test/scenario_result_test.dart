import 'package:butane_coordinator/butane_coordinator.dart';
import 'package:test/test.dart';

void main() {
  test('ScenarioResult.toString includes PASS, ms, name', () {
    final r = ScenarioResult(
      name: 'round-trip',
      success: true,
      duration: const Duration(milliseconds: 812),
    );
    expect(r.toString(), contains('PASS'));
    expect(r.toString(), contains('812ms'));
    expect(r.toString(), contains('round-trip'));
  });

  test('ScenarioResult.toString failure includes error suffix', () {
    final r = ScenarioResult(
      name: 'x',
      success: false,
      duration: const Duration(milliseconds: 1),
      error: 'boom',
    );
    expect(r.toString(), contains('FAIL'));
    expect(r.toString(), contains('(boom)'));
  });
}
