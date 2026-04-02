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

  /// Base64 of "BUTANE" — preconfigured read response.
  static const String readValue = 'QlVUQU5F';

  /// Base64 of "HELLO" — write test value.
  static const String writeValue = 'SEVMTE8=';

  /// Base64 of "NOTIFIED" — notification test value.
  static const String notifyValue = 'Tk9USUZZRUQ=';
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

  /// Discovered peripheral ID, populated by scan step.
  String? _peripheralId;

  /// Run the full BLE flow: check_state → add_service → advertise → scan →
  /// connect → discover → read → write → subscribe → notify → disconnect.
  ///
  /// Returns results for all steps. A failed step aborts remaining steps
  /// that depend on it.
  Future<List<StepResult>> runFullBleFlow() async {
    final results = <StepResult>[];

    // 1. Check BLE state (central) — polls until poweredOn or timeout.
    results.add(
      await _runStep(
        'Check BLE state (central)',
        () => _waitForPoweredOn(central, 'central'),
      ),
    );

    // 2. Check BLE state (peripheral) — polls until poweredOn or timeout.
    results.add(
      await _runStep(
        'Check BLE state (peripheral)',
        () => _waitForPoweredOn(peripheral, 'peripheral'),
      ),
    );

    // Abort early if BLE is not powered on.
    if (!results.every((r) => r.success)) {
      return results;
    }

    // 2b. Clean up any stale state from previous runs.
    try {
      await peripheral.sendCommand(
        'stop_advertising',
        timeout: const Duration(seconds: 5),
      );
    } catch (_) {
      // Ignore — may not be advertising.
    }
    try {
      await peripheral.sendCommand(
        'remove_service',
        params: {'uuid': TestUuids.service},
        timeout: const Duration(seconds: 5),
      );
    } catch (_) {
      // Ignore — service may not exist.
    }

    // 3. Set read response on peripheral (so central can read a known value).
    results.add(
      await _runStep(
        'Set read response (peripheral)',
        () => peripheral.sendCommand(
          'set_read_response',
          params: {
            'serviceUuid': TestUuids.service,
            'characteristicUuid': TestUuids.characteristic,
            'value': TestUuids.readValue,
          },
        ),
      ),
    );

    // 4. Add service (peripheral)
    results.add(
      await _runStep(
        'Add service (peripheral)',
        () => peripheral.sendCommand(
          'add_service',
          params: {
            'uuid': TestUuids.service,
            'isPrimary': true,
            'characteristics': [
              {
                'uuid': TestUuids.characteristic,
                'properties': {
                  'read': true,
                  'write': true,
                },
                'permissions': {
                  'readable': true,
                  'writeable': true,
                },
                // No 'value' — dynamic characteristics must have nil value
                // for CoreBluetooth to invoke delegate callbacks.
              },
              {
                'uuid': TestUuids.notifyCharacteristic,
                'properties': {
                  'read': true,
                  'notify': true,
                },
                'permissions': {
                  'readable': true,
                },
                // No 'value' — notifications are sent via updateValue.
              },
            ],
          },
        ),
      ),
    );

    // 5. Start advertising (peripheral)
    results.add(
      await _runStep(
        'Start advertising (peripheral)',
        () => peripheral.sendCommand(
          'start_advertising',
          params: {
            'serviceUuids': [TestUuids.service],
          },
        ),
      ),
    );

    // 6. Scan (central) — captures peripheral ID for subsequent steps
    results.add(
      await _runStep(
        'Scan for peripheral (central)',
        () async {
          final resp = await central.sendCommand(
            'scan',
            params: {
              'serviceUuids': [TestUuids.service],
            },
          );
          // Extract peripheral ID from scan result.
          final data = resp['data'] as Map<String, dynamic>?;
          final peripheralMap =
              data?['peripheral'] as Map<String, dynamic>?;
          _peripheralId = peripheralMap?['id'] as String?;
          if (_peripheralId == null) {
            throw StateError('Scan returned no peripheral ID');
          }
          return resp;
        },
      ),
    );

    // Abort if scan failed (no peripheral ID for subsequent steps).
    if (_peripheralId == null) {
      return results;
    }

    // 7. Connect (central)
    results.add(
      await _runStep(
        'Connect to peripheral (central)',
        () => central.sendCommand(
          'connect',
          params: {
            'peripheralId': _peripheralId,
          },
        ),
      ),
    );

    // Abort if connect failed.
    if (!results.last.success) {
      return results;
    }

    // 8. Discover services (central)
    results.add(
      await _runStep(
        'Discover services (central)',
        () async {
          final resp = await central.sendCommand(
            'discover_services',
            params: {
              'peripheralId': _peripheralId,
            },
          );
          final data = resp['data'] as Map<String, dynamic>?;
          final services = data?['services'] as List<dynamic>?;
          if (services == null || services.isEmpty) {
            throw StateError('No services discovered');
          }
          return resp;
        },
      ),
    );

    // 9. Discover characteristics (central)
    results.add(
      await _runStep(
        'Discover characteristics (central)',
        () async {
          final resp = await central.sendCommand(
            'discover_characteristics',
            params: {
              'peripheralId': _peripheralId,
              'serviceUuid': TestUuids.service,
            },
          );
          final data = resp['data'] as Map<String, dynamic>?;
          final chars = data?['characteristics'] as List<dynamic>?;
          if (chars == null || chars.isEmpty) {
            throw StateError('No characteristics discovered');
          }
          return resp;
        },
      ),
    );

    // 10. Read characteristic (central)
    results.add(
      await _runStep(
        'Read characteristic (central)',
        () async {
          final resp = await central.sendCommand(
            'read_characteristic',
            params: {
              'peripheralId': _peripheralId,
              'serviceUuid': TestUuids.service,
              'characteristicUuid': TestUuids.characteristic,
            },
          );
          final data = resp['data'] as Map<String, dynamic>?;
          final value = data?['value'] as String?;
          if (value != TestUuids.readValue) {
            throw StateError(
              'Read value "$value" != expected "${TestUuids.readValue}"',
            );
          }
          return resp;
        },
      ),
    );

    // 11. Write characteristic (central)
    results.add(
      await _runStep(
        'Write characteristic (central)',
        () => central.sendCommand(
          'write_characteristic',
          params: {
            'peripheralId': _peripheralId,
            'serviceUuid': TestUuids.service,
            'characteristicUuid': TestUuids.characteristic,
            'value': TestUuids.writeValue,
          },
        ),
      ),
    );

    // 11b. Verify write was received by peripheral.
    results.add(
      await _runStep(
        'Verify write (peripheral)',
        () async {
          // Small delay for write to propagate.
          await Future<void>.delayed(const Duration(milliseconds: 500));
          final resp = await peripheral.sendCommand(
            'get_written_value',
            params: {
              'serviceUuid': TestUuids.service,
              'characteristicUuid': TestUuids.characteristic,
            },
          );
          final data = resp['data'] as Map<String, dynamic>?;
          final value = data?['value'] as String?;
          if (value != TestUuids.writeValue) {
            throw StateError(
              'Written value "$value" != expected "${TestUuids.writeValue}"',
            );
          }
          return resp;
        },
      ),
    );

    // 12. Subscribe to notifications (central)
    results.add(
      await _runStep(
        'Subscribe to notifications (central)',
        () => central.sendCommand(
          'subscribe',
          params: {
            'peripheralId': _peripheralId,
            'serviceUuid': TestUuids.service,
            'characteristicUuid': TestUuids.notifyCharacteristic,
          },
        ),
      ),
    );

    // 13. Trigger notification (peripheral) and verify central receives it.
    //
    // Allow BLE subscription to stabilize before triggering notification.
    await Future<void>.delayed(const Duration(seconds: 1));

    results.add(
      await _runStep(
        'Notification round-trip',
        () async {
          // Listen for notification event on central.
          final notificationFuture = central.events
              .firstWhere(
                (event) => event['event'] == 'notification',
              )
              .timeout(
                const Duration(seconds: 10),
                onTimeout: () => throw TimeoutException(
                  'No notification received within 10s',
                ),
              );

          // Trigger notification from peripheral.
          final updateResp = await peripheral.sendCommand(
            'update_value',
            params: {
              'serviceUuid': TestUuids.service,
              'characteristicUuid': TestUuids.notifyCharacteristic,
              'value': TestUuids.notifyValue,
            },
          );

          // Verify the peripheral acknowledged the update.
          final updateData =
              updateResp['data'] as Map<String, dynamic>? ?? {};
          final sent = updateData['sent'] as bool? ?? false;
          if (!sent) {
            throw StateError(
              'Peripheral updateValue returned sent=false — '
              'no subscribers or transmit queue full',
            );
          }

          final event = await notificationFuture;
          final value = event['value'] as String?;
          if (value != TestUuids.notifyValue) {
            throw StateError(
              'Notification value "$value" != '
              'expected "${TestUuids.notifyValue}"',
            );
          }
          return <String, dynamic>{'notified': true, 'value': value};
        },
      ),
    );

    // 14. Disconnect (central)
    results.add(
      await _runStep(
        'Disconnect (central)',
        () => central.sendCommand(
          'disconnect',
          params: {
            'peripheralId': _peripheralId,
          },
        ),
      ),
    );

    // 15. Post-run cleanup: stop advertising and remove service so
    //     subsequent runs start fresh.
    try {
      await peripheral.sendCommand(
        'stop_advertising',
        timeout: const Duration(seconds: 5),
      );
    } catch (_) {}
    try {
      await peripheral.sendCommand(
        'remove_service',
        params: {'uuid': TestUuids.service},
        timeout: const Duration(seconds: 5),
      );
    } catch (_) {}

    return results;
  }

  /// Polls check_state until BLE reports poweredOn, or throws after ~60s.
  ///
  /// After a clean build, macOS may take 1-2 minutes to deliver
  /// the Bluetooth authorization callback to the app.
  Future<Map<String, dynamic>> _waitForPoweredOn(
    HarnessClient client,
    String label,
  ) async {
    const maxAttempts = 120;
    for (var i = 0; i < maxAttempts; i++) {
      final resp = await client.sendCommand('check_state');
      final state = resp['data']?['state'] as String?;
      if (state == 'poweredOn') {
        return resp;
      }
      if (state == 'unsupported' || state == 'unauthorized') {
        throw StateError(
          '$label BLE state is "$state" — cannot proceed. '
          'Check Bluetooth permission and hardware.',
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    throw TimeoutException(
      '$label BLE did not reach poweredOn within ${maxAttempts ~/ 2}s. '
      'If this is the first run after a clean build, macOS may need to '
      're-authorize Bluetooth access. Check System Settings > Privacy & '
      'Security > Bluetooth.',
    );
  }

  Future<StepResult> _runStep(
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
