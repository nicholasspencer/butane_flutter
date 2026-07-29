import 'dart:async';

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

class _FakeLeonardDrive implements LeonardDrive {
  final calls = <String>[];

  @override
  Future<void> attach(FollowerEndpoint endpoint) async {
    calls.add('attach:${endpoint.vmServiceUri}');
  }

  @override
  Future<void> close() async => calls.add('close');

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
  Future<void> teardown() async => teardowns++;
}

class _TranscriptRuntimeProvider implements RuntimeProvider {
  final started = <String, RuntimeConfig>{};
  final stopped = <String>[];
  final _events = StreamController<RuntimeEvent>.broadcast();
  final _outputs = <String, StreamController<String>>{};

  void emit(RuntimeEvent event) => _events.add(event);

  void emitOutput(String name, String line) => _outputs[name]?.add(line);

  @override
  Future<void> start(String name, RuntimeConfig config) async {
    started[name] = config;
    _outputs.putIfAbsent(name, StreamController<String>.broadcast);
  }

  @override
  Future<void> stop(String name) async => stopped.add(name);

  @override
  Future<void> interrupt(String name) async {}

  @override
  Stream<RuntimeEvent> get events => _events.stream;

  @override
  Stream<String> output(String name) =>
      _outputs.putIfAbsent(name, StreamController<String>.broadcast).stream;

  @override
  bool isRunning(String name) =>
      started.containsKey(name) && !stopped.contains(name);

  @override
  bool processAlive(String name) => isRunning(name);

  @override
  String peek(String name, int lines) => '';

  @override
  List<String> listRunning(String prefix) =>
      started.keys.where((name) => name.startsWith(prefix)).toList();

  @override
  DateTime? lastActivity(String name) => null;

  @override
  RuntimeEvent? terminalOf(String name) => null;

  @override
  ({int pid, int? pgid})? identityOf(String name) => null;

