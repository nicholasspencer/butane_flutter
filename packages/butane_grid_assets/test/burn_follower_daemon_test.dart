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
  _FakeFollowerLauncher({this.error});

  final Object? error;
  LaunchSpec? spec;

  @override
  Future<LaunchedDaemon> launch(LaunchSpec spec) async {
    this.spec = spec;
    if (error case final error?) throw error;
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
    expect(logs.single, contains('launch failed'));
    await runner.teardown();
    expect(processes.signals, isEmpty);
  });
}
