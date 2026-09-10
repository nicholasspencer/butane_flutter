import 'package:butane_grid_assets/src/burn/burn_order_inputs.dart';
import 'package:butane_grid_assets/src/burn/burn_report.dart';
import 'package:butane_grid_assets/src/burn/burn_scenario.dart';
import 'package:butane_grid_assets/src/burn/darwin_pair_receipt.dart';
import 'package:butane_grid_assets/src/burn/follower.dart';
import 'package:test/test.dart';

const _smoke = DriveScenario(
  name: 'smoke',
  steps: <DriveStep>[
    DriveStep.observe('butane.central.state', on: DriveEndpoint.local),
    DriveStep.invoke('butane.start_advertising'),
  ],
);
const _nus = DriveScenario(
  name: 'nus-round-trip',
  steps: <DriveStep>[
    DriveStep.invoke('butane.scan', on: DriveEndpoint.local),
    DriveStep.observe('butane.peripheral.state'),
  ],
);
const _inputs = BurnOrderInputs(
  followerDevice: 'ios-device',
  harnessDirectory: '/harness',
  leonardDrive: '/leonard_drive',
  followerTarget: 'ios',
  centralTarget: 'macos',
);
const _centralEndpoint = FollowerEndpoint(
  vmServiceUri: 'ws://127.0.0.1:4101/ws',
  station: 'mac-station',
);
const _followerEndpoint = FollowerEndpoint(
  vmServiceUri: 'ws://127.0.0.1:4102/ws',
  station: 'ipad-station',
);

