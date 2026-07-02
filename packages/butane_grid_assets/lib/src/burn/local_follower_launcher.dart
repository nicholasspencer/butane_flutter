/// The PIPELINE-PROOF local [FollowerLauncher] — proves the burn's live entry
/// pieces on ONE box without touching butane: instead of shelling
/// `butane`/`flutter`, it launches a small pure-Dart daemon (the package's
/// `tool/follower_daemon.dart`) under `dart run --enable-vm-service=0`, scrapes
/// the daemon's VM-service URI from its stdout, and returns the running
/// [LaunchedDaemon] (pid + pgid + the published ws:// endpoint) for the M4
/// `terminateGroup` reaper.
///
/// **Process-group posture (load-bearing).** The daemon MUST land in its OWN
/// process group, or the reaper cannot reap it: under `ProcessStartMode.normal`
/// the child inherits the SPAWNER's group, so the "group" named by pid-as-pgid
/// does not exist (ESRCH — the daemon survives) while the child's REAL pgid is
/// the test runner's own group (signalling it kills the suite — exactly what
/// `terminateGroup`'s self-group guard exists to refuse). So this launcher uses
/// `ProcessStartMode.detachedWithStdio` — the one Dart spawn mode that
/// `setsid()`s the child into a fresh session + group, and grid_runtime's own
/// justified spawn posture (`subprocess_provider.dart`) — and resolves the real
/// pgid back from the OS via the injected [ProcessGroupController] (the VM
/// forks an intermediate launcher, so pid ≠ pgid), falling back to pid-as-pgid
/// only when the resolve fails.
///
/// **Readiness scrape.** The launcher completes on the daemon's
/// `GRID_VM_URI=<ws://…/ws>` sentinel (printed AFTER the exploration host is
/// registered — the same readiness barrier the attach test's target uses, so
/// the first `leonard_drive` call can never race the extension registration).
/// The VM's own `The Dart VM service is listening on <http…>` banner is kept as
/// a fallback (converted to the ws form with the `/ws` suffix, as the attach
/// test forms it).
///
/// Loopback only: `--enable-vm-service=0` binds an ephemeral port on
/// 127.0.0.1. No butane, no beads, no network beyond the local VM service.
library;

import 'dart:io';

import 'package:grid_runtime/grid_runtime.dart'
    show ProcessGroupController, SystemProcessGroupController;

import 'follower.dart';
import 'launch_scrape.dart';

void _noLog(String _) {}

/// Launches the pipeline-proof pure-Dart follower daemon on this box.
class LocalDartFollowerLauncher implements FollowerLauncher {
  /// Creates a launcher for the daemon at [daemonEntrypoint] (a `.dart` file —
  /// typically this package's `tool/follower_daemon.dart`), publishing under
  /// [station]. [processes] resolves the spawned group's real pgid;
  /// [readyTimeout] bounds the wait for the daemon's VM-service URI.
  LocalDartFollowerLauncher({
    required this.daemonEntrypoint,
    this.station = 'the-studio-local',
    ProcessGroupController processes = const SystemProcessGroupController(),
    this.readyTimeout = const Duration(seconds: 60),
    void Function(String)? onLog,
  }) : _processes = processes,
       _onLog = onLog ?? _noLog;

  /// The daemon `.dart` entrypoint to launch.
  final String daemonEntrypoint;

  /// The station id stamped on the published [FollowerEndpoint].
  final String station;

  /// How long to wait for the daemon to print its VM-service URI.
  final Duration readyTimeout;

  final ProcessGroupController _processes;
  final void Function(String) _onLog;

  LaunchedDaemon? _last;

  /// The most recently launched daemon (for teardown-of-last-resort in tests),
  /// or null when nothing has launched yet.
  LaunchedDaemon? get lastLaunched => _last;

  @override
  Future<LaunchedDaemon> launch(LaunchSpec spec) async {
    _onLog('local launcher: dart run $daemonEntrypoint (for ${spec.app})');
    final process = await Process.start(
      Platform.resolvedExecutable,
      <String>[
        'run',
        '--enable-vm-service=0',
        '--disable-service-auth-codes',
        daemonEntrypoint,
      ],
      workingDirectory:
          _packageRootOf(daemonEntrypoint) ?? File(daemonEntrypoint).parent.path,
      // detachedWithStdio: the one spawn mode that setsid()s the child into a
      // NEW session + process group (see the library doc — pid-as-pgid under
      // `normal` mode is unreapable/unsafe), while keeping stdio pipes so the
      // URI can be scraped. grid_runtime's justified spawn posture.
      mode: ProcessStartMode.detachedWithStdio,
    );

    final String wsUri;
    try {
      wsUri = await scrapeVmServiceWsUri(process).timeout(readyTimeout);
    } on Object {
      // The daemon never became ready: kill EXACTLY the pid we spawned.
      Process.killPid(process.pid, ProcessSignal.sigkill);
      rethrow;
    }

    final pgid = await _processes.resolvePgid(process.pid) ?? process.pid;
    _onLog(
      'local launcher: daemon pid ${process.pid} (pgid $pgid) ready at $wsUri',
    );
    return _last = LaunchedDaemon(
      pid: process.pid,
      pgid: pgid,
      endpoint: FollowerEndpoint(vmServiceUri: wsUri, station: station),
    );
  }

  /// The nearest ancestor of [dartFile] carrying a resolved
  /// `.dart_tool/package_config.json` (the pub-workspace root), so `dart run`
  /// resolves the daemon's deps regardless of the caller's cwd.
  static String? _packageRootOf(String dartFile) {
    var dir = File(dartFile).parent;
    while (true) {
      if (File('${dir.path}/.dart_tool/package_config.json').existsSync()) {
        return dir.path;
      }
      final parent = dir.parent;
      if (parent.path == dir.path) return null;
      dir = parent;
    }
  }
}
