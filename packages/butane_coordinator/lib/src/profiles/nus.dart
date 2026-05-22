/// Well-known UUIDs and helpers for the Nordic UART Service (NUS).
///
/// Kept separate from `TestUuids` so the existing custom-UUID flow in
/// `ScenarioRunner.runFullBleFlow()` is untouched.
class NusUuids {
  NusUuids._();

  static const String service = '6E400001-B5A3-F393-E0A9-E50E24DCCA9E';
  // ignore: constant_identifier_names
  /// RX: central writes, peripheral receives.
  static const String rx = '6E400002-B5A3-F393-E0A9-E50E24DCCA9E';
  // ignore: constant_identifier_names
  /// TX: peripheral notifies, central subscribes.
  static const String tx = '6E400003-B5A3-F393-E0A9-E50E24DCCA9E';

  /// Payload for the `add_service` peripheral harness command. Mirrors
  /// the structure used in `scenario.dart` (no static `value` on either
  /// characteristic — see the CoreBluetooth delegate-callback comments
  /// there). RX must support both `write` and `writeWithoutResponse`
  /// because the `burst-writes` scenario uses writeWithoutResponse.
  static Map<String, dynamic> buildAddServicePayload() => {
    'uuid': service,
    'isPrimary': true,
    'characteristics': [
      {
        'uuid': rx,
        'properties': {
          'write': true,
          'writeWithoutResponse': true,
        },
        'permissions': {
          'writeable': true,
        },
      },
      {
        'uuid': tx,
        'properties': {
          'notify': true,
        },
        'permissions': {
          'readable': true,
        },
      },
    ],
  };
}
