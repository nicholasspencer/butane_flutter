import 'dart:async';

import 'step_result.dart';
import 'ws_client.dart';

/// Well-known UUIDs for the test BLE service and characteristic.
class TestUuids {
  TestUuids._();

  /// Test service UUID.
  static const String service = '12345678-1234-5678-1234-56789abcdef0';

  /// Test read/write characteristic UUID.
  static const String characteristic = '12345678-1234-5678-1234-56789abcdef1';

  /// Test notify characteristic UUID.
  static const String notifyCharacteristic =
      '12345678-1234-5678-1234-56789abcdef2';
}

/// Runs BLE test scenarios against central and peripheral harness instances.
class ScenarioRunner {
  ScenarioRunner({
    required this.central,
    required this.peripheral,
  });

  /// The central-role harness client.
  final HarnessClient central;

  /// The peripheral-role harness client.
  final HarnessClient peripheral;

  /// Run the full BLE flow: advertise → scan → connect → discover → read →
  /// write → subscribe → notify → disconnect.
  ///
  /// Returns results for all 12 steps. Failed steps do not abort the run.
  Future<List<StepResult>> runFullBleFlow() async {
    final results = <StepResult>[];

    // 1. Check BLE state (central)
    results.add(await _runStep(
      'Check BLE state (central)',
      () => central.sendCommand('getState'),
    ),);

    // 2. Check BLE state (peripheral)
    results.add(await _runStep(
      'Check BLE state (peripheral)',
      () => peripheral.sendCommand('getState'),
    ),);

    // 3. Add service (peripheral)
    results.add(await _runStep(
      'Add service (peripheral)',
      () => peripheral.sendCommand('addService', params: {
        'uuid': TestUuids.service,
        'characteristics': [
          {
            'uuid': TestUuids.characteristic,
            'properties': ['read', 'write'],
          },
          {
            'uuid': TestUuids.notifyCharacteristic,
            'properties': ['notify'],
          },
        ],
      },),
    ),);

    // 4. Start advertising (peripheral)
    results.add(await _runStep(
      'Start advertising (peripheral)',
      () => peripheral.sendCommand('startAdvertising', params: {
        'serviceUuids': [TestUuids.service],
      },),
    ),);

    // 5. Scan (central)
    results.add(await _runStep(
      'Scan for peripheral (central)',
      () => central.sendCommand('scan', params: {
        'serviceUuids': [TestUuids.service],
      },),
    ),);

    // 6. Connect (central)
    results.add(await _runStep(
      'Connect to peripheral (central)',
      () => central.sendCommand('connect'),
    ),);

    // 7. Discover services (central)
    results.add(await _runStep(
      'Discover services (central)',
      () => central.sendCommand('discoverServices'),
    ),);

    // 8. Discover characteristics (central)
    results.add(await _runStep(
      'Discover characteristics (central)',
      () => central.sendCommand('discoverCharacteristics', params: {
        'serviceUuid': TestUuids.service,
      },),
    ),);

    // 9. Read characteristic (central)
    results.add(await _runStep(
      'Read characteristic (central)',
      () => central.sendCommand('readCharacteristic', params: {
        'serviceUuid': TestUuids.service,
        'characteristicUuid': TestUuids.characteristic,
      },),
    ),);

    // 10. Write characteristic (central)
    results.add(await _runStep(
      'Write characteristic (central)',
      () => central.sendCommand('writeCharacteristic', params: {
        'serviceUuid': TestUuids.service,
        'characteristicUuid': TestUuids.characteristic,
        'value': 'SEVMTE8=', // base64 "HELLO"
      },),
    ),);

    // 11. Subscribe to notifications (central)
    results.add(await _runStep(
      'Subscribe to notifications (central)',
      () => central.sendCommand('subscribe', params: {
        'serviceUuid': TestUuids.service,
        'characteristicUuid': TestUuids.notifyCharacteristic,
      },),
    ),);

    // 12. Trigger notification (peripheral)
    results.add(await _runStep(
      'Trigger notification (peripheral)',
      () => peripheral.sendCommand('updateValue', params: {
        'serviceUuid': TestUuids.service,
        'characteristicUuid': TestUuids.notifyCharacteristic,
        'value': 'Tk9USUZZPQ==', // base64 "NOTIFIED"
      },),
    ),);

    return results;
  }

  Future<StepResult> _runStep(
    String name,
    Future<Map<String, dynamic>> Function() action,
  ) async {
    final stopwatch = Stopwatch()..start();
    try {
      final response = await action();
      stopwatch.stop();
      final success = response['success'] as bool? ?? false;
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
