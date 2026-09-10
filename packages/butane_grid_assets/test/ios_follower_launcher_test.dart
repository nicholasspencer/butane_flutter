import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:butane_grid_assets/butane_grid_assets.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

const nonzeroHelper = r'''
import 'dart:io';
void main() {
  stderr.writeln('version solving failed');
  stderr.writeln('Failed to update packages');
  exitCode = 1;
}
''';

const _hangingHelper = r'''
Future<void> main() => Future<void>.delayed(const Duration(days: 1));
''';

// Liveness tripwire only, never a latency assertion: every fixture below
// compiles a Dart script from source, and under the code-validation lane's
// parallel load a cold compile alone exceeded five seconds (1 in 21 runs).
const _phaseTestCeiling = Duration(seconds: 30);

typedef _StartedIosProcess = ({
  String executable,
  List<String> arguments,
  String workingDirectory,
  ProcessStartMode mode,
});

typedef _RanIosCommand = ({
  String executable,
  List<String> arguments,
  String? workingDirectory,
  Duration? timeout,
});

class _IosProcessFixture {
  _IosProcessFixture(this.source);

  final String source;
  final _processes = <Process>[];
  final starts = <_StartedIosProcess>[];
  final _controller = const SystemProcessGroupController();
  Directory? _directory;

  Future<Process> start(
    String executable,
    List<String> arguments, {
    required String workingDirectory,
    required ProcessStartMode mode,
  }) async {
    starts.add((
      executable: executable,
      arguments: List<String>.of(arguments),
      workingDirectory: workingDirectory,
      mode: mode,
    ));
    final directory = _directory ??= await Directory.systemTemp.createTemp(
      'ios_follower_launcher_test_',
    );
    final script = File('${directory.path}/helper.dart');
    await script.writeAsString(source);
    final process = await Process.start(Platform.resolvedExecutable, <String>[
      script.path,
    ], mode: mode);
    _processes.add(process);
    return process;
  }

  int get processCount => _processes.length;

  Future<void> signalChildExit() async {
    _processes.single.stdin.writeln('exit');
    await _processes.single.stdin.flush();
  }

  Future<bool> get allChildrenExited async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    return _processes.every(
      (process) => !_controller.processAlive(process.pid),
    );
  }

  Future<void> dispose() async {
    for (final process in _processes) {
      if (_controller.processAlive(process.pid)) {
        Process.killPid(process.pid, ProcessSignal.sigkill);
      }
    }
    final deadline = DateTime.now().add(const Duration(seconds: 2));
    while (_processes.any((process) => _controller.processAlive(process.pid)) &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    for (final process in _processes) {
      if (_controller.processAlive(process.pid)) {
        Process.killPid(process.pid, ProcessSignal.sigkill);
      }
    }
    final directory = _directory;
    if (directory != null) await directory.delete(recursive: true);
  }
}

class _FakeProcessGroupController implements ProcessGroupController {
  @override
  int currentGroupId() => -1;

  @override
  bool processAlive(int pid) => true;

  @override
  Future<List<int>> groupMembers(int pgid) async => const <int>[];

  @override
  Future<int?> resolvePgid(int pid) async => pid;

  @override
  bool signalGroup(int pgid, ProcessSignal signal) => true;
}

