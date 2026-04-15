import 'dart:io';

import 'package:args/args.dart';
import 'package:butane_coordinator/butane_coordinator.dart';

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption(
      'central-port',
      defaultsTo: '8080',
      help: 'WebSocket port for central harness',
    )
    ..addOption(
      'peripheral-port',
      defaultsTo: '8081',
      help: 'WebSocket port for peripheral harness',
    )
    ..addOption(
      'host',
      defaultsTo: 'localhost',
      help: 'Host address for central harness (and peripheral if --peripheral-host is not set)',
    )
    ..addOption(
      'peripheral-host',
      help: 'Host address for peripheral harness (defaults to --host)',
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
      negatable: false,
      help: 'Resolve both harness endpoints via mDNS '
          '(overrides --host / --peripheral-host / ports)',
    )
    ..addOption(
      'discover-timeout',
      defaultsTo: '15',
      help: 'mDNS discovery timeout in seconds (with --discover)',
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

  String host;
  String peripheralHost;
  int centralPort;
  int peripheralPort;

  print('=== Butane BLE Coordinator ===');
  print('');

  if (discover) {
    final discoveryTimeout = Duration(
      seconds: int.parse(results.option('discover-timeout')!),
    );
    print('Discovering harness endpoints via mDNS '
        '(timeout ${discoveryTimeout.inSeconds}s)...');
    try {
      final found =
          await HarnessDiscovery().discover(timeout: discoveryTimeout);
      host = found.central.host;
      centralPort = found.central.port;
      peripheralHost = found.peripheral.host;
      peripheralPort = found.peripheral.port;
      print('  central:    ${found.central.host}:${found.central.port}');
      print('  peripheral: '
          '${found.peripheral.host}:${found.peripheral.port}');
    } on DiscoveryTimeoutException catch (e) {
      print('FATAL: $e');
      exit(2);
    }
  } else {
    host = results.option('host')!;
    peripheralHost = results.option('peripheral-host') ?? host;
    centralPort = int.parse(results.option('central-port')!);
    peripheralPort = int.parse(results.option('peripheral-port')!);
  }

  print('Central:    ws://$host:$centralPort');
  print('Peripheral: ws://$peripheralHost:$peripheralPort');
  print('Timeout:    ${timeout.inSeconds}s');
  print('');

  // Connect to both harness instances.
  final central = HarnessClient(
    role: 'central',
    host: host,
    port: centralPort,
    defaultTimeout: timeout,
  );
  final peripheral = HarnessClient(
    role: 'peripheral',
    host: peripheralHost,
    port: peripheralPort,
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
