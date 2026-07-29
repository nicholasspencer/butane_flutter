import 'dart:async';
import 'dart:io';

import 'package:beads_dart/beads_dart.dart';
import 'package:butane_grid_assets/butane_grid_assets.dart';
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/testing.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

const _endpoint = FollowerEndpoint(
  vmServiceUri: 'ws://127.0.0.1:5599/Test=/ws',
  station: 'resident-test',
  leaseId: 'local',
);

class _FakeFollowerLauncher implements FollowerLauncher {
  LaunchSpec? spec;

  @override
  Future<LaunchedDaemon> launch(LaunchSpec spec) async {
    this.spec = spec;
    return const LaunchedDaemon(pid: 4242, pgid: 4242, endpoint: _endpoint);
  }
}

class _DelayedFollowerLauncher implements FollowerLauncher {
  final Completer<LaunchedDaemon> _launched = Completer<LaunchedDaemon>();
  LaunchSpec? spec;

  @override
  Future<LaunchedDaemon> launch(LaunchSpec spec) {
    this.spec = spec;
    return _launched.future;
  }

  void complete() {
    _launched.complete(
      const LaunchedDaemon(pid: 4242, pgid: 4242, endpoint: _endpoint),
    );
  }
}

class _FakeLeonardDrive implements LeonardDrive {
  final calls = <String>[];

  @override
  Future<void> attach(FollowerEndpoint endpoint) async {
    calls.add('attach:${endpoint.vmServiceUri}');
  }

  @override
  Future<void> close() async {
    calls.add('close');
  }

  @override
  Future<String> invoke(String tool, Map<String, Object?> args) async {
    calls.add('invoke:$tool');
    if (tool == 'butane.check_state') return '{"state":"poweredOn"}';
    return '{"matched":true,"added":true,"advertising":true}';
  }

  @override
  Future<String> observe(String path) async {
    calls.add('observe:$path');
    if (path.endsWith('.role')) return 'central';
    return 'BURN-LIVE';
  }
}

class _FakeHostHarnessLaunch implements HostHarnessLaunch {
  var launches = 0;
  var teardowns = 0;

  @override
  Future<FollowerEndpoint> launch(LaunchSpec spec) async {
    launches++;
    return const FollowerEndpoint(
      vmServiceUri: 'ws://yoga-win:6000/central/ws',
      station: 'windows-host',
    );
  }

