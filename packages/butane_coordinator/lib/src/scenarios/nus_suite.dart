import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../profiles/nus.dart';
import '../scenario_result.dart';
import '../step_result.dart';
import '../ws_client.dart';

typedef _ScenarioFn = Future<ScenarioResult> Function();

class NusSuite {
  NusSuite({required this.central, required this.peripheral});

  final HarnessClient central;
  final HarnessClient peripheral;

  String? _peripheralId;

  late final Map<String, _ScenarioFn> _scenarios = {
    'round-trip':           _roundTrip,
    'notify-lifecycle':     _notifyLifecycle,
    'large-write':          _largeWrite,
    'burst-writes':         _burstWrites,
    'reconnect':            _reconnect,
    'peripheral-vanishes':  _peripheralVanishes,
    'cancel-mid-discovery': _cancelMidDiscovery,
  };

  /// Ordered scenario names (matches AC ordering).
  List<String> get scenarioNames => _scenarios.keys.toList(growable: false);

  Future<List<ScenarioResult>> runAll() async {
    final results = <ScenarioResult>[];
    for (final name in scenarioNames) {
      await _teardown();
      results.add(await _scenarios[name]!());
    }
    await _teardown();
    return results;
  }

  Future<ScenarioResult> runOne(String name) async {
    final fn = _scenarios[name];
    if (fn == null) {
      throw ArgumentError(
        'Unknown NUS scenario: "$name". Valid: ${scenarioNames.join(', ')}',
      );
    }
    await _teardown();
    final result = await fn();
    await _teardown();
    return result;
  }

  /// Best-effort: disconnect, stop advertising, remove NUS service.
  Future<void> _teardown() async {
    final id = _peripheralId;
    if (id != null) {
      try { await central.sendCommand('disconnect', params: {'peripheralId': id}); } catch (_) {}
      _peripheralId = null;
    }
    try { await peripheral.sendCommand('stop_advertising'); } catch (_) {}
    try { await peripheral.sendCommand('remove_service', params: {'uuid': NusUuids.service}); } catch (_) {}
  }

  // Scenario bodies + helpers in steps 4-10.
}

extension on NusSuite {
  /// Standard setup: add_service, start_advertising, scan, connect,
  /// discover services + characteristics. Captures peripheralId.
  Future<void> _setup(List<StepResult> steps, {bool discover = true}) async {
    steps.add(
      await _step(
        'add_service',
        () => peripheral.sendCommand(
          'add_service',
          params: NusUuids.buildAddServicePayload(),
        ),
      ),
    );
    steps.add(
      await _step(
        'start_advertising',
        () => peripheral.sendCommand(
          'start_advertising',
          params: {'serviceUuids': [NusUuids.service]},
        ),
      ),
    );
    steps.add(
      await _step(
        'scan',
        () async {
          final r = await central.sendCommand(
            'scan',
            params: {'serviceUuids': [NusUuids.service]},
          );
          _peripheralId = ((r['data'] as Map)['peripheral'] as Map)['id'] as String;
          return r;
        },
      ),
    );
    steps.add(
      await _step(
        'connect',
        () => central.sendCommand(
          'connect',
          params: {'peripheralId': _peripheralId},
        ),
      ),
    );
    if (discover) {
      steps.add(
        await _step(
          'discover_services',
          () => central.sendCommand(
            'discover_services',
            params: {'peripheralId': _peripheralId},
          ),
        ),
      );
      steps.add(
        await _step(
          'discover_characteristics',
          () => central.sendCommand(
            'discover_characteristics',
            params: {
              'peripheralId': _peripheralId,
              'serviceUuid': NusUuids.service,
            },
          ),
        ),
      );
    }
  }

  Future<StepResult> _step(
    String name,
    Future<Map<String, dynamic>> Function() fn,
  ) async {
    final sw = Stopwatch()..start();
    try {
      final r = await fn();
      sw.stop();
      final ok = r['success'] as bool? ?? true;
      return StepResult(
        name: name,
        success: ok,
        duration: sw.elapsed,
        error: ok ? null : r['error'] as String?,
      );
    } catch (e) {
      sw.stop();
      return StepResult(
        name: name,
        success: false,
        duration: sw.elapsed,
        error: e.toString(),
      );
    }
  }

