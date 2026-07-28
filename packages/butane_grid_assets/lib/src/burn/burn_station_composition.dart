/// Resident, in-process composition for a station that executes burn orders.
library;

import 'dart:io' show Platform;

import 'package:beads_dart/beads_dart.dart' show Bead;
import 'package:genesis_tree/genesis_tree.dart' show TreeContext;
import 'package:grid_engine/grid_engine.dart'
    show
        CapabilityRegistry,
        Circuit,
        DefaultCapabilityRegistry,
        Failed,
        Ok,
        ServiceCapability,
        StepArgs,
        StepOutcome;
import 'package:grid_runtime/grid_runtime.dart'
    show ProcessGroupController, SystemProcessGroupController;

import 'burn_capabilities.dart'
    show
        BurnHostCapability,
        LocalFollowerLaunch,
        kBurnCircuit,
        kBurnFollowerStep,
        kBurnHostStep;
import 'burn_order_inputs.dart' show BurnOrderInputs;
import 'burn_scenario.dart' show LeonardDrive;
import 'follower.dart'
    show ButaneFollowerRunner, FollowerEndpoint, FollowerLauncher, LaunchSpec;
import 'ios_follower_launcher.dart' show IosFollowerLauncher;
import 'process_leonard_drive.dart' show ProcessLeonardDrive;
import 'scenarios.dart' show kSmokeScenario;

/// Appends one station observation to the work bead named by [beadId].
typedef NoteAppender = Future<void> Function(String beadId, String line);

/// Returns the resident burn circuit only for a complete burn-order bead.
Circuit? burnCircuitFor(Bead bead) {
  bool carries(String key) {
    final value = bead.metadata[key];
    return value is String && value.trim().isNotEmpty;
  }

  return carries(BurnOrderInputs.followerDeviceKey) &&
          carries(BurnOrderInputs.harnessDirectoryKey) &&
          carries(BurnOrderInputs.leonardDriveKey)
      ? kBurnCircuit
      : null;
}

final class _BeadNoteLog {
  _BeadNoteLog(this._append);

  final NoteAppender _append;
  String? _beadId;
  Future<void> _pending = Future<void>.value();

  void bind(String beadId) => _beadId = beadId;

  void call(String line) {
    final beadId = _beadId;
    if (beadId == null) {
      throw StateError('resident burn log emitted before StepArgs binding');
    }
    _pending = _pending.then((_) => _append(beadId, line));
  }

  Future<void> flush() => _pending;
}

final class _OrderLeonardDrive implements LeonardDrive {
  _OrderLeonardDrive(this._factory);

  final LeonardDrive Function(String executableOverride) _factory;
  LeonardDrive? _delegate;

  void select(String executableOverride) {
    _delegate = _factory(executableOverride);
  }

  LeonardDrive get _configured =>
      _delegate ??
      (throw StateError(
        'resident burn drive was not configured by burn-follower',
      ));

  @override
  Future<void> attach(FollowerEndpoint endpoint) =>
      _configured.attach(endpoint);

  @override
  Future<String> observe(String path) => _configured.observe(path);

  @override
  Future<String> invoke(String tool, Map<String, Object?> args) =>
      _configured.invoke(tool, args);

  @override
  Future<void> close() => _configured.close();
}

final class _ResidentBurnFollowerCapability extends ServiceCapability {
  _ResidentBurnFollowerCapability({
    required this.follower,
    required this.drive,
    required this.environment,
    required this.log,
  });

  final LocalFollowerLaunch follower;
  final _OrderLeonardDrive drive;
  final Map<String, String> environment;
  final _BeadNoteLog log;

  @override
  Future<StepOutcome> run(TreeContext context, StepArgs args) async {
    log.bind(args.beadId);
    final bead = context.getInheritedSeedOfExactType<Bead>();
    if (bead == null) {
      return Failed(
        'resident burn-follower requires ambient work bead ${args.beadId}',
      );
    }
    final inputs = BurnOrderInputs.resolve(
      metadata: bead.metadata,
      environment: environment,
      onLog: log.call,
    );
    drive.select(inputs.leonardDrive);
    final endpoint = await follower.launch(
      LaunchSpec(
        app: 'butane_harness',
        target: 'ios',
        role: 'peripheral',
        scenario: kSmokeScenario.name,
      ).withBurnInputs(inputs),
    );
    if (args.cancel.isCancelled) {
      await log.flush();
      return const Failed('cancelled');
    }
    if (!endpoint.isPublished) {
      await log.flush();
      return const Failed('follower published no endpoint');
    }
    log.call(
      'resident burn-receipt: follower published ${endpoint.vmServiceUri}',
    );
    await log.flush();
    return Ok({
      'endpoint': endpoint.vmServiceUri,
      'station': endpoint.station,
      'lease': endpoint.leaseId,
      'target': 'ios',
    });
  }

  @override
  Future<void> teardown(StepArgs args) async {
    log.bind(args.beadId);
    await follower.teardown();
    await log.flush();
  }
}

final class _ResidentBurnHostCapability extends BurnHostCapability {
  _ResidentBurnHostCapability({
    required _OrderLeonardDrive drive,
    required this.log,
  }) : super(drive: drive, scenario: kSmokeScenario, onLog: log.call);

  final _BeadNoteLog log;

  @override
  Future<StepOutcome> run(TreeContext context, StepArgs args) async {
    log.bind(args.beadId);
    final outcome = await super.run(context, args);
    await log.flush();
    return outcome;
  }

  @override
  Future<void> teardown(StepArgs args) async {
    log.bind(args.beadId);
    await super.teardown(args);
    await log.flush();
  }
}

/// Builds the local, single-process burn registry for a resident station.
CapabilityRegistry buildBurnStationRegistry({
  required NoteAppender appendNote,
  DateTime Function()? clock,
  FollowerLauncher? followerLauncher,
  LeonardDrive Function(String executableOverride)? driveFactory,
  Map<String, String>? environment,
  ProcessGroupController processes = const SystemProcessGroupController(),
}) {
  final log = _BeadNoteLog(appendNote);
  final orderDrive = _OrderLeonardDrive(
    driveFactory ??
        (executableOverride) => ProcessLeonardDrive(
          executableOverride: executableOverride,
          onLog: log.call,
        ),
  );
  final follower = LocalFollowerLaunch(
    runner: ButaneFollowerRunner(
      launcher:
          followerLauncher ??
          IosFollowerLauncher(processes: processes, onLog: log.call),
      processes: processes,
      onLog: log.call,
    ),
    onLog: log.call,
  );
  return DefaultCapabilityRegistry(
    capabilities: {
      kBurnFollowerStep: _ResidentBurnFollowerCapability(
        follower: follower,
        drive: orderDrive,
        environment: environment ?? Platform.environment,
        log: log,
      ),
      kBurnHostStep: _ResidentBurnHostCapability(drive: orderDrive, log: log),
    },
    circuits: const {'burn': kBurnCircuit},
    clock: clock,
  );
}