void main() {
  group('Darwin pair outcomes', () {
    test('maps role subsets and aggregate scenario outcomes', () {
      final passed = _report(
        scenario: _smoke,
        centralOutcome: BurnStepOutcome.passed,
        followerOutcome: BurnStepOutcome.passed,
        passed: true,
      );
      final centralFailed = _report(
        scenario: _nus,
        centralOutcome: BurnStepOutcome.failed,
        followerOutcome: BurnStepOutcome.passed,
      );
      final followerFailed = _report(
        scenario: _nus,
        centralOutcome: BurnStepOutcome.passed,
        followerOutcome: BurnStepOutcome.failed,
      );

      expect(darwinPairRoleOutcome(passed, BurnDeviceRole.central), 'PASS');
      expect(darwinPairRoleOutcome(passed, BurnDeviceRole.follower), 'PASS');
      expect(
        darwinPairRoleOutcome(centralFailed, BurnDeviceRole.central),
        'FAIL',
      );
      expect(
        darwinPairRoleOutcome(centralFailed, BurnDeviceRole.follower),
        'PASS',
      );
      expect(
        darwinPairRoleOutcome(followerFailed, BurnDeviceRole.central),
        'PASS',
      );
      expect(
        darwinPairRoleOutcome(followerFailed, BurnDeviceRole.follower),
        'FAIL',
      );
      expect(
        darwinPairRoleOutcome(
          _report(
            scenario: _smoke,
            centralOutcome: BurnStepOutcome.passed,
            followerOutcome: null,
            passed: true,
          ),
          BurnDeviceRole.follower,
        ),
        'FAIL',
      );
      expect(
        darwinPairCrossScenarioRoleOutcome(<TestReport>[
          passed,
          followerFailed,
        ], BurnDeviceRole.central),
        'PASS',
      );
      expect(
        darwinPairCrossScenarioRoleOutcome(<TestReport>[
          passed,
          centralFailed,
        ], BurnDeviceRole.central),
        'FAIL',
      );
      expect(
        darwinPairCrossScenarioRoleOutcome(
          const <TestReport>[],
          BurnDeviceRole.central,
        ),
        'FAIL',
      );
      expect(
        darwinPairScenarioOutcome(<TestReport>[passed, centralFailed], 'smoke'),
        'PASS',
      );
      expect(
        darwinPairScenarioOutcome(<TestReport>[
          passed,
          centralFailed,
        ], 'nus-round-trip'),
        'FAIL',
      );
    });

    test('projects every report field with completeness and role outcomes', () {
      final report = TestReport(
        scenario: 'smoke',
        endpoint: 'ws://127.0.0.1:4102/ws',
        central: 'macos',
        follower: 'ios',
        centralIdentity: 'mac-station',
        centralLaunchOutcome: BurnLaunchOutcome.launched,
        centralTeardownConfirmation: BurnTeardownConfirmation.notObserved,
        followerIdentity: 'ipad-station',
        followerLaunchOutcome: BurnLaunchOutcome.launched,
        followerTeardownConfirmation: BurnTeardownConfirmation.confirmed,
        steps: const <DriveStepResult>[
          DriveStepResult(
            description: '[local] observe butane.central.state',
            observed: '{ready: true}',
            role: BurnDeviceRole.central,
            outcome: BurnStepOutcome.passed,
            duration: Duration(milliseconds: 11),
          ),
          DriveStepResult(
            description: 'invoke butane.start_advertising',
            observed: '{ok: false}',
            role: BurnDeviceRole.follower,
            outcome: BurnStepOutcome.failed,
            duration: Duration(milliseconds: 23),
          ),
        ],
        passed: false,
      );

      expect(darwinPairScenarioReceipt(report), <String, Object?>{
        'scenario': 'smoke',
        'endpoint': 'ws://127.0.0.1:4102/ws',
        'central': 'macos',
        'follower': 'ios',
        'passed': false,
        'total': 2,
        'failures': 1,
        'observedSteps': 2,
        'devices': <Map<String, Object?>>[
          <String, Object?>{
            'identity': 'mac-station',
            'role': 'central',
            'target': 'macos',
            'launchOutcome': 'launched',
            'teardownConfirmation': 'not-observed',
          },
          <String, Object?>{
            'identity': 'ipad-station',
            'role': 'follower',
            'target': 'ios',
            'launchOutcome': 'launched',
            'teardownConfirmation': 'confirmed',
          },
        ],
        'steps': <Map<String, Object?>>[
          <String, Object?>{
            'description': '[local] observe butane.central.state',
            'observed': '{ready: true}',
            'passed': true,
            'role': 'central',
            'outcome': 'passed',
            'durationMs': 11,
          },
          <String, Object?>{
            'description': 'invoke butane.start_advertising',
            'observed': '{ok: false}',
            'passed': false,
            'role': 'follower',
            'outcome': 'failed',
            'durationMs': 23,
          },
        ],
        'complete': true,
        'roleOutcomes': <String, String>{'central': 'PASS', 'follower': 'FAIL'},
      });

      final incomplete = _report(
        scenario: _smoke,
        centralOutcome: BurnStepOutcome.notObserved,
        followerOutcome: BurnStepOutcome.passed,
      );
      expect(darwinPairScenarioReceipt(incomplete)['complete'], isFalse);
    });
  });

  test('recommends proven, experimental, or held-back from two reports', () {
    final smokePassed = _report(
      scenario: _smoke,
      centralOutcome: BurnStepOutcome.passed,
      followerOutcome: BurnStepOutcome.passed,
      passed: true,
    );
    final nusPassed = _report(
      scenario: _nus,
      centralOutcome: BurnStepOutcome.passed,
      followerOutcome: BurnStepOutcome.passed,
      passed: true,
    );
    final observedFailure = _report(
      scenario: _nus,
      centralOutcome: BurnStepOutcome.failed,
      followerOutcome: BurnStepOutcome.passed,
    );
    final incomplete = _report(
      scenario: _nus,
      centralOutcome: BurnStepOutcome.notObserved,
      followerOutcome: BurnStepOutcome.passed,
    );

    expect(
      darwinPairRecommendation(<TestReport>[smokePassed, nusPassed]),
      'proven',
    );
    expect(
      darwinPairRecommendation(<TestReport>[smokePassed, observedFailure]),
      'experimental',
    );
    expect(
      darwinPairRecommendation(<TestReport>[smokePassed, incomplete]),
      'held-back',
    );
    expect(
      () => darwinPairRecommendation(<TestReport>[smokePassed]),
      throwsArgumentError,
    );
  });

  test(
    'retains every unobserved fallback field for null and present roles',
    () {
      final missingFollower = darwinPairUnobservedReport(
        scenario: _smoke,
        inputs: _inputs,
        centralEndpoint: _centralEndpoint,
        followerEndpoint: null,
      );

      expect(missingFollower.scenario, 'smoke');
      expect(missingFollower.endpoint, isEmpty);
      expect(missingFollower.central, 'macos');
      expect(missingFollower.follower, 'ios');
      expect(missingFollower.centralIdentity, 'mac-station');
      expect(missingFollower.centralLaunchOutcome, BurnLaunchOutcome.launched);
      expect(
        missingFollower.centralTeardownConfirmation,
        BurnTeardownConfirmation.notObserved,
      );
      expect(missingFollower.followerIdentity, isEmpty);
      expect(missingFollower.followerLaunchOutcome, BurnLaunchOutcome.failed);
      expect(
        missingFollower.followerTeardownConfirmation,
        BurnTeardownConfirmation.notObserved,
      );
      expect(missingFollower.passed, isFalse);
      expect(missingFollower.steps.length, _smoke.steps.length);
      for (var index = 0; index < missingFollower.steps.length; index++) {
        final step = missingFollower.steps[index];
        expect(step.description, _smoke.steps[index].description);
        expect(step.observed, 'not-observed');
        expect(
          step.role,
          _smoke.steps[index].on == DriveEndpoint.local
              ? BurnDeviceRole.central
              : BurnDeviceRole.follower,
        );
        expect(step.outcome, BurnStepOutcome.notObserved);
        expect(step.duration, isNull);
      }

      final missingCentral = darwinPairUnobservedReport(
        scenario: _nus,
        inputs: _inputs,
        centralEndpoint: null,
        followerEndpoint: _followerEndpoint,
      );
      expect(missingCentral.endpoint, 'ws://127.0.0.1:4102/ws');
      expect(missingCentral.centralIdentity, isEmpty);
      expect(missingCentral.centralLaunchOutcome, BurnLaunchOutcome.failed);
      expect(missingCentral.followerIdentity, 'ipad-station');
      expect(missingCentral.followerLaunchOutcome, BurnLaunchOutcome.launched);
      expect(missingCentral.steps.length, _nus.steps.length);
      expect(
        missingCentral.steps.map((step) => step.outcome),
        everyElement(BurnStepOutcome.notObserved),
      );
    },
  );
}

