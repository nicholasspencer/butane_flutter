/// The NAMED butane drive scenarios — the burn's scenario registry.
///
/// Scenarios are SCRIPTED (zero inference) and two-endpoint: follower steps
/// drive the leased peripheral harness, `on: DriveEndpoint.local` steps the
/// host's own central. Every scenario gates BOTH adapters on
/// `wait_for_state` first — BLE ops invoked before poweredOn hang in
/// CoreBluetooth (proven by this suite's first live run).
library;

import 'burn_scenario.dart';

/// Nordic UART Service (the bench profile carried over from the
/// butane_coordinator NUS suite).
const String kNusServiceUuid = '6e400001-b5a3-f393-e0a9-e50e24dcca9e';

/// NUS TX (notify) characteristic.
const String kNusTxUuid = '6e400003-b5a3-f393-e0a9-e50e24dcca9e';

/// The two-drive smoke: adapters gated, a NUS-ish GATT table added +
/// advertised on the follower peripheral, perception observed on both ends.
/// Proven live-local (two real harnesses on one box).
const DriveScenario kSmokeScenario = DriveScenario(
  name: 'smoke',
  steps: [
    DriveStep.invoke(
      'butane.wait_for_state',
      expectContains: '"matched":true',
    ),
    DriveStep.invoke(
      'butane.wait_for_state',
      expectContains: '"matched":true',
      on: DriveEndpoint.local,
    ),
    DriveStep.invoke(
      'butane.add_service',
      args: {
        'uuid': kNusServiceUuid,
        'characteristics': [
          {
            'uuid': kNusTxUuid,
            'properties': {'read': true, 'notify': true},
            'permissions': {'readable': true},
          },
        ],
      },
      expectContains: 'added',
    ),
    DriveStep.invoke(
      'butane.start_advertising',
      args: {
        'localName': 'BURN-LIVE',
        'serviceUuids': [kNusServiceUuid],
      },
      expectContains: 'advertising',
    ),
    DriveStep.observe(
      'extensions.butane.data',
      expectContains: 'BURN-LIVE',
    ),
    DriveStep.invoke(
      'butane.check_state',
      expectContains: 'poweredOn',
      on: DriveEndpoint.local,
    ),
    DriveStep.observe(
      'extensions.butane.data.role',
      expectContains: 'central',
      on: DriveEndpoint.local,
    ),
  ],
);

/// The named scenario registry (`--scenario` on the burn run command). The
/// NUS round-trip suite (scan → connect → discover → write → notify) lands
/// here next.
const Map<String, DriveScenario> kButaneScenarios = {
  'smoke': kSmokeScenario,
};
