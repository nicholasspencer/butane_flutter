/// The REAL [FollowerLauncher] — builds and launches the butane harness on
/// this box (the live cross-machine arm's follower side; Track H).
///
/// `flutter build <target> --debug` in the harness directory, then a DIRECT
/// launch of the built binary (never `flutter run` — no tool attach on a
/// follower box) with the harness role as the `ROLE` runtime environment.
/// **Debug builds are load-bearing**: release builds install no
/// `LeonardBinding` and expose no VM service, so there is nothing to drive —
/// unlike the old gc deploy.sh, a burn follower must never build `--release`.
///
/// Readiness + process-group posture mirror [LocalDartFollowerLauncher]
/// exactly (the pipeline proof this launcher graduates): spawn
/// `detachedWithStdio` (the one mode that `setsid()`s the child into a fresh
/// group the reaper can signal), scrape the `GRID_VM_URI=` sentinel the
/// harness prints AFTER exploration registration, resolve the real pgid from
/// the OS, and return the [LaunchedDaemon] for the M4 `terminateGroup`
/// reaper.
library;

import 'dart:io';

import 'package:grid_runtime/grid_runtime.dart'
    show ProcessGroupController, SystemProcessGroupController;

import 'follower.dart';
import 'launch_scrape.dart';

void _noLog(String _) {}

/// Builds + launches the butane harness as the burn's follower app.
class ButaneFollowerLauncher implements FollowerLauncher {
  /// Creates a launcher over the harness app at [harnessDirectory] (the
  /// `packages/butane_harness` checkout on this box), publishing under
  /// [station]. [rebuild] runs `flutter build` before every launch — the
  /// follower's provision step; pass `false` to reuse an existing debug
  /// build (iteration/tests).
  ButaneFollowerLauncher({
    required this.harnessDirectory,
    this.station = 'butane-follower',
    this.rebuild = true,
    this.flutterExecutable = 'flutter',
    this.buildTimeout = const Duration(minutes: 10),
    this.readyTimeout = const Duration(minutes: 2),
    ProcessGroupController processes = const SystemProcessGroupController(),
    void Function(String)? onLog,
  }) : _processes = processes,
       _onLog = onLog ?? _noLog;

  /// The butane harness package directory (contains `pubspec.yaml` and the
  /// platform runners).
  final String harnessDirectory;

  /// The station id stamped on the published [FollowerEndpoint].
  final String station;

  /// Whether to `flutter build` before launching.
  final bool rebuild;

  /// The flutter tool (a bare name resolvable on PATH, or an absolute path).
  final String flutterExecutable;

  /// Bounds the provision/build step.
  final Duration buildTimeout;

  /// Bounds the wait for the harness's `GRID_VM_URI=` sentinel.
  final Duration readyTimeout;

  final ProcessGroupController _processes;
  final void Function(String) _onLog;

  LaunchedDaemon? _last;

  /// The most recently launched daemon (teardown-of-last-resort in tests),
  /// or null when nothing has launched yet.
  LaunchedDaemon? get lastLaunched => _last;

  @override
  Future<LaunchedDaemon> launch(LaunchSpec spec) async {
    final target = spec.target;
    if (rebuild) await _build(target);

    final executable = _builtExecutable(target);
    final role = spec.role.isEmpty ? 'peripheral' : spec.role;
    _onLog(
      'butane launcher: launching ${executable.path} '
      '(ROLE=$role)',
    );
    final process = await Process.start(
      executable.path,
      const <String>[],
      environment: <String, String>{'ROLE': role},
      // detachedWithStdio: setsid()s the child into a NEW session + process
      // group (reapable pgid) while keeping stdio pipes for the sentinel
      // scrape — the LocalDartFollowerLauncher posture, verbatim.
      mode: ProcessStartMode.detachedWithStdio,
    );

    final String wsUri;
    try {
      wsUri = await scrapeVmServiceWsUri(process).timeout(readyTimeout);
    } on Object {
      // The harness never became ready: kill EXACTLY the pid we spawned.
      Process.killPid(process.pid, ProcessSignal.sigkill);
      rethrow;
    }

    final pgid = await _processes.resolvePgid(process.pid) ?? process.pid;
    _onLog(
      'butane launcher: harness pid ${process.pid} (pgid $pgid) '
      'ready at $wsUri',
    );
    return _last = LaunchedDaemon(
      pid: process.pid,
      pgid: pgid,
      endpoint: FollowerEndpoint(vmServiceUri: wsUri, station: station),
    );
  }

  /// Provisions the app-under-test: `flutter build <target> --debug` in the
  /// harness directory. Throws [StateError] (with the tool's output tail) on
  /// a nonzero exit.
  Future<void> _build(String target) async {
    _onLog('butane launcher: flutter build $target --debug');
    final result = await Process.run(flutterExecutable, <String>[
      'build',
      target,
      '--debug',
    ], workingDirectory: harnessDirectory).timeout(buildTimeout);
    if (result.exitCode != 0) {
      throw StateError(
        'flutter build $target --debug exited ${result.exitCode}\n'
        'stdout: ${_tail(result.stdout)}\nstderr: ${_tail(result.stderr)}',
      );
    }
  }

  /// The built debug binary for [target]. Throws [StateError] when the build
  /// output is not where the target's layout puts it.
  File _builtExecutable(String target) {
    switch (target) {
      case 'macos':
        // build/macos/Build/Products/Debug/<App>.app/Contents/MacOS/<App>
        final products = Directory(
          '$harnessDirectory/build/macos/Build/Products/Debug',
        );
        final app = products.existsSync()
            ? products.listSync().whereType<Directory>().where(
                (d) => d.path.endsWith('.app'),
              )
            : const <Directory>[];
        for (final bundle in app) {
          final name = bundle.uri.pathSegments
              .lastWhere((s) => s.isNotEmpty)
              .replaceAll('.app', '');
          final executable = File('${bundle.path}/Contents/MacOS/$name');
          if (executable.existsSync()) return executable;
        }
        throw StateError(
          'no built macOS app under ${products.path} — '
          'run with rebuild: true or `flutter build macos --debug` first',
        );
      case 'linux':
        // build/linux/<arch>/debug/bundle/<binary>
        final root = Directory('$harnessDirectory/build/linux');
        if (root.existsSync()) {
          for (final arch in root.listSync().whereType<Directory>()) {
            final bundle = Directory('${arch.path}/debug/bundle');
            if (!bundle.existsSync()) continue;
            for (final file in bundle.listSync().whereType<File>()) {
              return file;
            }
          }
        }
        throw StateError(
          'no built linux bundle under ${root.path} — '
          'run with rebuild: true or `flutter build linux --debug` first',
        );
      default:
        throw StateError(
          'unsupported burn follower target "$target" '
          '(supported: macos, linux)',
        );
    }
  }

  static String _tail(Object? output) {
    final s = '$output';
    return s.length <= 2000 ? s : s.substring(s.length - 2000);
  }
}
