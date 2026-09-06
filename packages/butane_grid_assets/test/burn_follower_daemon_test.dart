import 'dart:async';
import 'dart:io';

import 'package:butane_grid_assets/butane_grid_assets.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

const _endpoint = FollowerEndpoint(
  vmServiceUri: 'ws://127.0.0.1:5599/Test=/ws',
  station: 'resident-test',
  leaseId: 'local',
);

class _FakeFollowerLauncher implements FollowerLauncher {
  _FakeFollowerLauncher({
    this.error,
    List<Future<LaunchedDaemon> Function()>? launches,
  }) : launches = launches ?? <Future<LaunchedDaemon> Function()>[];

  final Object? error;
  final List<Future<LaunchedDaemon> Function()> launches;
  var launchCalls = 0;
  LaunchSpec? spec;

  @override
  Future<LaunchedDaemon> launch(LaunchSpec spec) async {
    launchCalls++;
    this.spec = spec;
    if (error case final error?) throw error;
    if (launches.isNotEmpty) return launches.removeAt(0)();
    return const LaunchedDaemon(pid: 4242, pgid: 4242, endpoint: _endpoint);
  }
}

class _FakeProcessGroupController implements ProcessGroupController {
  final signals = <ProcessSignal>[];
  var alive = true;

  @override
  int currentGroupId() => 999999;

  @override
  bool processAlive(int pid) => alive;

  @override
  Future<List<int>> groupMembers(int pgid) async => const <int>[];

  @override
  Future<int?> resolvePgid(int pid) async => pid;

  @override
  bool signalGroup(int pgid, ProcessSignal signal) {
    signals.add(signal);
    if (signal == ProcessSignal.sigterm) alive = false;
    return true;
  }
}

const _inputs = BurnFollowerDaemonInputs(
  target: 'ios',
  device: 'device-1',
  harnessDirectory: '/harness',
  leonardDrive: '/drive',
);

