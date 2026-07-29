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
import 'dart:async';
Future<void> main() => Completer<void>().future;
''';

class _IosProcessFixture {
  _IosProcessFixture(this.source);

  final String source;
  final _processes = <Process>[];
  final _controller = const SystemProcessGroupController();
  Directory? _directory;

  Future<Process> start(
    String executable,
    List<String> arguments, {
    required String workingDirectory,
    required ProcessStartMode mode,
  }) async {
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

  test('probes exploration readiness through a loopback VM service', () async {
    var extensionRegistered = true;
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
            'extensionRPCs': extensionRegistered
                ? <String>['ext.exploration.butane']
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
    extensionRegistered = false;
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

  test(
    'detached nonzero flutter exit fails with output tail and reaps',
    () async {
      final fixture = _IosProcessFixture(nonzeroHelper);
      addTearDown(fixture.dispose);
      final launcher = IosFollowerLauncher(
        deviceId: 'device',
        harnessDirectory: Directory.current.path,
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

  test('phase deadline: provision', () async {
    final provision = Completer<void>();
    final launcher = IosFollowerLauncher(
      deviceId: 'device',
      harnessDirectory: Directory.current.path,
      provisionTimeout: const Duration(milliseconds: 30),
      lifecycleTimeout: const Duration(seconds: 1),
      preLaunchCleanup: (_) => provision.future,
    );

    final stopwatch = Stopwatch()..start();
    await expectLater(
      launcher.launch(const LaunchSpec(app: 'app', target: 'ios')),
      throwsA(
        isA<TimeoutException>().having(
          (error) => '$error',
          'phase',
          contains('provision'),
        ),
      ),
    );
    expect(stopwatch.elapsed, lessThan(const Duration(milliseconds: 250)));
  });

  test('phase deadline: process start', () async {
    final process = Completer<Process>();
    final launcher = IosFollowerLauncher(
      deviceId: 'device',
      harnessDirectory: Directory.current.path,
      launchTimeout: const Duration(milliseconds: 30),
      lifecycleTimeout: const Duration(seconds: 1),
      preLaunchCleanup: (_) async {},
      processStarter: (_, __, {required workingDirectory, required mode}) =>
          process.future,
    );

    final stopwatch = Stopwatch()..start();
    await expectLater(
      launcher.launch(const LaunchSpec(app: 'app', target: 'ios')),
      throwsA(
        isA<TimeoutException>().having(
          (error) => '$error',
          'phase',
          contains('install+launch'),
        ),
      ),
    );
    expect(stopwatch.elapsed, lessThan(const Duration(milliseconds: 250)));
  });

  test('phase deadline: live install+launch', () async {
    final fixture = _IosProcessFixture(_hangingHelper);
    addTearDown(fixture.dispose);
    final launcher = IosFollowerLauncher(
      deviceId: 'device',
      harnessDirectory: Directory.current.path,
      launchTimeout: const Duration(milliseconds: 50),
      lifecycleTimeout: const Duration(seconds: 1),
      preLaunchCleanup: (_) async {},
      processStarter: fixture.start,
    );

    final stopwatch = Stopwatch()..start();
    await expectLater(
      launcher.launch(const LaunchSpec(app: 'app', target: 'ios')),
      throwsA(
        isA<TimeoutException>().having(
          (error) => '$error',
          'phase',
          contains('install+launch'),
        ),
      ),
    );
    expect(stopwatch.elapsed, lessThan(const Duration(milliseconds: 250)));
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
      launchTimeout: const Duration(seconds: 1),
      readyTimeout: const Duration(milliseconds: 30),
      lifecycleTimeout: const Duration(seconds: 1),
      preLaunchCleanup: (_) async {},
      processStarter: fixture.start,
    );

    final stopwatch = Stopwatch()..start();
    await expectLater(
      launcher.launch(const LaunchSpec(app: 'app', target: 'ios')),
      throwsA(
        isA<TimeoutException>().having(
          (error) => '$error',
          'phase',
          contains('readiness'),
        ),
      ),
    );
    expect(stopwatch.elapsed, lessThan(const Duration(milliseconds: 250)));
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
import 'dart:async';
void main() async {
  print(
    "A Dart VM Service on Test Device is available at: "
    "http://127.0.0.1:${server.port}/auth/",
  );
  await Future<void>.delayed(const Duration(milliseconds: 80));
}
''');
    addTearDown(fixture.dispose);
    final launcher = IosFollowerLauncher(
      deviceId: 'device',
      harnessDirectory: Directory.current.path,
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
    final stopwatch = Stopwatch()..start();
    expect(await run, 1);
    expect(stopwatch.elapsed, lessThan(const Duration(milliseconds: 250)));
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
