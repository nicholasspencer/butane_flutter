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
import 'burn_report.dart' show TestReport;
import 'burn_scenario.dart' show LeonardDrive;
import 'follower.dart'
    show ButaneFollowerRunner, FollowerEndpoint, FollowerLauncher, LaunchSpec;
import 'ios_follower_launcher.dart' show IosFollowerLauncher;
import 'process_leonard_drive.dart' show ProcessLeonardDrive;
import 'remote_windows_host_launch.dart'
    show HostHarnessLaunch, RemoteWindowsHostLaunch;
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
  final List<String> _lines = [];
  String? _beadId;
  Object? _firstError;
  StackTrace? _firstStackTrace;
  Future<void> _pending = Future<void>.value();

  void bind(String beadId) => _beadId = beadId;

  void call(String line) {
    final beadId = _beadId;
    if (beadId == null) {
      throw StateError('resident burn log emitted before StepArgs binding');
    }
    _lines.add(line);
    _pending = _pending.then((_) async {
      try {
        await _append(beadId, line);
      } on Object catch (error, stackTrace) {
        _firstError ??= error;
        _firstStackTrace ??= stackTrace;
      }
    });
  }

  Future<void> flush() async {
    await _pending;
    final error = _firstError;
    if (error != null) {
      Error.throwWithStackTrace(error, _firstStackTrace ?? StackTrace.empty);
    }
  }

  Future<StepOutcome> flushOutcome(StepOutcome outcome) async {
    try {
      await flush();
      return outcome;
    } on Object catch (error) {
      return Failed(
        'note append failed: $error\n'
        'buffered notes:\n${_lines.join('\n')}',
      );
    }
  }
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
      return log.flushOutcome(const Failed('cancelled'));
    }
    if (!endpoint.isPublished) {
      return log.flushOutcome(const Failed('follower published no endpoint'));
    }
    log.call(
      'resident burn-receipt: follower published ${endpoint.vmServiceUri}',
    );
    return log.flushOutcome(
      Ok({
        'endpoint': endpoint.vmServiceUri,
        'station': endpoint.station,
        'lease': endpoint.leaseId,
        'target': 'ios',
      }),
    );
  }

  @override
  Future<void> teardown(StepArgs args) async {
    log.bind(args.beadId);
    await follower.teardown();
    await log.flush();
  }
}

/// Builds the lifecycle used to launch a Windows central.
typedef WindowsHostLaunchFactory =
    HostHarnessLaunch Function(
      BurnOrderInputs inputs,
      void Function(String) log,
    );

final class _ResidentBurnHostCapability extends BurnHostCapability {
  _ResidentBurnHostCapability({
    required _OrderLeonardDrive drive,
    required this.driveFactory,
    required this.environment,
    required this.windowsHostFactory,
    required this.log,
  }) : super(drive: drive, scenario: kSmokeScenario, onLog: log.call);

  final _BeadNoteLog log;
  final LeonardDrive Function(String executableOverride) driveFactory;
  final Map<String, String> environment;
  final WindowsHostLaunchFactory windowsHostFactory;
  final Expando<BurnHostCapability> _delegates = Expando();

  @override
  Future<StepOutcome> run(TreeContext context, StepArgs args) async {
    log.bind(args.beadId);
    final bead = context.getInheritedSeedOfExactType<Bead>();
    if (bead == null) {
      return Failed(
        'resident burn-host requires ambient work bead ${args.beadId}',
      );
    }
    final inputs = BurnOrderInputs.resolve(
      metadata: bead.metadata,
      environment: environment,
      onLog: log.call,
    );
    final BurnHostCapability delegate;
    switch (inputs.centralTarget) {
      case 'macos':
        delegate = BurnHostCapability(
          drive: drive,
          scenario: kSmokeScenario,
          onLog: log.call,
        );
      case 'windows':
        final centralDrive = _OrderLeonardDrive(driveFactory)
          ..select(inputs.leonardDrive);
        delegate = BurnHostCapability(
          drive: drive,
          scenario: kSmokeScenario,
          hostLaunch: windowsHostFactory(inputs, log.call),
          localSpec: LaunchSpec(
            app: 'butane_windows_example',
            target: 'windows',
            role: 'central',
            scenario: kSmokeScenario.name,
            harnessDirectory: inputs.harnessDirectory,
            leonardDrive: inputs.leonardDrive,
          ),
          localDrive: centralDrive,
          onLog: log.call,
        );
      default:
        return log.flushOutcome(
          Failed('unsupported burn central target "${inputs.centralTarget}"'),
        );
    }
    _delegates[args] = delegate;
    final outcome = await delegate.run(context, args);
    return log.flushOutcome(outcome);
  }

  @override
  Future<void> teardown(StepArgs args) async {
    log.bind(args.beadId);
    final delegate = _delegates[args];
    _delegates[args] = null;
    if (delegate == null) {
      await super.teardown(args);
    } else {
      await delegate.teardown(args);
    }
    await log.flush();
  }

  @override
  TestReport? reportFor(StepArgs args) => _delegates[args]?.reportFor(args);
}

/// Builds the local, single-process burn registry for a resident station.
CapabilityRegistry buildBurnStationRegistry({
  required NoteAppender appendNote,
  DateTime Function()? clock,
  FollowerLauncher? followerLauncher,
  LeonardDrive Function(String executableOverride)? driveFactory,
  WindowsHostLaunchFactory? windowsHostFactory,
  Map<String, String>? environment,
  ProcessGroupController processes = const SystemProcessGroupController(),
}) {
  final log = _BeadNoteLog(appendNote);
  final resolvedDriveFactory =
      driveFactory ??
      (executableOverride) => ProcessLeonardDrive(
        executableOverride: executableOverride,
        onLog: log.call,
      );
  final orderDrive = _OrderLeonardDrive(resolvedDriveFactory);
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
      kBurnHostStep: _ResidentBurnHostCapability(
        drive: orderDrive,
        driveFactory: resolvedDriveFactory,
        environment: environment ?? Platform.environment,
        windowsHostFactory:
            windowsHostFactory ??
            (inputs, onLog) => RemoteWindowsHostLaunch(
              host: inputs.windowsHost,
              repository: inputs.windowsRepo,
              flutterExecutable: inputs.windowsFlutter,
              onLog: onLog,
            ),
        log: log,
      ),
    },
    circuits: const {'burn': kBurnCircuit},
    clock: clock,
  );
}