void main() {
  test('selects flutter forwarded URI over device GRID_VM_URI', () {
    const transcript = '''
GRID_VM_URI=http://192.168.4.36:55720/device-auth/
A Dart VM Service on Nico's iPad mini is available at: http://127.0.0.1:49458/mac-auth/
''';

    expect(
      flutterForwardedVmServiceWsUri(transcript),
      'ws://127.0.0.1:49458/mac-auth/ws',
    );
  });

  test('converts Flutter DevTools debugger URI', () {
    const transcript = '''
The Flutter DevTools debugger and profiler on Test Device is available at: http://127.0.0.1:43210/devtools-auth/
''';

    expect(
      flutterForwardedVmServiceWsUri(transcript),
      'ws://127.0.0.1:43210/devtools-auth/ws',
    );
  });

  test('returns null without a forwarded URI', () {
    const transcript = '''
Launching lib/main.dart on Test Device in profile mode...
GRID_VM_URI=http://192.168.1.5:1234/device-auth/
''';

    expect(flutterForwardedVmServiceWsUri(transcript), isNull);
  });

  test('rejects non-loopback forwarded URI', () {
    const transcript = '''
A Dart VM Service on Test Device is available at: http://192.168.1.5:1234/device-auth/
''';

    expect(flutterForwardedVmServiceWsUri(transcript), isNull);
  });

  test(
    'explicit flutterRun mode preserves the granted-operator fallback',
    () async {
      final fixture = _IosProcessFixture(r'''
Future<void> main() async {
  print(
    'A Dart VM Service on Test Device is available at: '
    'http://127.0.0.1:43210/forwarded-auth/',
  );
  await Future<void>.delayed(const Duration(days: 1));
}
''');
      addTearDown(fixture.dispose);
      var resolverCalls = 0;
      var relayCalls = 0;
      final logs = <String>[];
      final launcher = IosFollowerLauncher(
        deviceId: 'device',
        harnessDirectory: Directory.current.path,
        launchMode: IosFollowerLaunchMode.flutterRun,
        preLaunchCleanup: (_) async {},
        processStarter: fixture.start,
        processes: _FakeProcessGroupController(),
        explorationReadyProbe: (base) async {
          expect(base, Uri.parse('http://127.0.0.1:43210/forwarded-auth/'));
          return true;
        },
        mdnsCandidateResolver: () async {
          resolverCalls++;
          return const <IosMdnsCandidate>[];
        },
        relayStarter: (candidate) async {
          relayCalls++;
          throw StateError('relay must not start for a forwarded endpoint');
        },
        onLog: logs.add,
      );

      final daemon = await launcher.launch(
        const LaunchSpec(app: 'butane_harness', target: 'ios'),
      );

      expect(
        daemon.endpoint.vmServiceUri,
        'ws://127.0.0.1:43210/forwarded-auth/ws',
      );
      expect(resolverCalls, 0);
      expect(relayCalls, 0);
      expect(logs.where((line) => line.contains('relay pid')), isEmpty);
      final start = _flutterFixtureCall(fixture);
      expect(start.executable, 'flutter');
      expect(start.arguments, <String>[
        'run',
        '--profile',
        '-d',
        'device',
        '--dart-define=ROLE=peripheral',
      ]);
      expect(start.workingDirectory, Directory.current.path);
      expect(start.mode, ProcessStartMode.detachedWithStdio);
    },
  );

  test('falls back to mDNS after forwarded preference window', () async {
    final flutterFixture = _IosProcessFixture(_hangingHelper);
    final relayFixture = _IosProcessFixture(_hangingHelper);
    addTearDown(flutterFixture.dispose);
    addTearDown(relayFixture.dispose);
    const candidate = (ip: '192.168.1.5', port: 1234, authCode: 'mdns-auth');
    var resolverCalls = 0;
    var relayCalls = 0;
    IosMdnsCandidate? relayedCandidate;
    Process? relayProcess;
    final logs = <String>[];
    final launcher = IosFollowerLauncher(
      deviceId: 'device',
      harnessDirectory: Directory.current.path,
      launchMode: IosFollowerLaunchMode.flutterRun,
      forwardedPreferenceWindow: const Duration(milliseconds: 1),
      preLaunchCleanup: (_) async {},
      processStarter: flutterFixture.start,
      processes: _FakeProcessGroupController(),
      explorationReadyProbe: (base) async {
        expect(base, Uri.parse('http://192.168.1.5:1234/mdns-auth/'));
        return true;
      },
      mdnsCandidateResolver: () async {
        resolverCalls++;
        return const <IosMdnsCandidate>[candidate];
      },
      relayStarter: (resolved) async {
        relayCalls++;
        relayedCandidate = resolved;
        relayProcess = await relayFixture.start(
          '',
          const <String>[],
          workingDirectory: Directory.current.path,
          mode: ProcessStartMode.detachedWithStdio,
        );
        return relayProcess!;
      },
      onLog: logs.add,
    );

    final stopwatch = Stopwatch()..start();
    final daemon = await launcher.launch(
      const LaunchSpec(app: 'butane_harness', target: 'ios'),
    );
    stopwatch.stop();

    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 1)));
    expect(daemon.endpoint.vmServiceUri, 'ws://127.0.0.1:50999/mdns-auth/ws');
    expect(resolverCalls, 1);
    expect(relayCalls, 1);
    expect(relayedCandidate, candidate);
    expect(relayProcess, isNotNull);
    expect(logs.where((line) => line.contains('relay pid')), hasLength(1));
  });

  test('accepts current and legacy iOS readiness extension prefixes', () async {
    var extensionRpc = 'ext.leonard.butane.wait_for_state';
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final serving = server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      if (request.uri.path.endsWith('/getVM')) {
        request.response.write(
          jsonEncode(<String, Object>{
            'isolates': <Object>[
              <String, String>{'id': 'isolates/42'},
            ],
          }),
        );
      } else if (request.uri.path.endsWith('/getIsolate')) {
        expect(request.uri.queryParameters['isolateId'], 'isolates/42');
        request.response.write(
          jsonEncode(<String, Object>{
            'extensionRPCs': extensionRpc.isNotEmpty
                ? <String>[extensionRpc]
                : <String>[],
          }),
        );
      } else {
        request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });
    addTearDown(() async {
      await server.close(force: true);
      await serving.cancel();
    });
    final base = Uri.parse('http://127.0.0.1:${server.port}/auth/');

    expect(await isIosExplorationReady(base), isTrue);
    extensionRpc = 'ext.exploration.butane';
    expect(await isIosExplorationReady(base), isTrue);
    extensionRpc = 'ext.leonard.core.handshake';
    expect(await isIosExplorationReady(base), isFalse);
  });

  test('resolves every valid iOS mDNS address for every port', () {
    const lookupOutput = '''
com.nicospencer.butaneHarness._dartVmService._tcp.local. can be reached at ipad.local.:55433
 authCode=first
com.nicospencer.butaneHarness._dartVmService._tcp.local. can be reached at ipad.local.:55434
 authCode=second
''';
    const addressOutput = '''
10:11:12.000  Add  2  34 ipad.local.  0.0.0.0         0 No Such Record
10:11:12.001  Add  2  35 ipad.local.  169.254.243.58 120
10:11:12.002  Add  2  23 ipad.local.  192.168.4.36   120
10:11:12.003  Rmv  0  23 ipad.local.  10.0.0.8       120
10:11:12.004  Add  2  23 ipad.local.  10.0.0.9
10:11:12.005  Add  2  23 ipad.local.  999.1.1.1      120
''';

    final candidates = resolveIosMdnsCandidates(
      lookupOutput: lookupOutput,
      addressOutput: addressOutput,
    );

    expect(candidates, hasLength(4));
    expect(
      candidates,
      containsAll(<IosMdnsCandidate>[
        (ip: '169.254.243.58', port: 55433, authCode: 'first'),
        (ip: '192.168.4.36', port: 55433, authCode: 'first'),
        (ip: '169.254.243.58', port: 55434, authCode: 'second'),
        (ip: '192.168.4.36', port: 55434, authCode: 'second'),
      ]),
    );
    expect(
      candidates.map((candidate) => candidate.ip),
      isNot(contains('0.0.0.0')),
    );
    expect(
      candidates.map((candidate) => candidate.ip),
      isNot(contains('10.0.0.8')),
    );
    expect(
      candidates.map((candidate) => candidate.ip),
      isNot(contains('10.0.0.9')),
    );
    expect(
      candidates.map((candidate) => candidate.ip),
      isNot(contains('999.1.1.1')),
    );
  });

  test('devicectl is the default and issues build install and launch without '
      'flutter run', () async {
    final harness = await Directory.systemTemp.createTemp(
      'ios_follower_devicectl_commands_',
    );
    addTearDown(() => harness.delete(recursive: true));
    final runnerApp = Directory(
      '${harness.path}/build/ios/iphoneos/Runner.app',
    );
    await runnerApp.create(recursive: true);

    final launchFixture = _IosProcessFixture(r'''
Future<void> main() async {
  print(
    'The Dart VM service is listening on '
    'http://0.0.0.0:55434/current-auth/',
  );
  await Future<void>.delayed(const Duration(days: 1));
}
''');
    final relayFixture = _IosProcessFixture(_hangingHelper);
    addTearDown(launchFixture.dispose);
    addTearDown(relayFixture.dispose);
    final commands = <_RanIosCommand>[];

    final launcher = IosFollowerLauncher(
      deviceId: '00008110-device',
      harnessDirectory: harness.path,
      preLaunchCleanup: (_) async {},
      processes: _FakeProcessGroupController(),
      commandRunner:
          (executable, arguments, {workingDirectory, timeout}) async {
            commands.add((
              executable: executable,
              arguments: List<String>.of(arguments),
              workingDirectory: workingDirectory,
              timeout: timeout,
            ));
            return ProcessResult(0, 0, '', '');
          },
      processStarter: launchFixture.start,
      mdnsCandidateResolver: () async => const <IosMdnsCandidate>[
        (ip: '192.168.4.36', port: 55434, authCode: 'cached-auth'),
      ],
      explorationReadyProbe: (_) async => true,
      relayStarter: (candidate) => relayFixture.start(
        'python3',
        const <String>[],
        workingDirectory: harness.path,
        mode: ProcessStartMode.detachedWithStdio,
      ),
    );

    final daemon = await launcher.launch(
      const LaunchSpec(app: 'butane_harness', target: 'ios'),
    );

    expect(launcher.launchMode, IosFollowerLaunchMode.devicectl);
    expect(commands, hasLength(2));
    expect(commands[0].executable, 'flutter');
    expect(commands[0].arguments, <String>[
      'build',
      'ios',
      '--profile',
      '--dart-define=ROLE=peripheral',
    ]);
    expect(commands[0].workingDirectory, harness.path);
    expect(commands[0].timeout, const Duration(minutes: 10));
    expect(commands[1].executable, 'xcrun');
    expect(commands[1].arguments, <String>[
      'devicectl',
      'device',
      'install',
      'app',
      '--device',
      '00008110-device',
      runnerApp.absolute.path,
    ]);
    expect(commands[1].workingDirectory, isNull);
    expect(commands[1].timeout, const Duration(minutes: 10));
    final start = launchFixture.starts.single;
    expect(start.executable, 'xcrun');
    expect(start.arguments, <String>[
      'devicectl',
      'device',
      'process',
      'launch',
      '--console',
      '--terminate-existing',
      '--device',
      '00008110-device',
      'com.nicospencer.butaneHarness',
      '--vm-service-host=0.0.0.0',
      '--enable-dart-profiling',
    ]);
    expect(start.workingDirectory, harness.path);
    expect(start.mode, ProcessStartMode.detachedWithStdio);
    final allArguments = <String>[
      for (final command in commands) ...command.arguments,
      ...launchFixture.starts.single.arguments,
    ];
    expect(allArguments, isNot(contains('--start-stopped')));
    expect(allArguments, isNot(contains('--environment-variables')));
    expect(
      commands.where(
        (command) =>
            command.executable == 'flutter' &&
            command.arguments.isNotEmpty &&
            command.arguments.first == 'run',
      ),
      isEmpty,
    );
    expect(daemon.endpoint.vmServiceUri, 'ws://127.0.0.1:50999/cached-auth/ws');
  });

  test(
    'devicectl console and dns-sd transcripts resolve the current VM service',
    () async {
      final harness = await Directory.systemTemp.createTemp(
        'ios_follower_devicectl_transcript_',
      );
      addTearDown(() => harness.delete(recursive: true));
      await Directory(
        '${harness.path}/build/ios/iphoneos/Runner.app',
      ).create(recursive: true);
      final launchFixture = _IosProcessFixture(r'''
Future<void> main() async {
  print('devicectl: established connection');
  print(
    'The Dart VM service is listening on '
    'http://0.0.0.0:55434/current-auth/',
  );
  await Future<void>.delayed(const Duration(days: 1));
}
''');
      final relayFixture = _IosProcessFixture(_hangingHelper);
      addTearDown(launchFixture.dispose);
      addTearDown(relayFixture.dispose);
      const lookupOutput = '''
com.nicospencer.butaneHarness._dartVmService._tcp.local. can be reached at ipad.local.:55433
 authCode=stale-auth
com.nicospencer.butaneHarness._dartVmService._tcp.local. can be reached at ipad.local.:55434
 authCode=advertised-auth
''';
      const addressOutput = '''
10:11:12.000  Add  2  34 ipad.local.  0.0.0.0         0 No Such Record
10:11:12.001  Add  2  35 ipad.local.  169.254.243.58 120
10:11:12.002  Rmv  0  23 ipad.local.  192.168.4.36   120
''';
      final candidates = resolveIosMdnsCandidates(
        lookupOutput: lookupOutput,
        addressOutput: addressOutput,
      );
      final probed = <Uri>[];
      IosMdnsCandidate? relayed;
      final consoleLineLogged = Completer<void>();
      final launcher = IosFollowerLauncher(
        deviceId: 'device',
        harnessDirectory: harness.path,
        preLaunchCleanup: (_) async {},
        processes: _FakeProcessGroupController(),
        commandRunner: (_, __, {workingDirectory, timeout}) async =>
            ProcessResult(0, 0, '', ''),
        processStarter: launchFixture.start,
        mdnsCandidateResolver: () async {
          await consoleLineLogged.future.timeout(_phaseTestCeiling);
          return candidates;
        },
        explorationReadyProbe: (base) async {
          probed.add(base);
          return true;
        },
        relayStarter: (candidate) async {
          relayed = candidate;
          return relayFixture.start(
            'python3',
            const <String>[],
            workingDirectory: harness.path,
            mode: ProcessStartMode.detachedWithStdio,
          );
        },
        onLog: (line) {
          if (line.contains('The Dart VM service is listening on') &&
              !consoleLineLogged.isCompleted) {
            consoleLineLogged.complete();
          }
        },
      );

      final daemon = await launcher.launch(
        const LaunchSpec(app: 'butane_harness', target: 'ios'),
      );

      expect(probed, <Uri>[
        Uri.parse('http://169.254.243.58:55434/current-auth/'),
      ]);
      expect(relayed, (
        ip: '169.254.243.58',
        port: 55434,
        authCode: 'current-auth',
      ));
      expect(
        daemon.endpoint.vmServiceUri,
        'ws://127.0.0.1:50999/current-auth/ws',
      );
    },
  );

  test(
    'devicectl resolves dns-sd transcript without a console VM banner',
    () async {
      final harness = await Directory.systemTemp.createTemp(
        'ios_follower_devicectl_mdns_only_',
      );
      addTearDown(() => harness.delete(recursive: true));
      await Directory(
        '${harness.path}/build/ios/iphoneos/Runner.app',
      ).create(recursive: true);
      final launchFixture = _IosProcessFixture(_hangingHelper);
      final relayFixture = _IosProcessFixture(_hangingHelper);
      addTearDown(launchFixture.dispose);
      addTearDown(relayFixture.dispose);
      final candidates = resolveIosMdnsCandidates(
        lookupOutput: '''
com.nicospencer.butaneHarness._dartVmService._tcp.local. can be reached at ipad.local.:55683
 authCode=mdns-only-auth
''',
        addressOutput: '''
10:11:12.000  Add  2  34 ipad.local.  0.0.0.0         0 No Such Record
10:11:12.001  Add  2  35 ipad.local.  169.254.219.128 120
''',
      );
      final probed = <Uri>[];
      IosMdnsCandidate? relayed;
      final launcher = IosFollowerLauncher(
        deviceId: 'device',
        harnessDirectory: harness.path,
        preLaunchCleanup: (_) async {},
        processes: _FakeProcessGroupController(),
        commandRunner: (_, __, {workingDirectory, timeout}) async =>
            ProcessResult(0, 0, '', ''),
        processStarter: launchFixture.start,
        mdnsCandidateResolver: () async => candidates,
        explorationReadyProbe: (base) async {
          probed.add(base);
          return true;
        },
        relayStarter: (candidate) async {
          relayed = candidate;
          return relayFixture.start(
            'python3',
            const <String>[],
            workingDirectory: harness.path,
            mode: ProcessStartMode.detachedWithStdio,
          );
        },
      );

      final daemon = await launcher.launch(
        const LaunchSpec(app: 'butane_harness', target: 'ios'),
      );

      expect(probed, <Uri>[
        Uri.parse('http://169.254.219.128:55683/mdns-only-auth/'),
      ]);
      expect(relayed, (
        ip: '169.254.219.128',
        port: 55683,
        authCode: 'mdns-only-auth',
      ));
      expect(
        daemon.endpoint.vmServiceUri,
        'ws://127.0.0.1:50999/mdns-only-auth/ws',
      );
    },
  );

  test(
    'detached nonzero flutter exit fails with output tail and reaps',
    () async {
      final fixture = _IosProcessFixture(nonzeroHelper);
      addTearDown(fixture.dispose);
      final launcher = IosFollowerLauncher(
        deviceId: 'device',
        harnessDirectory: Directory.current.path,
        launchMode: IosFollowerLaunchMode.flutterRun,
        processStarter: fixture.start,
        preLaunchCleanup: (_) async {},
        processes: _FakeProcessGroupController(),
      );

      final stopwatch = Stopwatch()..start();
      await expectLater(
        launcher.launch(const LaunchSpec(app: 'butane_harness', target: 'ios')),
        throwsA(
          isA<StateError>()
              .having(
                (error) => '$error',
                'exit',
                contains('flutter exited before readiness'),
              )
              .having(
                (error) => '$error',
                'pub tail',
                contains('version solving failed'),
              )
              .having(
                (error) => '$error',
                'failure tail',
                contains('Failed to update packages'),
              ),
        ),
      );
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 1)));
      expect(await fixture.allChildrenExited, isTrue);
    },
  );

  group('devicectl failures are loud and reaped', () {
    test('nonzero build includes captured command output', () async {
      final fixture = _IosProcessFixture(_hangingHelper);
      addTearDown(fixture.dispose);
      final launcher = IosFollowerLauncher(
        deviceId: 'device',
        harnessDirectory: Directory.current.path,
        preLaunchCleanup: (_) async {},
        processStarter: fixture.start,
        commandRunner: (_, __, {workingDirectory, timeout}) async =>
            ProcessResult(
              101,
              1,
              'build stdout receipt',
              'build stderr receipt',
            ),
      );

      await expectLater(
        launcher.launch(const LaunchSpec(app: 'butane_harness', target: 'ios')),
        throwsA(
          isA<StateError>()
              .having(
                (error) => '$error',
                'build command',
                contains('flutter build ios --profile'),
              )
              .having(
                (error) => '$error',
                'stdout',
                contains('build stdout receipt'),
              )
              .having(
                (error) => '$error',
                'stderr',
                contains('build stderr receipt'),
              ),
        ),
      );
      expect(fixture.processCount, 0);
    });

    test('nonzero install includes captured command output', () async {
      final harness = await Directory.systemTemp.createTemp(
        'ios_follower_install_failure_',
      );
      addTearDown(() => harness.delete(recursive: true));
      await Directory(
        '${harness.path}/build/ios/iphoneos/Runner.app',
      ).create(recursive: true);
      final fixture = _IosProcessFixture(_hangingHelper);
      addTearDown(fixture.dispose);
      var invocation = 0;
      final launcher = IosFollowerLauncher(
        deviceId: 'device',
        harnessDirectory: harness.path,
        preLaunchCleanup: (_) async {},
        processStarter: fixture.start,
        commandRunner: (_, __, {workingDirectory, timeout}) async =>
            ++invocation == 1
            ? ProcessResult(102, 0, '', '')
            : ProcessResult(
                103,
                72,
                'install stdout receipt',
                'install stderr receipt',
              ),
      );

      await expectLater(
        launcher.launch(const LaunchSpec(app: 'butane_harness', target: 'ios')),
        throwsA(
          isA<StateError>()
              .having(
                (error) => '$error',
                'install command',
                contains('devicectl device install app'),
              )
              .having(
                (error) => '$error',
                'stdout',
                contains('install stdout receipt'),
              )
              .having(
                (error) => '$error',
                'stderr',
                contains('install stderr receipt'),
              ),
        ),
      );
      expect(fixture.processCount, 0);
    });

    test(
      'console exit reports its output tail and leaves no process',
      () async {
        final harness = await Directory.systemTemp.createTemp(
          'ios_follower_console_failure_',
        );
        addTearDown(() => harness.delete(recursive: true));
        await Directory(
          '${harness.path}/build/ios/iphoneos/Runner.app',
        ).create(recursive: true);
        final fixture = _IosProcessFixture(r'''
import 'dart:io';
void main() {
  stdout.writeln('console stdout receipt');
  stderr.writeln('console stderr receipt');
  exitCode = 1;
}
''');
        addTearDown(fixture.dispose);
        final launcher = IosFollowerLauncher(
          deviceId: 'device',
          harnessDirectory: harness.path,
          preLaunchCleanup: (_) async {},
          processes: _FakeProcessGroupController(),
          processStarter: fixture.start,
          commandRunner: (_, __, {workingDirectory, timeout}) async =>
              ProcessResult(104, 0, '', ''),
          mdnsCandidateResolver: () async => const <IosMdnsCandidate>[],
        );

        await expectLater(
          launcher.launch(
            const LaunchSpec(app: 'butane_harness', target: 'ios'),
          ),
          throwsA(
            isA<StateError>()
                .having(
                  (error) => '$error',
                  'exit',
                  contains('devicectl exited before readiness'),
                )
                .having(
                  (error) => '$error',
                  'stdout tail',
                  contains('console stdout receipt'),
                )
                .having(
                  (error) => '$error',
                  'stderr tail',
                  contains('console stderr receipt'),
                ),
          ),
        );
        expect(await fixture.allChildrenExited, isTrue);
      },
    );
  });

  test('phase deadline: provision', () async {
    final provision = Completer<void>();
    final launcher = IosFollowerLauncher(
      deviceId: 'device',
      harnessDirectory: Directory.current.path,
      launchMode: IosFollowerLaunchMode.flutterRun,
      provisionTimeout: const Duration(milliseconds: 30),
      lifecycleTimeout: const Duration(seconds: 1),
      preLaunchCleanup: (_) => provision.future,
    );

    await expectLater(
      launcher
          .launch(const LaunchSpec(app: 'app', target: 'ios'))
          .timeout(_phaseTestCeiling),
      throwsA(
        isA<TimeoutException>().having(
          (error) => '$error',
          'phase',
          contains('provision'),
        ),
      ),
    );
  });

  test('phase deadline: process start', () async {
    final process = Completer<Process>();
    final launcher = IosFollowerLauncher(
      deviceId: 'device',
      harnessDirectory: Directory.current.path,
      launchMode: IosFollowerLaunchMode.flutterRun,
      launchTimeout: const Duration(milliseconds: 30),
      lifecycleTimeout: const Duration(seconds: 1),
      preLaunchCleanup: (_) async {},
      processStarter: (_, __, {required workingDirectory, required mode}) =>
          process.future,
    );

    await expectLater(
      launcher
          .launch(const LaunchSpec(app: 'app', target: 'ios'))
          .timeout(_phaseTestCeiling),
      throwsA(
        isA<TimeoutException>().having(
          (error) => '$error',
          'phase',
          contains('install+launch'),
        ),
      ),
    );
  });

  test('phase deadline: live install+launch', () async {
    final fixture = _IosProcessFixture(_hangingHelper);
    addTearDown(fixture.dispose);
    final launcher = IosFollowerLauncher(
      deviceId: 'device',
      harnessDirectory: Directory.current.path,
      launchMode: IosFollowerLaunchMode.flutterRun,
      launchTimeout: const Duration(milliseconds: 50),
      lifecycleTimeout: const Duration(seconds: 1),
      preLaunchCleanup: (_) async {},
      processStarter: fixture.start,
    );

    await expectLater(
      launcher
          .launch(const LaunchSpec(app: 'app', target: 'ios'))
          .timeout(_phaseTestCeiling),
      throwsA(
        isA<TimeoutException>().having(
          (error) => '$error',
          'phase',
          contains('install+launch'),
        ),
      ),
    );
    expect(await fixture.allChildrenExited, isTrue);
  });

  test('phase deadline: readiness probe', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final serving = server.listen((request) {});
    addTearDown(() async {
      await server.close(force: true);
      await serving.cancel();
    });
    final fixture = _IosProcessFixture('''
import 'dart:async';
void main() async {
  print(
    "A Dart VM Service on Test Device is available at: "
    "http://127.0.0.1:${server.port}/auth/",
  );
  await Future<void>.delayed(const Duration(days: 1));
}
''');
    addTearDown(fixture.dispose);
    final launcher = IosFollowerLauncher(
      deviceId: 'device',
      harnessDirectory: Directory.current.path,
      launchMode: IosFollowerLaunchMode.flutterRun,
      launchTimeout: const Duration(seconds: 1),
      readyTimeout: const Duration(milliseconds: 30),
      lifecycleTimeout: const Duration(seconds: 1),
      preLaunchCleanup: (_) async {},
      processStarter: fixture.start,
    );

    await expectLater(
      launcher
          .launch(const LaunchSpec(app: 'app', target: 'ios'))
          .timeout(_phaseTestCeiling),
      throwsA(
        isA<TimeoutException>().having(
          (error) => '$error',
          'phase',
          contains('readiness'),
        ),
      ),
    );
    expect(await fixture.allChildrenExited, isTrue);
  });

  test('detached child death ends resident hold promptly and reaps', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final serving = server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      if (request.uri.path.endsWith('/getVM')) {
        request.response.write(
          jsonEncode(<String, Object>{
            'isolates': <Object>[
              <String, String>{'id': 'isolates/42'},
            ],
          }),
        );
      } else if (request.uri.path.endsWith('/getIsolate')) {
        request.response.write(
          jsonEncode(<String, Object>{
            'extensionRPCs': <String>['ext.exploration.butane'],
          }),
        );
      }
      await request.response.close();
    });
    addTearDown(() async {
      await server.close(force: true);
      await serving.cancel();
    });
    final fixture = _IosProcessFixture('''
import 'dart:io';
void main() async {
  print(
    "A Dart VM Service on Test Device is available at: "
    "http://127.0.0.1:${server.port}/auth/",
  );
  await stdin.first;
}
''');
    addTearDown(fixture.dispose);
    final launcher = IosFollowerLauncher(
      deviceId: 'device',
      harnessDirectory: Directory.current.path,
      launchMode: IosFollowerLaunchMode.flutterRun,
      processStarter: fixture.start,
      preLaunchCleanup: (_) async {},
      processes: const SystemProcessGroupController(),
      launchTimeout: const Duration(seconds: 1),
      readyTimeout: const Duration(seconds: 1),
      lifecycleTimeout: const Duration(seconds: 2),
    );
    final runner = ButaneFollowerRunner(
      launcher: launcher,
      processes: const SystemProcessGroupController(),
      reapGrace: Duration.zero,
    );
    final logs = <String>[];
    final published = Completer<void>();
    final terminate = StreamController<void>();
    addTearDown(terminate.close);

    final run = runBurnFollowerDaemon(
      inputs: BurnFollowerDaemonInputs(
        target: 'ios',
        device: 'device',
        harnessDirectory: Directory.current.path,
        leonardDrive: '/drive',
      ),
      runner: runner,
      terminate: terminate.stream,
      publish: (_) => published.complete(),
      onLog: logs.add,
    );

    await published.future;
    await fixture.signalChildExit();
    expect(await run.timeout(_phaseTestCeiling), 1);
    expect(
      logs,
      contains(contains('burn follower child exited while resident')),
    );
    expect(
      logs.where((line) => line.startsWith('teardown-receipt:')),
      hasLength(1),
    );
    expect(await fixture.allChildrenExited, isTrue);
    expect(runner.isRunning, isFalse);

    final second = runner.launch(
      const LaunchSpec(app: 'butane_harness', target: 'ios'),
    );
    await expectLater(second, completes);
    await runner.teardown();
  });
}

_StartedIosProcess _flutterFixtureCall(_IosProcessFixture fixture) {
  expect(fixture.starts, hasLength(1));
  return fixture.starts.single;
}
