/// Resident, in-process composition for a station that executes burn orders.
library;

import 'dart:async';
import 'dart:io' show Directory, Platform;
import 'dart:isolate' show Isolate;

import 'package:beads_dart/beads_dart.dart' show Bead;
import 'package:genesis_tree/genesis_tree.dart' show TreeContext;
import 'package:grid_engine/grid_engine.dart'
    show
        CapabilityRegistry,
        Circuit,
        DefaultCapabilityRegistry,
        Allocation,
        AllocationContext,
        AllocationFailed,
        AllocationReady,
        AllocationState,
        Capability,
        Failed,
        StepArgs,
        StepOutcome;
import 'package:grid_runtime/grid_runtime.dart'
    show
        ActivityChanged,
        Died,
        Exited,
        Lifecycle,
        Respawned,
        RuntimeConfig,
        RuntimeEvent,
        SessionOrphaned,
        SessionStarted,
        SystemProcessGroupController;
import 'package:meta/meta.dart' show visibleForTesting;

import 'burn_capabilities.dart'
    show
        BurnHostCapability,
        LocalFollowerLaunch,
        kBurnCircuit,
        kBurnFollowerStep,
        kBurnHostStep;
import 'burn_order_inputs.dart' show BurnOrderInputs;
import 'burn_preflight.dart' show BurnPreflight;
import 'burn_preflight_io.dart' show systemBurnPreflight;
import 'burn_report.dart' show TestReport;
import 'burn_scenario.dart' show LeonardDrive;
import 'follower.dart' show ButaneFollowerRunner, FollowerEndpoint, LaunchSpec;
import 'macos_central_launcher.dart' show MacosCentralLauncher;
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

const _publishedPrefix = 'burn-follower-published ';

final class _ResidentBurnFollowerCapability extends Capability {
  _ResidentBurnFollowerCapability({
    required this.drive,
    required this.environment,
    required this.log,
    required this.entrypoint,
    required this.preflight,
  });

  final _OrderLeonardDrive drive;
  final Map<String, String> environment;
  final _BeadNoteLog log;
  final String entrypoint;
  final BurnPreflight preflight;

  Future<({RuntimeConfig config, String followerTarget})> spawn(
    TreeContext context,
    StepArgs args,
  ) async {
    log.bind(args.beadId);
    final bead = context.getInheritedSeedOfExactType<Bead>();
    if (bead == null) {
      throw StateError(
        'resident burn-follower requires ambient work bead ${args.beadId}',
      );
    }
    final inputs = BurnOrderInputs.resolve(
      metadata: bead.metadata,
      environment: environment,
      onLog: log.call,
    );
    if (inputs.preconditions.isNotEmpty) {
      await preflight.validate(inputs);
    }
    drive.select(inputs.leonardDrive);
    return (
      config: RuntimeConfig(
        workDir: Directory(entrypoint).parent.parent.path,
        command: Platform.resolvedExecutable,
        args: [
          'run',
          entrypoint,
          '--target',
          inputs.followerTarget,
          '--device',
          inputs.followerDevice,
          '--harness-dir',
          inputs.harnessDirectory,
          '--leonard-drive',
          inputs.leonardDrive,
        ],
        lifecycle: Lifecycle.longLived,
      ),
      followerTarget: inputs.followerTarget,
    );
  }

  @override
  Allocation createAllocation(AllocationContext context) =>
      _PublishedFollowerAllocation(this, context, log);
}

final class _PublishedFollowerAllocation extends Allocation {
  _PublishedFollowerAllocation(this.capability, super.context, this.log);

  final _ResidentBurnFollowerCapability capability;
  final _BeadNoteLog log;
  StreamSubscription<RuntimeEvent>? _eventSubscription;
  StreamSubscription<String>? _outputSubscription;
  bool _started = false;
  bool _terminal = false;
  String _followerTarget = 'ios';

  @override
  Future<void> startOrAdopt() async {
    final name = address.providerName;
    try {
      final base = await capability.spawn(context.treeContext, context.args);
      _followerTarget = base.followerTarget;
      final config = base.config.copyWith(
        env: {...base.config.env, ...context.env},
      );
      _eventSubscription = context.transport.events
          .where((event) => event.name == name)
          .listen(_event);
      _started = true;
      await context.transport.start(name, config);
      // Subscribe AFTER start: output(name) is the session's transcript,
      // which exists only once start() registers the session — before that
      // the provider returns a permanently-empty stream and the publish line
      // can never arrive (the 2026-07-30 live hang). The publish is minutes
      // away (harness launch + readiness), so this cannot race it; a crash
      // in the gap is still caught by the events subscription above.
      _outputSubscription = context.transport.output(name).listen(_line);
      state = AllocationState.live;
    } on Object catch (error) {
      _fail('resident burn follower failed to start: $error');
    }
  }

  void _event(RuntimeEvent event) {
    switch (event) {
      case Exited() || Died():
        _fail('resident burn follower exited before publishing its endpoint');
      case SessionOrphaned(:final pgid, :final memberCount):
        // This is an observation, not a terminal. The runtime still owns and
        // supervises the surviving process group; its later Exited/Died event
        // remains the only lifecycle terminal.
        log.call(
          'resident burn-observation: follower session orphaned '
          'sessionId=${event.name} pgid=$pgid memberCount=$memberCount',
        );
        return;
      case SessionStarted() || Respawned() || ActivityChanged():
        return;
    }
  }

