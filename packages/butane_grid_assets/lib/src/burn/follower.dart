/// The FOLLOWER-side execution of the burn (ADR-0011 D9) — what runs on the
/// leased peer: provision the app-under-test from the butane substation, build it
/// for the target, **launch it exposing `ext.exploration.*`** (the app embeds
/// `leonard_flutter`), **publish its VM-service endpoint**, and **tear it down on
/// release** via the M4 `terminateGroup`/pgid reaper.
///
/// The actual provision/build/launch is the [FollowerLauncher] seam — abstract at
/// this layer so the REAL impl (shelling `butane`/`flutter`) can ship at the live
/// cross-machine arm (Track H, the human gate) while offline tests inject a
/// headless stand-in. What this file OWNS, concretely, is the **guaranteed
/// teardown**: [ButaneFollowerRunner.teardown] reaps the launched daemon's whole
/// process group through grid_runtime's `terminateGroup` reaper — even on the
/// failure path, the leaked follower app is reaped (ADR-0011 Hazards: "orphaned
/// work on the lessor").
///
/// Acts return [Future]s; lib stays print-free (an injectable `onLog`).
library;

import 'package:grid_runtime/grid_runtime.dart'
    show GroupTerminateResult, ProcessGroupController, terminateGroup;
import 'package:meta/meta.dart';

import 'burn_order_inputs.dart';

/// What the host asks the follower to launch (ADR-0011 D9) — the butane domain's
/// dispatch payload, serialized into the kind-agnostic federation bus envelope.
@immutable
class LaunchSpec {
  /// Creates a launch spec for [app] built for [target], booted as [role]
  /// (the burn's follower is the peripheral by convention — the host drives
  /// its own local central), optionally naming the [scenario] the host will
  /// drive (a hint; the host owns the actual scenario).
  const LaunchSpec({
    required this.app,
    required this.target,
    this.role = 'peripheral',
    this.scenario = '',
    this.followerDevice = '',
    this.harnessDirectory = '',
    this.leonardDrive = '',
  });

  /// The app-under-test provisioned from the butane substation (e.g.
  /// `butane_flutter`).
  final String app;

  /// The build target (e.g. `linux`) — matched against the follower's
  /// capability profile by the host before it leases (Track C containment).
  final String target;

  /// The harness role the launched app boots as (`central`/`peripheral`;
  /// the launcher passes it through as the `ROLE` runtime env).
  final String role;

  /// An optional scenario hint carried to the follower (the host owns the drive).
  final String scenario;

  /// The iOS follower device selected by the ORDER bead.
  final String followerDevice;

  /// The harness working directory selected by the ORDER bead.
  final String harnessDirectory;

  /// The leonard-drive executable selected by the ORDER bead.
  final String leonardDrive;

  /// JSON form (the opaque bus dispatch payload).
  Map<String, dynamic> toJson() => {
    'app': app,
    'target': target,
    'role': role,
    if (scenario.isNotEmpty) 'scenario': scenario,
    if (followerDevice.isNotEmpty) 'followerDevice': followerDevice,
    if (harnessDirectory.isNotEmpty) 'harnessDirectory': harnessDirectory,
    if (leonardDrive.isNotEmpty) 'leonardDrive': leonardDrive,
  };

  /// Parses [j] (a missing role defaults to `peripheral` — the burn's
  /// follower convention).
  static LaunchSpec fromJson(Map<String, dynamic> j) => LaunchSpec(
    app: j['app'] as String,
    target: j['target'] as String,
    role: (j['role'] as String?) ?? 'peripheral',
    scenario: (j['scenario'] as String?) ?? '',
    followerDevice: (j['followerDevice'] as String?) ?? '',
    harnessDirectory: (j['harnessDirectory'] as String?) ?? '',
    leonardDrive: (j['leonardDrive'] as String?) ?? '',
  );

  /// Returns this launch request carrying the resolved ORDER burn inputs.
  LaunchSpec withBurnInputs(BurnOrderInputs inputs) => LaunchSpec(
    app: app,
    target: target,
    role: role,
    scenario: scenario,
    followerDevice: inputs.followerDevice,
    harnessDirectory: inputs.harnessDirectory,
    leonardDrive: inputs.leonardDrive,
  );
}

/// The follower's PUBLISHED endpoint (ADR-0011 D9) — the rendezvous handoff the
/// host needs to attach `leonard_drive`. It rides the bus dispatch RESULT
/// envelope; the actual drive traffic is a SEPARATE, direct channel (perception ⊥
/// the bus, ADR-0012).
@immutable
class FollowerEndpoint {
  /// Creates a published endpoint at [vmServiceUri] on [station], optionally
  /// carrying the [leaseId] it was published under.
  const FollowerEndpoint({
    required this.vmServiceUri,
    required this.station,
    this.leaseId = '',
  });

  /// The follower app's `ext.exploration.*` VM-service URI — what `leonard_drive`
  /// attaches to over the LAN, point-to-point, NOT tunneled through the bus.
  final String vmServiceUri;

  /// The follower station id that published this endpoint.
  final String station;

  /// The lease the endpoint was published under (optional).
  final String leaseId;

  /// Whether an endpoint was actually published (a non-empty URI).
  bool get isPublished => vmServiceUri.isNotEmpty;

  /// JSON form (the opaque bus dispatch result).
  Map<String, dynamic> toJson() => {
    'vmServiceUri': vmServiceUri,
    'station': station,
    if (leaseId.isNotEmpty) 'leaseId': leaseId,
  };

  /// Parses [j] (a missing/empty URI yields an unpublished endpoint).
  static FollowerEndpoint fromJson(Map<String, dynamic> j) => FollowerEndpoint(
    vmServiceUri: (j['vmServiceUri'] as String?) ?? '',
    station: (j['station'] as String?) ?? '',
    leaseId: (j['leaseId'] as String?) ?? '',
  );
}