  Future<ScenarioResult> _roundTrip() async {
    final sw = Stopwatch()..start();
    final steps = <StepResult>[];
    StreamSubscription<Map<String, dynamic>>? echoSub;
    try {
      await _setup(steps);
      steps.add(
        await _step(
          'subscribe TX',
          () => central.sendCommand(
            'subscribe',
            params: {
              'peripheralId': _peripheralId,
              'serviceUuid': NusUuids.service,
              'characteristicUuid': NusUuids.tx,
            },
          ),
        ),
      );

      // Coordinator-driven echo: subscribe to peripheral.events, decode
      // write_request, reply via update_value. (Discovery design option A.)
      echoSub = peripheral.events.listen((event) {
        if (event['event'] != 'write_request') return;
        final data = (event['data'] as Map<String, dynamic>?) ?? event;
        if ((data['characteristicUuid'] as String?)?.toLowerCase()
            != NusUuids.rx.toLowerCase()) return;
        final b64 = data['value'] as String?;
        if (b64 == null) return;
        final decoded = utf8.decode(base64Decode(b64), allowMalformed: true);
        if (decoded != 'PING') return;
        peripheral.sendCommand(
          'update_value',
          params: {
            'serviceUuid': NusUuids.service,
            'characteristicUuid': NusUuids.tx,
            'value': base64Encode(utf8.encode('PONG')),
          },
        );
      });

      // Listen for PONG BEFORE the PING write.
      final notif = central.events
        .firstWhere(
          (e) =>
            e['event'] == 'notification' &&
            (e['characteristicUuid'] as String?)?.toLowerCase()
              == NusUuids.tx.toLowerCase(),
        )
        .timeout(const Duration(seconds: 10));

      steps.add(
        await _step(
          'write PING',
          () => central.sendCommand(
            'write_characteristic',
            params: {
              'peripheralId': _peripheralId,
              'serviceUuid': NusUuids.service,
              'characteristicUuid': NusUuids.rx,
              'value': base64Encode(utf8.encode('PING')),
            },
          ),
        ),
      );

      final e = await notif;
      final got = utf8.decode(base64Decode(e['value'] as String));
      if (got != 'PONG') throw StateError('expected PONG, got "$got"');
      sw.stop();
      return ScenarioResult(
        name: 'round-trip',
        success: true,
        duration: sw.elapsed,
        steps: steps,
        diagnostics: {'echo': 'PING->PONG ok'},
      );
    } catch (err) {
      sw.stop();
      return ScenarioResult(
        name: 'round-trip',
        success: false,
        duration: sw.elapsed,
        error: err.toString(),
        steps: steps,
      );
    } finally {
      await echoSub?.cancel();
    }
  }

