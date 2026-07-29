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
  Future<int?> resolvePgid(int pid) async => pid;

  @override
  bool signalGroup(int pgid, ProcessSignal signal) {
    signals.add(signal);
    if (signal == ProcessSignal.sigterm) alive = false;
    return true;
  }
}

const _inputs = BurnFollowerDaemonInputs(
  device: 'device-1',
  harnessDirectory: '/harness',
  leonardDrive: '/drive',
);

void main() {
  test('parses required supervisor arguments', () {
    expect(
      BurnFollowerDaemonInputs.parse([
        '--device',
        ' device-1 ',
        '--harness-dir',
        ' /harness ',
        '--leonard-drive',
        ' /drive ',
      ]).device,
      'device-1',
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

    terminate.add(null);
    expect(await run, 0);
    await runner.teardown();
    expect(
      processes.signals.where((signal) => signal == ProcessSignal.sigterm),
      hasLength(1),
    );
    await terminate.close();
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
    expect(logs.first, contains('launch failed'));
    expect(logs.last, 'teardown-receipt: burn follower daemon reaped');
    await runner.teardown();
    expect(processes.signals, isEmpty);
  });

  test('hard deadline settles, receipts, and permits runner reuse', () async {
    Future<void> exercise(Future<LaunchedDaemon> Function() firstLaunch) async {
      final launcher = _FakeFollowerLauncher(
        launches: <Future<LaunchedDaemon> Function()>[
          firstLaunch,
          () async =>
              const LaunchedDaemon(pid: 4242, pgid: 4242, endpoint: _endpoint),
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
        lifecycleTimeout: const Duration(milliseconds: 30),
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
        onReap: () => Completer<void>().future,
      ),
    );
  });
}