  void _line(String line) {
    if (_terminal || !line.startsWith(_publishedPrefix)) return;
    final uri = line.substring(_publishedPrefix.length).trim();
    final parsed = Uri.tryParse(uri);
    if (parsed == null || !{'ws', 'wss'}.contains(parsed.scheme)) {
      _fail('invalid burn follower endpoint: $uri');
      return;
    }
    _terminal = true;
    state = AllocationState.ready;
    log.call('resident burn-receipt: follower published $uri');
    context.sink(
      AllocationReady({
        'endpoint': uri,
        'station': _followerTarget == 'macos'
            ? 'butane-macos-follower'
            : 'butane-ios-follower',
        'lease': 'local',
        'target': _followerTarget,
      }),
    );
  }

  void _fail(String reason) {
    if (_terminal) return;
    _terminal = true;
    state = AllocationState.gone;
    context.sink(AllocationFailed(reason));
  }

  @override
  Future<void> dispose() async {
    state = AllocationState.dying;
    await _eventSubscription?.cancel();
    await _outputSubscription?.cancel();
    if (_started) await context.transport.stop(address.providerName);
    state = AllocationState.gone;
    log.call('teardown-receipt: resident follower supervisor stopped');
    await log.flush();
  }
}

/// Builds the lifecycle used to launch a Windows central.
typedef WindowsHostLaunchFactory =
    HostHarnessLaunch Function(
      BurnOrderInputs inputs,
      void Function(String) log,
    );

/// Builds the lifecycle used to launch a macOS central.
typedef MacosHostLaunchFactory =
    HostHarnessLaunch Function(
      BurnOrderInputs inputs,
      void Function(String) log,
    );

final class _ResidentBurnHostCapability extends BurnHostCapability {
  _ResidentBurnHostCapability({
    required _OrderLeonardDrive drive,
    required this.driveFactory,
    required this.environment,
    required this.macosHostFactory,
    required this.windowsHostFactory,
    required this.log,
  }) : super(drive: drive, scenario: kSmokeScenario, onLog: log.call);

  final _BeadNoteLog log;
  final LeonardDrive Function(String executableOverride) driveFactory;
  final Map<String, String> environment;
  final MacosHostLaunchFactory macosHostFactory;
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
        log.call(
          'operator action: macOS may prompt for Bluetooth access to '
          'butane_harness; the first-run grant is required once',
        );
        final centralDrive = _OrderLeonardDrive(driveFactory)
          ..select(inputs.leonardDrive);
        delegate = BurnHostCapability(
          drive: drive,
          scenario: kSmokeScenario,
          hostLaunch: macosHostFactory(inputs, log.call),
          localSpec: LaunchSpec(
            app: 'butane_harness',
            target: 'macos',
            role: 'central',
            scenario: kSmokeScenario.name,
            harnessDirectory: inputs.harnessDirectory,
            leonardDrive: inputs.leonardDrive,
          ),
          localDrive: centralDrive,
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
            app: 'butane_harness',
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
  String? burnFollowerEntrypoint,
  @visibleForTesting Uri? Function(Uri)? packageUriResolver,
  LeonardDrive Function(String executableOverride)? driveFactory,
  MacosHostLaunchFactory? macosHostFactory,
  WindowsHostLaunchFactory? windowsHostFactory,
  Map<String, String>? environment,
  BurnPreflight? preflight,
}) {
  const packageLibrary = 'package:butane_grid_assets/butane_grid_assets.dart';
  final packageEntrypoint =
      (packageUriResolver ?? Isolate.resolvePackageUriSync)(
        Uri.parse(packageLibrary),
      )?.resolve('../bin/burn_follower_daemon.dart').toFilePath();
  final resolvedBurnFollowerEntrypoint =
      burnFollowerEntrypoint ??
      packageEntrypoint ??
      (throw StateError(
        'Could not resolve $packageLibrary and no '
        'burnFollowerEntrypoint was provided.',
      ));
  final log = _BeadNoteLog(appendNote);
  final resolvedDriveFactory =
      driveFactory ??
      (executableOverride) => ProcessLeonardDrive(
        executableOverride: executableOverride,
        onLog: log.call,
      );
  final orderDrive = _OrderLeonardDrive(resolvedDriveFactory);
  final resolvedPreflight = preflight ?? systemBurnPreflight();
  return DefaultCapabilityRegistry(
    capabilities: {
      kBurnFollowerStep: _ResidentBurnFollowerCapability(
        drive: orderDrive,
        environment: environment ?? Platform.environment,
        log: log,
        entrypoint: resolvedBurnFollowerEntrypoint,
        preflight: resolvedPreflight,
      ),
      kBurnHostStep: _ResidentBurnHostCapability(
        drive: orderDrive,
        driveFactory: resolvedDriveFactory,
        environment: environment ?? Platform.environment,
        macosHostFactory:
            macosHostFactory ??
            (inputs, onLog) => LocalFollowerLaunch(
              runner: ButaneFollowerRunner(
                launcher: MacosCentralLauncher(onLog: onLog),
                processes: const SystemProcessGroupController(),
                onLog: onLog,
              ),
              onLog: onLog,
            ),
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
