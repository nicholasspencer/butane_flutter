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
  _FakeHostHarnessLaunch({
    this.endpoint = const FollowerEndpoint(
      vmServiceUri: 'ws://yoga-win:6000/central/ws',
      station: 'windows-host',
    ),
  });

  final FollowerEndpoint endpoint;
  final specs = <LaunchSpec>[];
  var launches = 0;
  var teardowns = 0;
  LaunchSpec? lastSpec;

  @override
  Future<FollowerEndpoint> launch(LaunchSpec spec) async {
    specs.add(spec);
    launches++;
    lastSpec = spec;
    return endpoint;
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
  Future<void> write(String name, List<int> bytes) async {}

  @override
  Stream<RuntimeEvent> get events => _events.stream;

  @override
  Stream<String> output(String name) {
    // Mirrors SubprocessProvider from package:grid_runtime: output(name) is
    // permanently empty until start(name) registers the transcript.
    return _outputs[name]?.stream ?? const Stream<String>.empty();
  }

  @override
  Stream<List<int>> interactionOutput(String name) =>
      const Stream<List<int>>.empty();

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
  String exitOutputOf(String name) => '';

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

  test(
    'output subscription created before start never receives publish line',
    () async {
      final transport = _TranscriptRuntimeProvider();
      final received = <String>[];
      const name = 'burn-follower';
      final subscription = transport.output(name).listen(received.add);

      await transport.start(
        name,
        const RuntimeConfig(workDir: '.', command: 'burn-follower'),
      );
      transport.emitOutput(
        name,
        'burn-follower-published ${_endpoint.vmServiceUri}',
      );
      await Future<void>.delayed(Duration.zero);

      expect(received, isEmpty);
      await subscription.cancel();
    },
  );

  test('registry exposes a direct follower capability and service host', () {
    final registry = buildBurnStationRegistry(
      appendNote: (_, _) async {},
      driveFactory: (_) => _FakeLeonardDrive(),
      burnFollowerEntrypoint: '/package/bin/burn_follower_daemon.dart',
    );

    expect(identical(registry.circuit('burn'), kBurnCircuit), isTrue);
    expect(_capability(registry, 0), isA<Capability>());
    expect(_capability(registry, 0), isNot(isA<ProcessCapability>()));
    expect(_capability(registry, 1), isA<BurnHostCapability>());
  });

  test(
    'default follower entrypoint resolves outside the current cwd',
    () async {
      final originalDirectory = Directory.current;
      final temporaryDirectory = await Directory.systemTemp.createTemp(
        'burn-station-composition-',
      );
      Allocation? allocation;

      try {
        Directory.current = temporaryDirectory.path;
        final registry = buildBurnStationRegistry(
          appendNote: (_, _) async {},
          driveFactory: (_) => _FakeLeonardDrive(),
        );
        final transport = _TranscriptRuntimeProvider();
        allocation = _capability(registry, 0).createAllocation(
          _allocationContext(
            transport: transport,
            reports: <AllocationReport>[],
            bead: _order(_metadata),
          ),
        );

        await allocation.startOrAdopt();
        final config = transport.started[allocation.address.providerName]!;
        final entrypoint = config.args[1];
        final packageRoot = File(entrypoint).parent.parent;
        final cwdEntrypoint = temporaryDirectory.uri
            .resolve('bin/burn_follower_daemon.dart')
            .toFilePath();

        expect(entrypoint, endsWith('bin/burn_follower_daemon.dart'));
        expect(File(entrypoint).existsSync(), isTrue);
        expect(entrypoint, isNot(cwdEntrypoint));
        expect(config.workDir, packageRoot.path);
        expect(
          File(
            packageRoot.uri.resolve('pubspec.yaml').toFilePath(),
          ).existsSync(),
          isTrue,
        );
      } finally {
        Directory.current = originalDirectory.path;
        try {
          await allocation?.dispose();
        } finally {
          await temporaryDirectory.delete(recursive: true);
        }
      }
    },
  );

  test(
    'explicit follower entrypoint survives failed package resolution',
    () async {
      const entrypoint = '/explicit/bin/burn_follower_daemon.dart';
      final registry = buildBurnStationRegistry(
        appendNote: (_, _) async {},
        burnFollowerEntrypoint: entrypoint,
        packageUriResolver: (_) => null,
        driveFactory: (_) => _FakeLeonardDrive(),
      );
      final transport = _TranscriptRuntimeProvider();
      final allocation = _capability(registry, 0).createAllocation(
        _allocationContext(
          transport: transport,
          reports: <AllocationReport>[],
          bead: _order(_metadata),
        ),
      );

      try {
        await allocation.startOrAdopt();
        final config = transport.started[allocation.address.providerName]!;
        expect(config.args[1], entrypoint);
      } finally {
        await allocation.dispose();
      }
    },
  );

  test('registry fails when neither follower entrypoint source resolves', () {
    expect(
      () => buildBurnStationRegistry(
        appendNote: (_, _) async {},
        packageUriResolver: (_) => null,
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          allOf(
            contains('package:butane_grid_assets/butane_grid_assets.dart'),
            contains('burnFollowerEntrypoint'),
          ),
        ),
      ),
    );
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
    final follower = _capability(registry, 0);
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
      '--target',
      'ios',
      '--device',
      'device-from-bead',
      '--harness-dir',
      '/harness/from/bead',
      '--leonard-drive',
      '/drive/from/bead',
    ]);
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
    'macOS follower metadata selects daemon and readiness payload',
    () async {
      final registry = buildBurnStationRegistry(
        appendNote: (_, _) async {},
        driveFactory: (_) => _FakeLeonardDrive(),
        burnFollowerEntrypoint: '/package/bin/burn_follower_daemon.dart',
      );
      final follower = _capability(registry, 0);
      final transport = _TranscriptRuntimeProvider();
      final reports = <AllocationReport>[];
      final allocation = follower.createAllocation(
        _allocationContext(
          transport: transport,
          reports: reports,
          bead: _order({
            ..._metadata,
            BurnOrderInputs.followerTargetKey: 'macos',
          }),
        ),
      );

      await allocation.startOrAdopt();
      final name = allocation.address.providerName;
      expect(
        transport.started[name]!.args,
        containsAllInOrder(['--target', 'macos']),
      );
      transport.emitOutput(
        name,
        'burn-follower-published ${_endpoint.vmServiceUri}',
      );
      await Future<void>.delayed(Duration.zero);
      expect(reports.whereType<AllocationReady>().single.payload, {
        'endpoint': _endpoint.vmServiceUri,
        'station': 'butane-macos-follower',
        'lease': 'local',
        'target': 'macos',
      });
      await allocation.dispose();
    },
  );

  test(
    'invalid published URI fails without readiness and stops once',
    () async {
      final registry = buildBurnStationRegistry(
        appendNote: (_, _) async {},
        driveFactory: (_) => _FakeLeonardDrive(),
        burnFollowerEntrypoint: '/package/bin/burn_follower_daemon.dart',
      );
      final follower = _capability(registry, 0);
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
      transport.emitOutput(name, 'burn-follower-published http://127.0.0.1/ws');
      await Future<void>.delayed(Duration.zero);

      expect(reports.whereType<AllocationFailed>(), hasLength(1));
      expect(reports.whereType<AllocationReady>(), isEmpty);
      await allocation.dispose();
      await Future<void>.delayed(Duration.zero);
      expect(transport.stopped, [name]);
    },
  );

  test(
    'follower exit before publication fails and cannot become ready',
    () async {
      final registry = buildBurnStationRegistry(
        appendNote: (_, _) async {},
        driveFactory: (_) => _FakeLeonardDrive(),
        burnFollowerEntrypoint: '/package/bin/burn_follower_daemon.dart',
      );
      final follower = _capability(registry, 0);
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
      transport.emit(Exited(name: name, exitCode: 1));
      await Future<void>.delayed(Duration.zero);
      transport.emitOutput(
        name,
        'burn-follower-published ${_endpoint.vmServiceUri}',
      );
      await Future<void>.delayed(Duration.zero);

      expect(reports.whereType<AllocationFailed>(), hasLength(1));
      expect(reports.whereType<AllocationReady>(), isEmpty);
      await allocation.dispose();
      expect(transport.stopped, [name]);
    },
  );

  test('orphan observation stays live until the follower publishes', () async {
    final notes = <({String beadId, String line})>[];
    final registry = buildBurnStationRegistry(
      appendNote: (beadId, line) async =>
          notes.add((beadId: beadId, line: line)),
      driveFactory: (_) => _FakeLeonardDrive(),
      burnFollowerEntrypoint: '/package/bin/burn_follower_daemon.dart',
    );
    final follower = _capability(registry, 0);
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
    transport.emit(
      SessionOrphaned(name: name, pgid: 4242, memberCount: 2, pid: 4242),
    );
    await Future<void>.delayed(Duration.zero);

    expect(allocation.state, AllocationState.live);
    expect(transport.started, hasLength(1));
    expect(transport.stopped, isEmpty);
    expect(reports, isEmpty);
    expect(
      notes.map((note) => note.line),
      contains(
        'resident burn-observation: follower session orphaned '
        'sessionId=$name pgid=4242 memberCount=2',
      ),
    );

    transport.emitOutput(
      name,
      'burn-follower-published ${_endpoint.vmServiceUri}',
    );
    await Future<void>.delayed(Duration.zero);

    expect(allocation.state, AllocationState.ready);
    expect(reports.whereType<AllocationFailed>(), isEmpty);
    expect(reports.whereType<AllocationReady>(), hasLength(1));
    await allocation.dispose();
    expect(transport.stopped, [name]);
  });

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
    final follower = _capability(registry, 0);
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
    expect(remote.specs, hasLength(1));
    expect(remote.specs.single.app, 'butane_harness');
    expect(remote.specs.single.target, 'windows');
    expect(remote.specs.single.role, 'central');
    expect(drives, hasLength(2));
    await host.teardown(hostArgs);
    expect(remote.teardowns, 1);
    await allocation.dispose();
  });

  test('macOS metadata selects local central and two drives', () async {
    final local = _FakeHostHarnessLaunch(
      endpoint: const FollowerEndpoint(
        vmServiceUri: 'ws://mac:6123/central/ws',
        station: 'macos-central',
      ),
    );
    final drives = <_FakeLeonardDrive>[];
    final notes = <String>[];
    final registry = buildBurnStationRegistry(
      appendNote: (_, line) async => notes.add(line),
      driveFactory: (_) {
        final drive = _FakeLeonardDrive();
        drives.add(drive);
        return drive;
      },
      macosHostFactory: (_, _) => local,
      burnFollowerEntrypoint: '/package/bin/burn_follower_daemon.dart',
    );
    final follower = _capability(registry, 0);
    final host = _capability(registry, 1) as BurnHostCapability;
    final bead = _order({
      ..._metadata,
      BurnOrderInputs.centralTargetKey: 'macos',
    });
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
    expect(local.launches, 1);
    expect(drives, hasLength(2));
    expect(drives[0].calls, contains('attach:ws://ios:5000/follower/ws'));
    expect(drives[1].calls, contains('attach:ws://mac:6123/central/ws'));
    expect(local.lastSpec?.app, 'butane_harness');
    expect(local.lastSpec?.target, 'macos');
    expect(local.lastSpec?.role, 'central');
    expect(local.lastSpec?.scenario, kSmokeScenario.name);
    expect(local.lastSpec?.harnessDirectory, '/harness/from/bead');
    expect(local.lastSpec?.leonardDrive, '/drive/from/bead');
    expect(
      notes,
      contains(
        'operator action: macOS may prompt for Bluetooth access to '
        'butane_harness; the first-run grant is required once',
      ),
    );
    await host.teardown(hostArgs);
    expect(local.teardowns, 1);
    await allocation.dispose();
  });
}