void main() {
  test('parses required supervisor arguments', () {
    expect(
      BurnFollowerDaemonInputs.parse([
        '--target',
        ' ios ',
        '--device',
        ' device-1 ',
        '--harness-dir',
        ' /harness ',
        '--leonard-drive',
        ' /drive ',
      ]),
      isA<BurnFollowerDaemonInputs>()
          .having((inputs) => inputs.target, 'target', 'ios')
          .having((inputs) => inputs.device, 'device', 'device-1'),
    );
  });

  test('publishes once, holds until termination, and reaps once', () async {
    final launcher = _FakeFollowerLauncher();
    final processes = _FakeProcessGroupController();
    final runner = ButaneFollowerRunner(
      launcher: launcher,
      processes: processes,
      reapGrace: Duration.zero,
    );
    final terminate = StreamController<void>.broadcast();
    final published = <String>[];
    var completed = false;

    final run = runBurnFollowerDaemon(
      inputs: _inputs,
      runner: runner,
      terminate: terminate.stream,
      publish: published.add,
    ).whenComplete(() => completed = true);

    while (published.isEmpty) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(published, ['burn-follower-published ${_endpoint.vmServiceUri}']);
    expect(completed, isFalse);
    expect(launcher.spec!.followerDevice, 'device-1');
    expect(launcher.spec!.harnessDirectory, '/harness');
    expect(launcher.spec!.leonardDrive, '/drive');
    expect(launcher.spec!.target, 'ios');
    expect(launcher.spec!.role, 'peripheral');

    terminate.add(null);
    expect(await run, 0);
    await runner.teardown();
    expect(
      processes.signals.where((signal) => signal == ProcessSignal.sigterm),
      hasLength(1),
    );
    await terminate.close();
  });

  test('threads macos target and peripheral role through launch', () async {
    final launcher = _FakeFollowerLauncher();
    final runner = ButaneFollowerRunner(
      launcher: launcher,
      processes: _FakeProcessGroupController(),
      reapGrace: Duration.zero,
    );

    expect(
      await runBurnFollowerDaemon(
        inputs: const BurnFollowerDaemonInputs(
          target: 'macos',
          device: 'unused',
          harnessDirectory: '/harness',
          leonardDrive: '/drive',
        ),
        runner: runner,
        terminate: Stream<void>.value(null),
        publish: (_) {},
      ),
      0,
    );
    expect(launcher.spec!.target, 'macos');
    expect(launcher.spec!.role, 'peripheral');
  });

  test('launch failure returns nonzero without publishing', () async {
    final launcher = _FakeFollowerLauncher(error: StateError('launch failed'));
    final processes = _FakeProcessGroupController();
    final runner = ButaneFollowerRunner(
      launcher: launcher,
      processes: processes,
      reapGrace: Duration.zero,
    );
    final published = <String>[];
    final logs = <String>[];

    final result = await runBurnFollowerDaemon(
      inputs: _inputs,
      runner: runner,
      terminate: const Stream<void>.empty(),
      publish: published.add,
      onLog: logs.add,
    );

    expect(result, 1);
    expect(published, isEmpty);
    expect(
      logs.first,
      allOf(
        startsWith('burn follower supervisor failed:'),
        contains('launch failed'),
      ),
    );
    expect(logs.last, 'teardown-receipt: burn follower daemon reaped');
    await runner.teardown();
    expect(processes.signals, isEmpty);
  });

  test(
    'termination during launch exits promptly and emits teardown receipt',
    () async {
      final pendingLaunch = Completer<LaunchedDaemon>();
      final launcher = _FakeFollowerLauncher(
        launches: [() => pendingLaunch.future],
      );
      final processes = _FakeProcessGroupController();
      final runner = ButaneFollowerRunner(
        launcher: launcher,
        processes: processes,
        reapGrace: Duration.zero,
      );
      final terminate = StreamController<void>();
      final published = <String>[];
      final logs = <String>[];
      Timer? launchDeadline;

      final run = runZoned(
        () => runBurnFollowerDaemon(
          inputs: _inputs,
          runner: runner,
          terminate: terminate.stream,
          publish: published.add,
          onLog: logs.add,
        ),
        zoneSpecification: ZoneSpecification(
          createTimer: (self, parent, zone, duration, callback) {
            final timer = parent.createTimer(zone, duration, callback);
            if (duration == const Duration(minutes: 15)) {
              launchDeadline = timer;
            }
            return timer;
          },
        ),
      );

      while (launcher.launchCalls == 0) {
        await Future<void>.delayed(Duration.zero);
      }
      terminate.add(null);
      expect(await run.timeout(const Duration(milliseconds: 250)), 0);
      expect(launchDeadline, isNotNull);
      expect(launchDeadline!.isActive, isFalse);
      expect(published, isEmpty);
      expect(
        logs.where(
          (line) =>
              line ==
              'termination-receipt: burn follower daemon launch aborted',
        ),
        hasLength(1),
      );
      expect(
        logs.where(
          (line) => line == 'teardown-receipt: burn follower daemon reaped',
        ),
        hasLength(1),
      );
      expect(processes.signals, isNot(contains(ProcessSignal.sigkill)));
      pendingLaunch.complete(
        const LaunchedDaemon(pid: 4242, pgid: 4242, endpoint: _endpoint),
      );
      while (processes.signals.isEmpty) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(runner.isRunning, isFalse);
      expect(
        processes.signals.where((signal) => signal == ProcessSignal.sigterm),
        hasLength(1),
      );
      expect(processes.signals, isNot(contains(ProcessSignal.sigkill)));
      await terminate.close();
    },
  );

  test(
    'launch and teardown deadlines settle, receipt once, and permit runner reuse',
    () async {
      Future<void> exercise(
        Future<LaunchedDaemon> Function() firstLaunch,
      ) async {
        final launcher = _FakeFollowerLauncher(
          launches: <Future<LaunchedDaemon> Function()>[
            firstLaunch,
            () async => const LaunchedDaemon(
              pid: 4242,
              pgid: 4242,
              endpoint: _endpoint,
            ),
          ],
        );
        final processes = _FakeProcessGroupController();
        final runner = ButaneFollowerRunner(
          launcher: launcher,
          processes: processes,
          reapGrace: Duration.zero,
        );
        final logs = <String>[];
        final stopwatch = Stopwatch()..start();

        final run = runBurnFollowerDaemon(
          inputs: _inputs,
          runner: runner,
          terminate: const Stream<void>.empty(),
          publish: (_) {},
          onLog: logs.add,
          launchTimeout: const Duration(milliseconds: 30),
          teardownTimeout: const Duration(milliseconds: 30),
        );

        expect(await run, 1);
        expect(stopwatch.elapsed, lessThan(const Duration(milliseconds: 250)));
        expect(
          logs.where((line) => line.startsWith('teardown-receipt:')),
          hasLength(1),
        );
        expect(runner.isRunning, isFalse);

        final endpoint = await runner.launch(
          const LaunchSpec(app: 'butane_harness', target: 'ios'),
        );
        expect(endpoint, _endpoint);
        await runner.teardown();
      }

      await exercise(() => Completer<LaunchedDaemon>().future);
      await exercise(
        () async => LaunchedDaemon(
          pid: 4242,
          pgid: 4242,
          endpoint: _endpoint,
          exited: Future<void>.value(),
          onReap: () => Completer<void>().future,
        ),
      );
    },
  );

  test('resident hold has no wall-clock deadline', () async {
    final exited = Completer<void>();
    final launcher = _FakeFollowerLauncher(
      launches: <Future<LaunchedDaemon> Function()>[
        () async => LaunchedDaemon(
          pid: 4242,
          pgid: 4242,
          endpoint: _endpoint,
          exited: exited.future,
        ),
      ],
    );
    final processes = _FakeProcessGroupController();
    final runner = ButaneFollowerRunner(
      launcher: launcher,
      processes: processes,
      reapGrace: Duration.zero,
    );
    final terminate = StreamController<void>.broadcast();
    final logs = <String>[];
    var completed = false;

    final run = runBurnFollowerDaemon(
      inputs: _inputs,
      runner: runner,
      terminate: terminate.stream,
      publish: (_) {},
      onLog: logs.add,
      launchTimeout: const Duration(milliseconds: 30),
    ).whenComplete(() => completed = true);

    await Future<void>.delayed(const Duration(milliseconds: 70));
    expect(completed, isFalse);
    terminate.add(null);
    expect(await run, 0);
    expect(
      logs.where(
        (line) => line == 'teardown-receipt: burn follower daemon reaped',
      ),
      hasLength(1),
    );
    await terminate.close();
  });

  test(
    'resident fallback observes child death without launcher exit future',
    () async {
      final launcher = _FakeFollowerLauncher();
      final processes = _FakeProcessGroupController();
      final runner = ButaneFollowerRunner(
        launcher: launcher,
        processes: processes,
        reapGrace: Duration.zero,
        residentExitPollInterval: Duration.zero,
      );
      final terminate = StreamController<void>();
      final published = <String>[];
      final logs = <String>[];

      final run = runBurnFollowerDaemon(
        inputs: _inputs,
        runner: runner,
        terminate: terminate.stream,
        publish: published.add,
        onLog: logs.add,
      );

      while (published.isEmpty) {
        await Future<void>.delayed(Duration.zero);
      }
      processes.alive = false;
      expect(await run.timeout(const Duration(milliseconds: 250)), 1);
      expect(
        logs,
        contains(contains('burn follower child exited while resident')),
      );
      expect(
        logs.where((line) => line.startsWith('teardown-receipt:')),
        hasLength(1),
      );
      expect(runner.isRunning, isFalse);
      await terminate.close();
    },
  );
}
