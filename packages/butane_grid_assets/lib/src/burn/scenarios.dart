/// The NAMED butane drive scenarios — the burn's scenario registry.
///
/// Scenarios are SCRIPTED (zero inference) and two-endpoint: follower steps
/// drive the leased peripheral harness, `on: DriveEndpoint.local` steps the
/// host's own central. Every scenario gates BOTH adapters on
/// `wait_for_state` first — BLE ops invoked before poweredOn hang in
/// CoreBluetooth (proven by this suite's first live run).
library;

import 'burn_scenario.dart';

/// Nordic UART Service used by the bench profile.
const String kNusServiceUuid = '6e400001-b5a3-f393-e0a9-e50e24dcca9e';

/// NUS RX (central → peripheral write) characteristic.
const String kNusRxUuid = '6e400002-b5a3-f393-e0a9-e50e24dcca9e';

/// NUS TX (peripheral → central notify) characteristic.
const String kNusTxUuid = '6e400003-b5a3-f393-e0a9-e50e24dcca9e';

/// The two-drive smoke: adapters gated, a NUS-ish GATT table added +
/// advertised on the follower peripheral, perception observed on both ends.
/// Proven live-local (two real harnesses on one box).
const DriveScenario kSmokeScenario = DriveScenario(
  name: 'smoke',
  steps: [
    DriveStep.invoke('butane.wait_for_state', expectContains: '"matched":true'),
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
    DriveStep.observe('extensions.butane.data', expectContains: 'BURN-LIVE'),
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

/// The REAL-RADIO NUS round-trip: the follower peripheral publishes the NUS
/// GATT table and advertises; the local central scans it off the air,
/// connects, discovers, writes `burn` to RX (verified byte-for-byte on the
/// peripheral), subscribes to TX, and receives the peripheral's `pong`
/// notification. Central commands omit `peripheralId` — the harness targets
/// the most recently scanned peripheral (static steps cannot thread the scan
/// result forward).
const DriveScenario kNusRoundTripScenario = DriveScenario(
  name: 'nus-round-trip',
  steps: [
    // Gate both adapters (BLE ops before poweredOn hang in CoreBluetooth).
    DriveStep.invoke('butane.wait_for_state', expectContains: '"matched":true'),
    DriveStep.invoke(
      'butane.wait_for_state',
      expectContains: '"matched":true',
      on: DriveEndpoint.local,
    ),
    // Peripheral: NUS GATT table + advertise.
    DriveStep.invoke(
      'butane.add_service',
      args: {
        'uuid': kNusServiceUuid,
        'characteristics': [
          {
            'uuid': kNusRxUuid,
            'properties': {'write': true, 'writeWithoutResponse': true},
            'permissions': {'readable': true, 'writeable': true},
          },
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
        'localName': 'BURN-NUS',
        'serviceUuids': [kNusServiceUuid],
      },
      expectContains: 'advertising',
    ),
    // Central: off-the-air discovery → connect → GATT walk.
    DriveStep.invoke(
      'butane.scan',
      args: {
        'serviceUuids': [kNusServiceUuid],
      },
      expectContains: '"id":',
      on: DriveEndpoint.local,
    ),
    DriveStep.invoke(
      'butane.connect',
      expectContains: '"connected":true',
      on: DriveEndpoint.local,
    ),
    DriveStep.invoke(
      'butane.discover_services',
      args: {
        'serviceUuids': [kNusServiceUuid],
      },
      expectContains: kNusServiceUuid, // UUIDs are platform-cased
      on: DriveEndpoint.local,
      caseInsensitive: true,
    ),
    DriveStep.invoke(
      'butane.discover_characteristics',
      args: {'serviceUuid': kNusServiceUuid},
      expectContains: kNusRxUuid,
      on: DriveEndpoint.local,
      caseInsensitive: true,
    ),
    // Write `burn` over the air; the peripheral proves the bytes arrived.
    DriveStep.invoke(
      'butane.write_characteristic',
      args: {
        'serviceUuid': kNusServiceUuid,
        'characteristicUuid': kNusRxUuid,
        'value': 'YnVybg==', // base64('burn')
      },
      expectContains: '"written":true',
      on: DriveEndpoint.local,
    ),
    DriveStep.invoke(
      'butane.get_written_value',
      args: {'serviceUuid': kNusServiceUuid, 'characteristicUuid': kNusRxUuid},
      expectContains: 'YnVybg==',
    ),
    // Subscribe to TX; the peripheral notifies `pong`; the central gates on
    // its arrival (delivery is async — never a bare observe).
    DriveStep.invoke(
      'butane.subscribe',
      args: {'serviceUuid': kNusServiceUuid, 'characteristicUuid': kNusTxUuid},
      expectContains: '"subscribed":true',
      on: DriveEndpoint.local,
    ),
    DriveStep.invoke(
      'butane.update_value',
      args: {
        'serviceUuid': kNusServiceUuid,
        'characteristicUuid': kNusTxUuid,
        'value': 'cG9uZw==', // base64('pong')
      },
      expectContains: '"sent":true',
    ),
    DriveStep.invoke(
      'butane.wait_for_notification',
      args: {'serviceUuid': kNusServiceUuid, 'characteristicUuid': kNusTxUuid},
      expectContains: 'cG9uZw==',
      on: DriveEndpoint.local,
    ),
    // Clean disconnect closes the loop.
    DriveStep.invoke(
      'butane.disconnect',
      expectContains: '"disconnected":true',
      on: DriveEndpoint.local,
    ),
  ],
);

/// The named scenario registry (`--scenario` on the burn run command).
const Map<String, DriveScenario> kButaneScenarios = {
  'smoke': kSmokeScenario,
  'nus-round-trip': kNusRoundTripScenario,
};
