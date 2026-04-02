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

  final host = results.option('host')!;
  final peripheralHost = results.option('peripheral-host') ?? host;
  final centralPort = int.parse(results.option('central-port')!);
  final peripheralPort = int.parse(results.option('peripheral-port')!);
  final timeout = Duration(seconds: int.parse(results.option('timeout')!));

  print('=== Butane BLE Coordinator ===');
  print('');
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

    // Run scenario.
    final runner = ScenarioRunner(
      central: central,
      peripheral: peripheral,
    );

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
      print('ALL STEPS PASSED ✓');
      exit(0);
    } else {
      print('');
      print('SOME STEPS FAILED ✗');
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
