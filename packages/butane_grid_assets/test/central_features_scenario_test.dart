import 'package:butane_grid_assets/src/burn/burn_scenario.dart';
import 'package:butane_grid_assets/src/burn/scenarios.dart';
import 'package:test/test.dart';

void main() {
  String expectationFor(DriveScenario scenario, String tool) =>
      scenario.steps.lastWhere((step) => step.tool == tool).expectContains;

  test(
    'a Darwin central must report every unhonoured option as unsupported',
    () {
      for (final target in ['macos', 'ios']) {
        final scenario = centralFeaturesScenario(centralTarget: target);
        final unsupported = scenario.steps
            .where((step) => step.expectContains == kUnsupportedError)
            .map((step) => [step.tool, step.args])
            .toList();

        expect(unsupported, [
          ['butane.request_enable', <String, Object?>{}],
          [
            'butane.connect',
            {'autoConnect': false},
          ],
          [
            'butane.connect',
            {'refreshGattCache': true},
          ],
          ['butane.bond_state', <String, Object?>{}],
          ['butane.bond', <String, Object?>{}],
        ]);
        expect(
          scenario.steps
              .lastWhere((step) => step.tool == 'butane.connect')
              .args,
          {'timeoutMs': 20000},
        );
      }
    },
  );

  test('an Android central must honour every option', () {
    final scenario = centralFeaturesScenario(centralTarget: 'android');

    expect(
      scenario.steps.where((step) => step.expectContains == kUnsupportedError),
      isEmpty,
    );
    expect(
      scenario.steps.where((step) => step.tool == 'butane.connect').single.args,
      {'timeoutMs': 20000, 'autoConnect': false, 'refreshGattCache': true},
    );
    expect(expectationFor(scenario, 'butane.bond'), '"bonded":true');
    expect(
      expectationFor(scenario, 'butane.request_enable'),
      '"requested":true',
    );
  });

  test('the peripheral publishes the descriptor the central must discover', () {
    final scenario = centralFeaturesScenario(centralTarget: 'android');
    final addService = scenario.steps.firstWhere(
      (step) => step.tool == 'butane.add_service',
    );

    expect(addService.on, DriveEndpoint.follower);
    expect(addService.args.toString(), contains(kUserDescriptionUuid));
    expect(
      expectationFor(scenario, 'butane.discover_characteristics'),
      kUserDescriptionUuid,
    );
  });
}