TestReport _report({
  required DriveScenario scenario,
  required BurnStepOutcome centralOutcome,
  required BurnStepOutcome? followerOutcome,
  bool passed = false,
}) => TestReport(
  scenario: scenario.name,
  endpoint: _followerEndpoint.vmServiceUri,
  central: _inputs.centralTarget,
  follower: _inputs.followerTarget,
  centralIdentity: _centralEndpoint.station,
  centralLaunchOutcome: BurnLaunchOutcome.launched,
  centralTeardownConfirmation: BurnTeardownConfirmation.notObserved,
  followerIdentity: _followerEndpoint.station,
  followerLaunchOutcome: BurnLaunchOutcome.launched,
  followerTeardownConfirmation: BurnTeardownConfirmation.notObserved,
  steps: <DriveStepResult>[
    DriveStepResult(
      description: '${scenario.name} central',
      observed: centralOutcome.wire,
      role: BurnDeviceRole.central,
      outcome: centralOutcome,
      duration: centralOutcome == BurnStepOutcome.notObserved
          ? null
          : const Duration(milliseconds: 1),
    ),
    if (followerOutcome != null)
      DriveStepResult(
        description: '${scenario.name} follower',
        observed: followerOutcome.wire,
        role: BurnDeviceRole.follower,
        outcome: followerOutcome,
        duration: followerOutcome == BurnStepOutcome.notObserved
            ? null
            : const Duration(milliseconds: 2),
      ),
  ],
  passed: passed,
);