  @override
  RuntimeCapabilities get capabilities => RuntimeCapabilities.subprocess;
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

Capability _capability(CapabilityRegistry registry, int index) =>
    (registry.host(_mount(kBurnCircuit.steps[index] as CapabilityStep))
            as CapabilityHost)
        .capability;

AllocationContext _allocationContext({
  required _TranscriptRuntimeProvider transport,
  required List<AllocationReport> reports,
  required Bead bead,
}) => AllocationContext(
  treeContext: FakeTreeContext(values: {Bead: bead}),
  args: stepArgs('order-1/$kBurnFollowerStep'),
  transport: transport,
  address: const AllocationAddress('order-1-session', 'order-1/burn-follower'),
  env: const {},
  sink: reports.add,
  kind: StepKind.daemon,
);

TreeContext _hostContext(Map<String, String> followerResult, Bead bead) =>
    FakeTreeContext(
      values: {
        Bead: bead,
        SiblingView: SiblingView(
          results: {'order-1/burn-follower': followerResult},
        ),
      },
    );

void main() {
  group('burnCircuitFor', () {
    test('returns the identical circuit for a complete burn order', () {
      expect(
        identical(burnCircuitFor(_order(_metadata)), kBurnCircuit),
        isTrue,
      );
    });

    test('rejects an incomplete burn order', () {
      expect(burnCircuitFor(_order(const {})), isNull);
    });
  });

  test('registry exposes a process follower and service host', () {
    final registry = buildBurnStationRegistry(
      appendNote: (_, _) async {},
      driveFactory: (_) => _FakeLeonardDrive(),
      burnFollowerEntrypoint: '/package/bin/burn_follower_daemon.dart',
    );

    expect(identical(registry.circuit('burn'), kBurnCircuit), isTrue);
    expect(_capability(registry, 0), isA<ProcessCapability>());
    expect(_capability(registry, 1), isA<BurnHostCapability>());
  });

  test('follower stays mounted from readiness through host report', () async {
    final notes = <({String beadId, String line})>[];
    final drive = _FakeLeonardDrive();
    final registry = buildBurnStationRegistry(
      appendNote: (beadId, line) async =>
          notes.add((beadId: beadId, line: line)),
      driveFactory: (_) => drive.calls.isEmpty ? drive : _FakeLeonardDrive(),
      windowsHostFactory: (_, _) => _FakeHostHarnessLaunch(),
      burnFollowerEntrypoint: '/package/bin/burn_follower_daemon.dart',
      environment: const {
        'BURN_IOS_DEVICE': 'device-from-env',
        'BURN_HARNESS_DIR': '/harness/from/env',
        'LEONARD_DRIVE': '/drive/from/env',
      },
    );
    final follower = _capability(registry, 0) as ProcessCapability;
    final host = _capability(registry, 1) as BurnHostCapability;
    final transport = _TranscriptRuntimeProvider();
    final reports = <AllocationReport>[];
    final bead = _order({
      ..._metadata,
      BurnOrderInputs.centralTargetKey: 'windows',
      BurnOrderInputs.windowsHostKey: 'yoga-from-bead',
    });
    final allocation = follower.createAllocation(
      _allocationContext(transport: transport, reports: reports, bead: bead),
    );

    await allocation.startOrAdopt();
    final name = allocation.address.providerName;
    final config = transport.started[name]!;
    expect(config.command, isNotEmpty);
    expect(config.lifecycle, Lifecycle.longLived);
    expect(config.args, [
      'run',
      '/package/bin/burn_follower_daemon.dart',
      '--device',
      'device-from-bead',
      '--harness-dir',
      '/harness/from/bead',
      '--leonard-drive',
      '/drive/from/bead',
    ]);
    transport.emit(SessionStarted(name: name, pid: 5150, pgid: 5150));
    await Future<void>.delayed(Duration.zero);
    transport.emitOutput(
      name,
      'burn-follower-published ${_endpoint.vmServiceUri}',
    );
    await Future<void>.delayed(Duration.zero);

    final ready = reports.whereType<AllocationReady>().single;
    expect(ready.payload, {
      'endpoint': _endpoint.vmServiceUri,
      'station': 'butane-ios-follower',
      'lease': 'local',
      'target': 'ios',
    });
    expect(transport.stopped, isEmpty);
    expect(
      notes.map((note) => note.line),
      isNot(contains(contains('teardown'))),
    );

    final hostArgs = stepArgs('order-1/$kBurnHostStep');
    final outcome = await host.run(
      _hostContext(ready.payload!, bead),
      hostArgs,
    );
    expect(
      outcome,
      isA<Ok>(),
      reason: outcome is Failed ? outcome.reason : null,
    );
    notes.add((beadId: 'order-1', line: 'host report: TestReport 7/7 passed'));
    expect(transport.stopped, isEmpty);
    expect(
      notes.map((note) => note.line),
      isNot(contains(contains('reaped pgid'))),
    );

    await allocation.dispose();
    await Future<void>.delayed(Duration.zero);
    expect(transport.stopped, [name]);
    expect(
      notes
          .map((note) => note.line)
          .where(
            (line) =>
                line.contains('resident burn-receipt') ||
                line.startsWith('host report:') ||
                line.contains('teardown-receipt: resident follower'),
          )
          .toList(),
      orderedEquals([
        contains('resident burn-receipt: follower published'),
        contains('host report: TestReport 7/7 passed'),
        contains('teardown-receipt: resident follower supervisor stopped'),
      ]),
    );
    await host.teardown(hostArgs);
  });

  test(
    'invalid published URI fails without readiness and stops once',
    () async {
      final registry = buildBurnStationRegistry(
        appendNote: (_, _) async {},
        driveFactory: (_) => _FakeLeonardDrive(),
        burnFollowerEntrypoint: '/package/bin/burn_follower_daemon.dart',
      );
      final follower = _capability(registry, 0) as ProcessCapability;
      final transport = _TranscriptRuntimeProvider();
      final reports = <AllocationReport>[];
      final allocation = follower.createAllocation(
        _allocationContext(
          transport: transport,
          reports: reports,
          bead: _order(_metadata),
        ),
      );

      await allocation.startOrAdopt();
      final name = allocation.address.providerName;
      transport.emit(SessionStarted(name: name, pid: 5150, pgid: 5150));
      await Future<void>.delayed(Duration.zero);
      transport.emitOutput(name, 'burn-follower-published http://127.0.0.1/ws');
      await Future<void>.delayed(Duration.zero);

      expect(reports.whereType<AllocationFailed>(), hasLength(1));
      expect(reports.whereType<AllocationReady>(), isEmpty);
      await allocation.dispose();
      await Future<void>.delayed(Duration.zero);
      expect(transport.stopped, [name]);
    },
  );

  test('Windows metadata selects remote central and two drives', () async {
    final remote = _FakeHostHarnessLaunch();
    final drives = <_FakeLeonardDrive>[];
    final registry = buildBurnStationRegistry(
      appendNote: (_, _) async {},
      driveFactory: (_) {
        final drive = _FakeLeonardDrive();
        drives.add(drive);
        return drive;
      },
      windowsHostFactory: (_, _) => remote,
      burnFollowerEntrypoint: '/package/bin/burn_follower_daemon.dart',
    );
    final follower = _capability(registry, 0) as ProcessCapability;
    final host = _capability(registry, 1) as BurnHostCapability;
    final metadata = {
      ..._metadata,
      BurnOrderInputs.centralTargetKey: 'windows',
      BurnOrderInputs.windowsHostKey: 'yoga-from-bead',
    };
    final bead = _order(metadata);
    final transport = _TranscriptRuntimeProvider();
    final reports = <AllocationReport>[];
    final allocation = follower.createAllocation(
      _allocationContext(transport: transport, reports: reports, bead: bead),
    );
    await allocation.startOrAdopt();

    final hostArgs = stepArgs('order-1/$kBurnHostStep');
    final outcome = await host.run(
      _hostContext(const {
        'endpoint': 'ws://ios:5000/follower/ws',
        'station': 'mac',
        'lease': 'local',
        'target': 'ios',
      }, bead),
      hostArgs,
    );

    expect(outcome, isA<Ok>());
    expect(remote.launches, 1);
    expect(drives, hasLength(2));
    await host.teardown(hostArgs);
    expect(remote.teardowns, 1);
    await allocation.dispose();
  });
}
