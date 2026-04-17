import 'dart:io';

import 'package:args/args.dart';
import 'package:butane_coordinator/butane_coordinator.dart';

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption(
      'central-port',
      help: 'WebSocket port for central harness (overrides mDNS)',
    )
    ..addOption(
      'peripheral-port',
      help: 'WebSocket port for peripheral harness (overrides mDNS)',
    )
    ..addOption(
      'host',
      help: 'Host for central harness (overrides mDNS)',
    )
    ..addOption(
      'peripheral-host',
      help: 'Host for peripheral harness (overrides mDNS; defaults to --host)',
    )
    ..addOption(
      'timeout',
      defaultsTo: '15',
      help: 'Command timeout in seconds',
    )
    ..addOption(
      'runs',
      defaultsTo: '1',
      help: 'Number of consecutive BLE flow runs',
    )
    ..addFlag(
      'discover',
      defaultsTo: true,
      help: 'Use mDNS to discover harness instances',
    )
    ..addOption(
      'discover-timeout',
      help: 'mDNS discovery timeout in seconds (default: no limit)',
    )
    ..addFlag(
      'help',
      abbr: 'h',
      negatable: false,
      help: 'Print usage',
    );

  final results = parser.parse(arguments);

  if (results.flag('help')) {
    print('Usage: coordinator [options]');
    print(parser.usage);
    exit(0);
  }

  final discover = results.flag('discover');
  final timeout = Duration(seconds: int.parse(results.option('timeout')!));
  final runs = int.parse(results.option('runs')!);

  // Parse explicit overrides (null if not provided).
  var host = results.option('host');
  var peripheralHost = results.option('peripheral-host');
  final centralPortArg = results.option('central-port');
  var centralPort = centralPortArg != null ? int.parse(centralPortArg) : null;
  final peripheralPortArg = results.option('peripheral-port');
  var peripheralPort =
      peripheralPortArg != null ? int.parse(peripheralPortArg) : null;

  print('=== Butane BLE Coordinator ===');
  print('');

  if (discover &&
      (host == null ||
          peripheralHost == null ||
          centralPort == null ||
          peripheralPort == null)) {
    final discoverTimeoutArg = results.option('discover-timeout');
    final discoverTimeout = discoverTimeoutArg != null
        ? Duration(seconds: int.parse(discoverTimeoutArg))
        : null;
    final label = discoverTimeout != null
        ? '(timeout ${discoverTimeout.inSeconds}s)'
        : '(no timeout limit)';
    print('Discovering harness endpoints via mDNS $label...');
    try {
      final found = await HarnessDiscovery().discover(
        timeout: discoverTimeout,
        onProgress: (msg) => print('  $msg'),
      );
      host ??= found.central.host;
      centralPort ??= found.central.port;
      peripheralHost ??= found.peripheral.host;
      peripheralPort ??= found.peripheral.port;
    } on DiscoveryTimeoutException catch (e) {
      print('FATAL: $e');
      exit(2);
    }
  }

  // Final defaults for --no-discover or fully-overridden mode.
  final resolvedHost = host ?? 'localhost';
  final resolvedPeripheralHost = peripheralHost ?? resolvedHost;
  final resolvedCentralPort = centralPort ?? 8080;
  final resolvedPeripheralPort = peripheralPort ?? 8081;

  print('Central:    ws://$resolvedHost:$resolvedCentralPort');
  print('Peripheral: ws://$resolvedPeripheralHost:$resolvedPeripheralPort');
  print('Timeout:    ${timeout.inSeconds}s');
  print('');

  // Connect to both harness instances.
  final central = HarnessClient(
    role: 'central',
    host: resolvedHost,
    port: resolvedCentralPort,
    defaultTimeout: timeout,
  );
  final peripheral = HarnessClient(
    role: 'peripheral',
    host: resolvedPeripheralHost,
    port: resolvedPeripheralPort,
    defaultTimeout: timeout,
  );

  try {
    print('Connecting to central harness...');
    await central.connect();
    print('  Connected.');

    print('Connecting to peripheral harness...');
    await peripheral.connect();
    print('  Connected.');
    print('');

    // Listen for error events forwarded from harness apps.
    central.events.listen((event) {
      if (event['event'] == 'error') {
        print('[CENTRAL ERROR] ${event['message']}');
        final trace = event['stackTrace'] as String?;
        if (trace != null && trace.isNotEmpty) {
          // Print first few lines of stack trace.
          final lines = trace.split('\n').take(5).join('\n');
          print(lines);
        }
      }
    });

    peripheral.events.listen((event) {
      if (event['event'] == 'error') {
        print('[PERIPHERAL ERROR] ${event['message']}');
        final trace = event['stackTrace'] as String?;
        if (trace != null && trace.isNotEmpty) {
          final lines = trace.split('\n').take(5).join('\n');
          print(lines);
        }
      }
    });

    // Run scenario.
    final runner = ScenarioRunner(
      central: central,
      peripheral: peripheral,
    );

    var allRunsPassed = true;

    for (var run = 1; run <= runs; run++) {
      if (runs > 1) {
        print('=== Run $run/$runs ===');
        print('');
      }

      print('Running full BLE flow...');
      print('');

      final results = await runner.runFullBleFlow();

      // Print results table.
      print('Step                                     Result    Duration');
      print('-----------------------------------------------------------');

      var allPassed = true;
      for (final result in results) {
        final status = result.success ? 'PASS' : 'FAIL';
        final ms = '${result.duration.inMilliseconds}ms';
        final name = result.name.padRight(40);
        print('$name  $status      $ms');
        if (!result.success && result.error != null) {
          print('  Error: ${result.error}');
        }
        if (!result.success) allPassed = false;
      }

      print('');
      final passed = results.where((r) => r.success).length;
      final total = results.length;
      print('Results: $passed/$total passed');

      if (allPassed) {
        print('');
        print('RUN $run PASSED ✓');
      } else {
        print('');
        print('RUN $run FAILED ✗');
        allRunsPassed = false;
        break; // Stop on first failure.
      }

      if (run < runs) {
        print('');
        print('Waiting 2s before next run...');
        await Future<void>.delayed(const Duration(seconds: 2));
        print('');
      }
    }

    print('');
    if (allRunsPassed) {
      print('ALL $runs RUNS PASSED ✓');
      exit(0);
    } else {
      print('FAILED — not all runs passed ✗');
      exit(1);
    }
  } catch (e) {
    print('FATAL: $e');
    exit(2);
  } finally {
    await central.disconnect();
    await peripheral.disconnect();
  }
}