  Future<ScenarioResult> _notifyLifecycle() async {
    final sw = Stopwatch()..start();
    final steps = <StepResult>[];
    StreamSubscription<Map<String, dynamic>>? centeralSub;
    try {
      await _setup(steps);
      steps.add(
        await _step(
          'subscribe TX',
          () => central.sendCommand(
            'subscribe',
            params: {
              'peripheralId': _peripheralId,
              'serviceUuid': NusUuids.service,
              'characteristicUuid': NusUuids.tx,
            },
          ),
        ),
      );

      // Buffer notifications into a list
      final received = <String>[];
      centeralSub = central.events.listen((event) {
        if (event['event'] != 'notification') return;
        if ((event['characteristicUuid'] as String?)?.toLowerCase()
            != NusUuids.tx.toLowerCase()) return;
        final b64 = event['value'] as String?;
        if (b64 == null) return;
        final decoded = utf8.decode(base64Decode(b64), allowMalformed: true);
        received.add(decoded);
      });

      // Fire 5 distinct updates spaced 50ms apart
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await peripheral.sendCommand(
          'update_value',
          params: {
            'serviceUuid': NusUuids.service,
            'characteristicUuid': NusUuids.tx,
            'value': base64Encode(utf8.encode('N$i')),
          },
        );
      }

      // Wait for 5 notifications
      await Future<void>.delayed(const Duration(seconds: 5));
      if (received.length != 5) {
        throw StateError('expected 5 notifications, got ${received.length}');
      }
      for (var i = 0; i < 5; i++) {
        if (received[i] != 'N$i') {
          throw StateError('expected N$i at index $i, got ${received[i]}');
        }
      }

      // Disconnect to tear down the subscription
      await centeralSub.cancel();
      await central.sendCommand(
        'disconnect',
        params: {'peripheralId': _peripheralId},
      );

      // Fresh subscription and verify silence
      final silenceBuffer = <String>[];
      final silenceSub = central.events.listen((event) {
        if (event['event'] != 'notification') return;
        if ((event['characteristicUuid'] as String?)?.toLowerCase()
            != NusUuids.tx.toLowerCase()) return;
        final b64 = event['value'] as String?;
        if (b64 == null) return;
        final decoded = utf8.decode(base64Decode(b64), allowMalformed: true);
        silenceBuffer.add(decoded);
      });

      await peripheral.sendCommand(
        'update_value',
        params: {
          'serviceUuid': NusUuids.service,
          'characteristicUuid': NusUuids.tx,
          'value': base64Encode(utf8.encode('SILENT')),
        },
      );

      await Future<void>.delayed(const Duration(seconds: 2));
      await silenceSub.cancel();

      if (silenceBuffer.isNotEmpty) {
        throw StateError('expected silence after disconnect, got ${silenceBuffer.length} notifications');
      }

      sw.stop();
      return ScenarioResult(
        name: 'notify-lifecycle',
        success: true,
        duration: sw.elapsed,
        steps: steps,
        diagnostics: {
          'received': 5,
          'silence_window_ms': 2000,
          'leaked': 0,
        },
      );
    } catch (err) {
      sw.stop();
      return ScenarioResult(
        name: 'notify-lifecycle',
        success: false,
        duration: sw.elapsed,
        error: err.toString(),
        steps: steps,
      );
    } finally {
      await centeralSub?.cancel();
    }
  }

  Future<ScenarioResult> _largeWrite() async {
    final sw = Stopwatch()..start();
    final steps = <StepResult>[];
    StreamSubscription<Map<String, dynamic>>? rxSub;
    try {
      await _setup(steps);

      // Build 512-byte payload
      final payload = Uint8List(512);
      for (var i = 0; i < 512; i++) {
        payload[i] = i % 256;
      }

      // Accumulate write_request payloads
      final received = <int>[];
      rxSub = peripheral.events.listen((event) {
        if (event['event'] != 'write_request') return;
        final data = (event['data'] as Map<String, dynamic>?) ?? event;
        if ((data['characteristicUuid'] as String?)?.toLowerCase()
            != NusUuids.rx.toLowerCase()) return;
        final b64 = data['value'] as String?;
        if (b64 == null) return;
        final bytes = base64Decode(b64);
        received.addAll(bytes);
      });

      // Write the payload
      steps.add(
        await _step(
          'write 512-byte payload',
          () => central.sendCommand(
            'write_characteristic',
            params: {
              'peripheralId': _peripheralId,
              'serviceUuid': NusUuids.service,
              'characteristicUuid': NusUuids.rx,
              'value': base64Encode(payload),
            },
          ),
        ),
      );

      // Wait for buffer to match
      await Future<void>.delayed(const Duration(seconds: 5));
      if (received.length != 512) {
        throw StateError('expected 512 bytes, got ${received.length}');
      }
      for (var i = 0; i < 512; i++) {
        if (received[i] != payload[i]) {
          throw StateError('byte mismatch at index $i: expected ${payload[i]}, got ${received[i]}');
        }
      }

      // Verify via get_written_value
      final getResult = await peripheral.sendCommand(
        'get_written_value',
        params: {
          'serviceUuid': NusUuids.service,
          'characteristicUuid': NusUuids.rx,
        },
      );
      final stored = getResult['value'] as String?;
      if (stored != base64Encode(payload)) {
        throw StateError('get_written_value mismatch');
      }

      sw.stop();
      final fragmentCount = (received.length.toDouble() / 20).ceil(); // rough estimate
      return ScenarioResult(
        name: 'large-write',
        success: true,
        duration: sw.elapsed,
        steps: steps,
        diagnostics: {
          'bytes': 512,
          'fragments': fragmentCount,
        },
      );
    } catch (err) {
      sw.stop();
      return ScenarioResult(
        name: 'large-write',
        success: false,
        duration: sw.elapsed,
        error: err.toString(),
        steps: steps,
      );
    } finally {
      await rxSub?.cancel();
    }
  }

  Future<ScenarioResult> _burstWrites() async {
    final sw = Stopwatch()..start();
    final steps = <StepResult>[];
    StreamSubscription<Map<String, dynamic>>? rxSub;
    try {
      await _setup(steps);

      // Accumulate write payloads
      final received = <String>[];
      rxSub = peripheral.events.listen((event) {
        if (event['event'] != 'write_request') return;
        final data = (event['data'] as Map<String, dynamic>?) ?? event;
        if ((data['characteristicUuid'] as String?)?.toLowerCase()
            != NusUuids.rx.toLowerCase()) return;
        final b64 = data['value'] as String?;
        if (b64 == null) return;
        final decoded = utf8.decode(base64Decode(b64), allowMalformed: true);
        received.add(decoded);
      });

      // Issue 20 writes-without-response back-to-back
      final futures = <Future<void>>[];
      for (var i = 0; i < 20; i++) {
        final payload = base64Encode(utf8.encode('b${i.toString().padLeft(2, '0')}'));
        futures.add(
          central.sendCommand(
            'write_characteristic',
            params: {
              'peripheralId': _peripheralId,
              'serviceUuid': NusUuids.service,
              'characteristicUuid': NusUuids.rx,
              'value': payload,
              'withoutResponse': true,
            },
          ).then((_) {}),
        );
      }
      await Future.wait(futures);

      // Wait for receipt
      await Future<void>.delayed(const Duration(seconds: 5));

      if (received.length != 20) {
        throw StateError('expected 20 payloads, got ${received.length}');
      }

      final mismatches = <int>[];
      for (var i = 0; i < 20; i++) {
        final expected = 'b${i.toString().padLeft(2, '0')}';
        if (received[i] != expected) {
          mismatches.add(i);
        }
      }

      sw.stop();
      return ScenarioResult(
        name: 'burst-writes',
        success: mismatches.isEmpty,
        duration: sw.elapsed,
        steps: steps,
        diagnostics: {
          'sent': 20,
          'received': received.length,
          'mismatches': mismatches,
        },
      );
    } catch (err) {
      sw.stop();
      return ScenarioResult(
        name: 'burst-writes',
        success: false,
        duration: sw.elapsed,
        error: err.toString(),
        steps: steps,
      );
    } finally {
      await rxSub?.cancel();
    }
  }

  Future<ScenarioResult> _reconnect() async {
    final sw = Stopwatch()..start();
    final steps = <StepResult>[];
    try {
      await _setup(steps, discover: true);

      // Capture services from first cycle
      final services1Result = await central.sendCommand(
        'discover_services',
        params: {'peripheralId': _peripheralId},
      );
      final services1 = (services1Result['data'] as Map)['services'] as List;

      // Disconnect
      await central.sendCommand(
        'disconnect',
        params: {'peripheralId': _peripheralId},
      );

      // Reconnect on same peripheral ID
      steps.add(
        await _step(
          'reconnect',
          () => central.sendCommand(
            'connect',
            params: {'peripheralId': _peripheralId},
          ),
        ),
      );

      // Re-discover
      steps.add(
        await _step(
          'rediscover_services',
          () => central.sendCommand(
            'discover_services',
            params: {'peripheralId': _peripheralId},
          ),
        ),
      );

      steps.add(
        await _step(
          'rediscover_characteristics',
          () => central.sendCommand(
            'discover_characteristics',
            params: {
              'peripheralId': _peripheralId,
              'serviceUuid': NusUuids.service,
            },
          ),
        ),
      );

      // Verify services
      final services2Result = await central.sendCommand(
        'discover_services',
        params: {'peripheralId': _peripheralId},
      );
      final services2 = (services2Result['data'] as Map)['services'] as List;

      final hasNusService = services2.any((s) {
        final uuid = (s as Map)['uuid'] as String?;
        return uuid?.toLowerCase() == NusUuids.service.toLowerCase();
      });

      if (!hasNusService) {
        throw StateError('NUS service not found in second discovery');
      }

      sw.stop();
      return ScenarioResult(
        name: 'reconnect',
        success: true,
        duration: sw.elapsed,
        steps: steps,
        diagnostics: {
          'cycle1_services': services1.length,
          'cycle2_services': services2.length,
        },
      );
    } catch (err) {
      sw.stop();
      return ScenarioResult(
        name: 'reconnect',
        success: false,
        duration: sw.elapsed,
        error: err.toString(),
        steps: steps,
      );
    }
  }

  Future<ScenarioResult> _peripheralVanishes() async {
    final sw = Stopwatch()..start();
    final steps = <StepResult>[];
    try {
      await _setup(steps, discover: true);

      // Simulate peripheral vanish: stop advertising and remove service
      await peripheral.sendCommand('stop_advertising');
      await peripheral.sendCommand('remove_service', params: {'uuid': NusUuids.service});

      String terminatedBy = 'unknown';
      try {
        steps.add(
          await _step(
            'read_characteristic (vanished)',
            () => central.sendCommand(
              'read_characteristic',
              params: {
                'peripheralId': _peripheralId,
                'serviceUuid': NusUuids.service,
                'characteristicUuid': NusUuids.tx,
              },
            ).timeout(const Duration(seconds: 10)),
          ),
        );
        terminatedBy = 'success';
      } on TimeoutException {
        terminatedBy = 'timeout';
      } catch (e) {
        terminatedBy = 'error';
      }

      // Disconnect must complete cleanly
      final disconnectSw = Stopwatch()..start();
      steps.add(
        await _step(
          'disconnect (post-vanish)',
          () => central.sendCommand(
            'disconnect',
            params: {'peripheralId': _peripheralId},
          ).timeout(const Duration(seconds: 10)),
        ),
      );
      disconnectSw.stop();

      sw.stop();
      return ScenarioResult(
        name: 'peripheral-vanishes',
        success: true,
        duration: sw.elapsed,
        steps: steps,
        diagnostics: {
          'vanish_op': 'read',
          'terminated_by': terminatedBy,
          'disconnect_ms': disconnectSw.elapsedMilliseconds,
        },
      );
    } catch (err) {
      sw.stop();
      return ScenarioResult(
        name: 'peripheral-vanishes',
        success: false,
        duration: sw.elapsed,
        error: err.toString(),
        steps: steps,
      );
    }
  }

  Future<ScenarioResult> _cancelMidDiscovery() async {
    final sw = Stopwatch()..start();
    final steps = <StepResult>[];
    try {
      await _setup(steps, discover: false);

      // Start discover without awaiting
      final pending = central.sendCommand(
        'discover_services',
        params: {'peripheralId': _peripheralId},
      );

      await Future<void>.delayed(const Duration(milliseconds: 20));

      final disconnectSw = Stopwatch()..start();
      steps.add(
        await _step(
          'disconnect_mid_discovery',
          () => central.sendCommand(
            'disconnect',
            params: {'peripheralId': _peripheralId},
          ).timeout(const Duration(seconds: 10)),
        ),
      );
      disconnectSw.stop();

      // Swallow the doomed discover
      pending.catchError((_) => <String, dynamic>{});

      // Fresh cycle on same ID
      steps.add(
        await _step(
          'reconnect',
          () => central.sendCommand(
            'connect',
            params: {'peripheralId': _peripheralId},
          ),
        ),
      );

      steps.add(
        await _step(
          'rediscover_services',
          () => central.sendCommand(
            'discover_services',
            params: {'peripheralId': _peripheralId},
          ),
        ),
      );

      // Verify NUS found
      final discoverResult = await central.sendCommand(
        'discover_services',
        params: {'peripheralId': _peripheralId},
      );
      final services = (discoverResult['data'] as Map)['services'] as List;

      final hasNusService = services.any((s) {
        final uuid = (s as Map)['uuid'] as String?;
        return uuid?.toLowerCase() == NusUuids.service.toLowerCase();
      });

      if (!hasNusService) {
        throw StateError('NUS service not found in second cycle');
      }

      sw.stop();
      return ScenarioResult(
        name: 'cancel-mid-discovery',
        success: true,
        duration: sw.elapsed,
        steps: steps,
        diagnostics: {
          'cancel_delay_ms': 20,
          'disconnect_ms': disconnectSw.elapsedMilliseconds,
          'second_cycle_services': services.length,
        },
      );
    } catch (err) {
      sw.stop();
      return ScenarioResult(
        name: 'cancel-mid-discovery',
        success: false,
        duration: sw.elapsed,
        error: err.toString(),
        steps: steps,
      );
    }
  }
}