/// A launched follower app — the running daemon's OS handle (pgid/pid, for the
/// reaper) plus its published [endpoint]. Returned by a [FollowerLauncher].
@immutable
class LaunchedDaemon {
  /// Creates a handle for a launched follower app: its [pid] + process-group
  /// [pgid] (the reaper subjects) and the published [endpoint]. [onReap] is an
  /// optional extra teardown the runner awaits AFTER the pgid reap — for a
  /// launch whose cleanup reaches beyond one local process group (the iOS
  /// path: kill the loopback relay, terminate the on-device app).
  const LaunchedDaemon({
    required this.pid,
    required this.pgid,
    required this.endpoint,
    this.exited,
    this.onReap,
  });

  /// The launched leader process pid (the liveness-probe subject for the reaper).
  final int pid;

  /// The launched process GROUP id — `terminateGroup` reaps the whole group so no
  /// child of the follower app survives (ADR-0011 Hazards).
  final int pgid;

  /// The endpoint the launched app published.
  final FollowerEndpoint endpoint;

  /// Completes when the launched child is known to have died.
  final Future<void>? exited;

  /// Extra teardown run once, after the pgid reap (exception-isolated by the
  /// runner). Null for the desktop path (the process group IS the whole
  /// launch); set by the iOS launcher to reap its off-group resources.
  final Future<void> Function()? onReap;
}

/// Provisions + builds + launches the app-under-test on the follower box,
/// exposing `ext.exploration.*` (the app embeds `leonard_flutter`), and returns
/// the running [LaunchedDaemon] (its pgid/pid + the published endpoint). (An act.)
///
/// The REAL impl (shelling `butane`/`flutter`, a NEW process group so the reaper
/// can signal it) ships at the live cross-machine arm (Track H, the human gate);
/// offline tests inject a headless stand-in. This is the ADR-0008
/// pluggable-abstract-domain seam: the burn knows "launch a follower exposing
/// exploration" in concept, not the butane/flutter detail.
abstract interface class FollowerLauncher {
  /// Provisions, builds, and launches [spec], returning the running daemon.
  Future<LaunchedDaemon> launch(LaunchSpec spec);
}

void _noLog(String _) {}

/// The follower-side coordinator (ADR-0011 D9): launches the app-under-test via a
/// [FollowerLauncher] and GUARANTEES its teardown via the M4 `terminateGroup`
/// pgid reaper on release/reap.
///
/// In the federation, a station composes this behind its lease bus (the lessor's
/// dispatch handler launches; the lessor reaps on release/TTL) — the offline
/// tests drive it through a fake lessor station, the live arm through a real
/// `StationServer`. The runner holds at most one launched daemon at a time and
/// reaps it ONCE (a double teardown is a no-op), so a release racing a TTL reap
/// cannot double-signal.
class ButaneFollowerRunner {
  /// Creates a runner over the [launcher] (provision/build/launch) and the
  /// [processes] group controller (the reaper seam). [onLog] observes events.
  ButaneFollowerRunner({
    required FollowerLauncher launcher,
    required ProcessGroupController processes,
    Duration reapGrace = const Duration(seconds: 2),
    void Function(String)? onLog,
  }) : _launcher = launcher,
       _processes = processes,
       _reapGrace = reapGrace,
       _onLog = onLog ?? _noLog;

  final FollowerLauncher _launcher;
  final ProcessGroupController _processes;
  final Duration _reapGrace;
  final void Function(String) _onLog;

  LaunchedDaemon? _daemon;

  /// Whether a launched follower daemon is currently running (un-reaped).
  bool get isRunning => _daemon != null;

  /// Death notification for the currently owned daemon.
  Future<void>? get residentExit => _daemon?.exited;

  /// Provisions + builds + launches [spec], publishing the follower endpoint.
  /// (An act.) A second launch while one is already running reaps the prior
  /// daemon first, so the runner never leaks a previous app.
  Future<FollowerEndpoint> launch(LaunchSpec spec) async {
    if (_daemon != null) {
      _onLog('follower: relaunch — reaping the prior daemon first');
      await teardown();
    }
    _onLog('follower: provision+build+launch ${spec.app} for ${spec.target}');
    final daemon = await _launcher.launch(spec);
    _daemon = daemon;
    _onLog(
      'follower: launched pid ${daemon.pid} (pgid ${daemon.pgid}); '
      'published ${daemon.endpoint.vmServiceUri}',
    );
    return daemon.endpoint;
  }

  /// Reaps the launched follower daemon's whole process group via the M4
  /// `terminateGroup` reaper (SIGTERM → grace → SIGKILL), ONCE. Idempotent: a
  /// teardown with nothing running returns [GroupTerminateResult.alreadyGone].
  /// (An act — the guaranteed teardown, ADR-0011 D9 / Hazards.)
  Future<GroupTerminateResult> teardown() async {
    final daemon = _daemon;
    if (daemon == null) return GroupTerminateResult.alreadyGone;
    _daemon =
        null; // once-only: a release racing a TTL reap cannot double-signal
    final result = await terminateGroup(
      controller: _processes,
      pgid: daemon.pgid,
      leaderPid: daemon.pid,
      grace: _reapGrace,
    );
    _onLog('follower: reaped pgid ${daemon.pgid} → ${result.name}');
    // Off-group cleanup (the iOS relay + on-device app). Exception-isolated:
    // the pgid reap already succeeded, so a hiccup here never fails teardown.
    final onReap = daemon.onReap;
    if (onReap != null) {
      try {
        await onReap();
      } on Object catch (e) {
        _onLog('follower: onReap hiccup (ignored): $e');
      }
    }
    return result;
  }
}