  @override
  Future<void> teardown() async {
    teardowns++;
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

StepMount _mount(CapabilityStep step) => StepMount(
  step: step,
  nodePath: 'order-1/${step.stepId}',
  circuit: kBurnCircuit,
  circuitPath: 'order-1',
  session: const SessionHandle('order-1-session'),
  node: const NodeCursor(),
  key: ValueKey('order-1/${step.stepId}#0.0'),
);

Bead _order(Map<String, dynamic> metadata) =>
    Bead(id: 'order-1', metadata: metadata);

const _metadata = <String, dynamic>{
  BurnOrderInputs.followerDeviceKey: ' device-from-bead ',
  BurnOrderInputs.harnessDirectoryKey: ' /harness/from/bead ',
  BurnOrderInputs.leonardDriveKey: ' /drive/from/bead ',
};

void main() {
  group('burnCircuitFor', () {
    test('returns the identical circuit for the complete burn-order shape', () {
      expect(
        identical(burnCircuitFor(_order(_metadata)), kBurnCircuit),
        isTrue,
      );
    });

    for (final key in const [
      BurnOrderInputs.followerDeviceKey,
      BurnOrderInputs.harnessDirectoryKey,
      BurnOrderInputs.leonardDriveKey,
    ]) {
      for (final invalid in const <Object?>[null, '   ', 7]) {
        test('returns null when $key is $invalid', () {
          final metadata = Map<String, dynamic>.of(_metadata);
          if (invalid == null) {
            metadata.remove(key);
          } else {
            metadata[key] = invalid;
          }
          expect(burnCircuitFor(_order(metadata)), isNull);
        });
      }
    }
  });

  test('registry exposes resident burn capabilities only', () {
    final registry = buildBurnStationRegistry(
      appendNote: (_, _) async {},
      followerLauncher: _FakeFollowerLauncher(),
      driveFactory: (_) => _FakeLeonardDrive(),
      processes: _FakeProcessGroupController(),
    );

    expect(identical(registry.circuit('burn'), kBurnCircuit), isTrue);
    expect(registry.circuit('code'), isNull);
    final follower =
        (registry.host(_mount(kBurnCircuit.steps[0] as CapabilityStep))
                as CapabilityHost)
            .capability;
    final host =
        (registry.host(_mount(kBurnCircuit.steps[1] as CapabilityStep))
                as CapabilityHost)
            .capability;
    expect(follower, isA<ServiceCapability>());
    expect(host, isA<BurnHostCapability>());
  });

  test('metadata wins over environment and notes are awaited', () async {
    final launcher = _FakeFollowerLauncher();
    final processes = _FakeProcessGroupController();
    final notes = <({String beadId, String line})>[];
    final firstNote = Completer<void>();
    var appendCount = 0;
    String? driveOverride;
    final registry = buildBurnStationRegistry(
      appendNote: (beadId, line) {
        notes.add((beadId: beadId, line: line));
        appendCount++;
        return appendCount == 1 ? firstNote.future : Future<void>.value();
      },
      followerLauncher: launcher,
      driveFactory: (override) {
        driveOverride = override;
        return _FakeLeonardDrive();
      },
      environment: const {
        'BURN_IOS_DEVICE': 'device-from-env',
        'BURN_HARNESS_DIR': '/harness/from/env',
        'LEONARD_DRIVE': '/drive/from/env',
      },
      processes: processes,
    );
    final capability =
        (registry.host(_mount(kBurnCircuit.steps[0] as CapabilityStep))
                    as CapabilityHost)
                .capability
            as ServiceCapability;
    final host =
        (registry.host(_mount(kBurnCircuit.steps[1] as CapabilityStep))
                    as CapabilityHost)
                .capability
            as BurnHostCapability;
    final args = stepArgs('order-1/$kBurnFollowerStep');
    var completed = false;
    final run = capability
        .run(FakeTreeContext(values: {Bead: _order(_metadata)}), args)
        .whenComplete(() => completed = true);

    while (launcher.spec == null) {
      await Future<void>.delayed(Duration.zero);
    }
    await Future<void>.delayed(Duration.zero);
    expect(completed, isFalse);
    firstNote.complete();
    final outcome = await run;

    expect(
      outcome,
      isA<Ok>(),
      reason: outcome is Failed ? outcome.reason : null,
    );
    expect(launcher.spec!.followerDevice, 'device-from-bead');
    expect(launcher.spec!.harnessDirectory, '/harness/from/bead');
    expect(launcher.spec!.leonardDrive, '/drive/from/bead');
    expect(driveOverride, '/drive/from/bead');
    expect(
      notes.map((note) => note.line),
      isNot(contains(contains('metadata absent; using environment'))),
    );
    expect(notes.every((note) => note.beadId == 'order-1'), isTrue);
    expect(
      notes.map((note) => note.line),
      contains(contains('resident burn-receipt: follower published')),
    );

    await capability.teardown(args);
    await capability.teardown(args);
    expect(
      processes.signals.where((signal) => signal == ProcessSignal.sigterm),
      hasLength(1),
    );
    expect(
      notes.map((note) => note.line),
      contains('teardown-receipt: resident follower reaped'),
    );
    await host.teardown(stepArgs('order-1/$kBurnHostStep'));
    expect(notes.map((note) => note.line).toList(), [
      'follower: provision+build+launch butane_harness for ios',
      'follower: launched pid 4242 (pgid 4242); published '
          'ws://127.0.0.1:5599/Test=/ws',
      'resident burn-receipt: follower published '
          'ws://127.0.0.1:5599/Test=/ws',
      'follower: reaped pgid 4242 → exitedOnTerm',
      'teardown-receipt: resident follower reaped',
      'teardown-receipt: resident follower reaped',
      'follower drive closed',
      'teardown-receipt: follower drive closed',
    ]);
  });

  test(
    'rejected notes stay observed and fail the capability with evidence',
    () async {
      final launcher = _DelayedFollowerLauncher();
      final uncaught = <Object>[];
      late StepOutcome outcome;

      await runZonedGuarded(() async {
        final registry = buildBurnStationRegistry(
          appendNote: (_, _) =>
              Future<void>.error(StateError('station offline')),
          followerLauncher: launcher,
          driveFactory: (_) => _FakeLeonardDrive(),
          environment: const {
            'BURN_IOS_DEVICE': 'device-from-env',
            'BURN_HARNESS_DIR': '/harness/from/env',
            'LEONARD_DRIVE': '/drive/from/env',
          },
          processes: _FakeProcessGroupController(),
        );
        final capability =
            (registry.host(_mount(kBurnCircuit.steps[0] as CapabilityStep))
                        as CapabilityHost)
                    .capability
                as ServiceCapability;
        final metadata = Map<String, dynamic>.of(_metadata)
          ..remove(BurnOrderInputs.followerDeviceKey);
        final run = capability.run(
          FakeTreeContext(values: {Bead: _order(metadata)}),
          stepArgs('order-1/$kBurnFollowerStep'),
        );

        while (launcher.spec == null) {
          await Future<void>.delayed(Duration.zero);
        }
        await Future<void>.delayed(Duration.zero);
        expect(uncaught, isEmpty);

        launcher.complete();
        outcome = await run;
      }, (error, _) => uncaught.add(error));

      expect(uncaught, isEmpty);
      expect(outcome, isA<Failed>());
      final reason = (outcome as Failed).reason;
      expect(
        reason,
        startsWith('note append failed: Bad state: station offline'),
      );
      expect(
        reason,
        contains(
          'burn input burn.follower_device: metadata absent; using environment '
          'BURN_IOS_DEVICE',
        ),
      );
      expect(
        reason,
        contains('follower: provision+build+launch butane_harness for ios'),
      );
      expect(
        reason,
        contains(
          'resident burn-receipt: follower published '
          'ws://127.0.0.1:5599/Test=/ws',
        ),
      );
    },
  );

  test(
    'Windows metadata selects a remote central and two direct drives',
    () async {
      final remote = _FakeHostHarnessLaunch();
      final drives = <_FakeLeonardDrive>[];
      var factoryCalls = 0;
      final registry = buildBurnStationRegistry(
        appendNote: (_, _) async {},
        followerLauncher: _FakeFollowerLauncher(),
        driveFactory: (_) {
          final drive = _FakeLeonardDrive();
          drives.add(drive);
          return drive;
        },
        windowsHostFactory: (inputs, _) {
          factoryCalls++;
          expect(inputs.windowsHost, 'yoga-from-bead');
          return remote;
        },
        processes: _FakeProcessGroupController(),
      );
      final follower =
          (registry.host(_mount(kBurnCircuit.steps[0] as CapabilityStep))
                      as CapabilityHost)
                  .capability
              as ServiceCapability;
      final host =
          (registry.host(_mount(kBurnCircuit.steps[1] as CapabilityStep))
                      as CapabilityHost)
                  .capability
              as ServiceCapability;
      final metadata = <String, dynamic>{
        ..._metadata,
        BurnOrderInputs.centralTargetKey: 'windows',
        BurnOrderInputs.windowsHostKey: 'yoga-from-bead',
      };
      final context = FakeTreeContext(
        values: {
          Bead: _order(metadata),
          SiblingView: const SiblingView(
            results: {
              'order-1/burn-follower': {
                'endpoint': 'ws://ios:5000/follower/ws',
                'station': 'mac',
                'lease': 'lease-1',
                'target': 'ios',
              },
            },
          ),
        },
      );
      final followerArgs = stepArgs('order-1/$kBurnFollowerStep');
      await follower.run(context, followerArgs);
      final hostArgs = stepArgs('order-1/$kBurnHostStep');
      final outcome = await host.run(context, hostArgs);

      expect(
        outcome,
        isA<Ok>(),
        reason: outcome is Failed ? outcome.reason : null,
      );
      expect((outcome as Ok).payload!['central'], 'windows');
      expect(outcome.payload!['follower'], 'ios');
      expect(factoryCalls, 1);
      expect(remote.launches, 1);
      expect(drives, hasLength(2));
      expect(drives[0].calls, contains('attach:ws://ios:5000/follower/ws'));
      expect(drives[1].calls, contains('attach:ws://yoga-win:6000/central/ws'));

      await host.teardown(hostArgs);
      expect(remote.teardowns, 1);
    },
  );

  test(
    'unsupported central target fails before Windows launch or drive attach',
    () async {
      final drives = <_FakeLeonardDrive>[];
      var factoryCalls = 0;
      final registry = buildBurnStationRegistry(
        appendNote: (_, _) async {},
        followerLauncher: _FakeFollowerLauncher(),
        driveFactory: (_) {
          final drive = _FakeLeonardDrive();
          drives.add(drive);
          return drive;
        },
        windowsHostFactory: (_, _) {
          factoryCalls++;
          return _FakeHostHarnessLaunch();
        },
        processes: _FakeProcessGroupController(),
      );
      final host =
          (registry.host(_mount(kBurnCircuit.steps[1] as CapabilityStep))
                      as CapabilityHost)
                  .capability
              as ServiceCapability;
      final context = FakeTreeContext(
        values: {
          Bead: _order({
            ..._metadata,
            BurnOrderInputs.centralTargetKey: 'linux',
          }),
          SiblingView: const SiblingView(
            results: {
              'order-1/burn-follower': {
                'endpoint': 'ws://ios:5000/follower/ws',
                'station': 'mac',
                'lease': 'lease-1',
                'target': 'ios',
              },
            },
          ),
        },
      );

      final outcome = await host.run(
        context,
        stepArgs('order-1/$kBurnHostStep'),
      );
      expect(outcome, isA<Failed>());
      expect(
        (outcome as Failed).reason,
        'unsupported burn central target "linux"',
      );
      expect(factoryCalls, 0);
      expect(drives, isEmpty);
    },
  );
}
