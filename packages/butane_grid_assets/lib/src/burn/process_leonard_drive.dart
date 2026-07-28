/// The REAL [LeonardDrive] — shells lenny's credential-free, zero-model
/// `leonard_drive` binary once per call (the A40/tg-e28 proven pattern; the same
/// discovery order + JSON envelope parsing as the_grid's
/// `grid_exploration/test/leonard_drive_attach_test.dart`).
///
/// Each call is STATELESS on the wire: `leonard_drive` connects to the
/// follower's VM service, performs one operation, prints a single JSON object
/// on stdout, and disconnects — the drive owns no session. [attach] therefore
/// only stashes the endpoint URI; [close] is a no-op (the follower app's
/// teardown belongs to the `burn-follower` order's lease release, NOT to this
/// channel).
///
/// Discovery order (mirrors the attach test exactly):
///   1. `$LEONARD_DRIVE` (absolute path to the executable/entrypoint, or a bare
///      command resolvable on `$PATH`);
///   2. a `leonard_drive` executable on `$PATH`;
///   3. the sibling lenny checkout's
///      `packages/leonard_cli/bin/leonard_drive.dart` (run via `dart run`) at
///      `~/development/com.nicospencer/lenny`.
///
/// [discover] returns the argv prefix (or null) so a live test can SELF-SKIP
/// when lenny is not checked out — never fail the suite for a missing sibling.
library;

import 'dart:convert';
import 'dart:io';

import 'burn_scenario.dart';
import 'follower.dart';

/// How to invoke `leonard_drive` once discovered (the attach test's shape).
typedef _DriveInvocation = ({
  String executable,
  List<String> prefixArgs,
  String? workingDirectory,
});

/// The real, process-shelling [LeonardDrive] over lenny's `leonard_drive`.
class ProcessLeonardDrive implements LeonardDrive {
  /// Creates the drive. [callTimeout] bounds each shelled call (a `dart run`
  /// first call includes a compile).
  ProcessLeonardDrive({
    this.callTimeout = const Duration(seconds: 120),
    this.executableOverride = '',
    void Function(String)? onLog,
  }) : _onLog = onLog ?? _noLog;

  /// The per-call timeout.
  final Duration callTimeout;

  /// Explicit ORDER-carried executable or entrypoint.
  final String executableOverride;

  final void Function(String) _onLog;

  String? _vmUri;
  _DriveInvocation? _invocation;

  /// Discovers how to invoke `leonard_drive` and returns the argv prefix
  /// (`[executable, ...prefixArgs]`), or `null` when lenny is not discoverable
  /// (the live test's self-skip signal).
  static Future<List<String>?> discover({
    String executableOverride = '',
    void Function(String)? onLog,
  }) async {
    final inv = _discover(
      executableOverride: executableOverride,
      onLog: onLog ?? _noLog,
    );
    return inv == null ? null : [inv.executable, ...inv.prefixArgs];
  }

  /// Resolves an explicit ORDER value, environment compatibility fallback,
  /// PATH, then the sibling checkout.
  static _DriveInvocation? _discover({
    required String executableOverride,
    required void Function(String) onLog,
  }) {
    _DriveInvocation invocationFor(String override) {
      final f = File(override);
      if (f.existsSync()) {
        return override.endsWith('.dart')
            ? (
                executable: _dartExecutable(),
                prefixArgs: <String>['run', override],
                workingDirectory: _packageRootOf(override),
              )
            : (
                executable: override,
                prefixArgs: const <String>[],
                workingDirectory: null,
              );
      }
      return (
        executable: override,
        prefixArgs: const <String>[],
        workingDirectory: null,
      );
    }

    // 1. Explicit ORDER override.
    final explicit = executableOverride.trim();
    if (explicit.isNotEmpty) return invocationFor(explicit);

    // 2. Compatibility environment fallback.
    final override = Platform.environment['LEONARD_DRIVE']?.trim();
    if (override != null && override.trim().isNotEmpty) {
      onLog(
        'burn input burn.leonard_drive: metadata absent; '
        'using environment LEONARD_DRIVE',
      );
      return invocationFor(override);
    }

    // 3. On PATH.
    final onPath = _which('leonard_drive');
    if (onPath != null) {
      return (
        executable: onPath,
        prefixArgs: const <String>[],
        workingDirectory: null,
      );
    }

    // 4. Sibling lenny checkout entrypoint.
    final home = Platform.environment['HOME'];
    if (home != null) {
      final entry = File(
        '$home/development/com.nicospencer/lenny/'
        'packages/leonard_cli/bin/leonard_drive.dart',
      );
      if (entry.existsSync()) {
        return (
          executable: _dartExecutable(),
          prefixArgs: <String>['run', entry.path],
          workingDirectory: _packageRootOf(entry.path),
        );
      }
    }
    return null;
  }

  static String _dartExecutable() => Platform.resolvedExecutable;

  /// The package root for a `.dart` entrypoint — the nearest ancestor carrying
  /// a resolved `.dart_tool/package_config.json` (lenny's pub-workspace root),
  /// so `dart run <entry>` resolves leonard_drive's deps regardless of cwd.
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

  static String? _which(String name) {
    final pathEnv = Platform.environment['PATH'];
    if (pathEnv == null) return null;
    for (final dir in pathEnv.split(Platform.isWindows ? ';' : ':')) {
      if (dir.isEmpty) continue;
      final candidate = File('$dir${Platform.pathSeparator}$name');
      if (candidate.existsSync()) return candidate.path;
    }
    return null;
  }

  @override
  Future<void> attach(FollowerEndpoint endpoint) async {
    // Stateless driver: attaching is just stashing the VM-service URI every
    // subsequent call targets (each call opens its own fresh session).
    _vmUri = endpoint.vmServiceUri;
  }

  @override
  Future<String> observe(String path) async {
    final envelope = await _driveJson(const ['observe']);
    final observation = envelope['observation'];
    if (observation == null) {
      throw StateError(
        'leonard_drive observe printed no observation: $envelope',
      );
    }
    return jsonEncode(_navigate(observation, path));
  }

  @override
  Future<String> invoke(String tool, Map<String, Object?> args) async {
    final envelope = await _driveJson([
      'invoke',
      '--tool',
      tool,
      if (args.isNotEmpty) ...['--args', jsonEncode(args)],
    ]);
    final result = envelope['result'];
    if (result == null) {
      throw StateError('leonard_drive invoke printed no result: $envelope');
    }
    return jsonEncode(result);
  }

  @override
  Future<void> close() async {
    // No-op: each call is stateless, and the follower app's teardown is owned
    // by the `burn-follower` order's lease release (the bus channel).
  }

  /// Walks the dot-separated [path] into the decoded observation. An empty
  /// path returns the whole observation.
  Object? _navigate(Object? root, String path) {
    var node = root;
    for (final seg in path.split('.')) {
      if (seg.isEmpty) continue;
      if (node is! Map) {
        throw StateError(
          'observe: no node at "$path" ("$seg" reached a non-object)',
        );
      }
      node = node[seg];
      if (node == null) {
        throw StateError('observe: nothing at "$path" (missing "$seg")');
      }
    }
    return node;
  }

  /// Runs one `leonard_drive` subcommand against the attached VM URI and
  /// decodes the single JSON object it prints to stdout (the attach test's
  /// parse: `dart run` compile chatter goes to stderr; machine output is the
  /// last JSON-object line on stdout).
  Future<Map<String, Object?>> _driveJson(List<String> subArgs) async {
    final uri = _vmUri;
    if (uri == null || uri.isEmpty) {
      throw StateError('ProcessLeonardDrive: attach(endpoint) first');
    }
    final drive = _invocation ??=
        _discover(executableOverride: executableOverride, onLog: _onLog) ??
        (throw StateError(
          r'leonard_drive not discoverable (set $LEONARD_DRIVE or check out '
          'lenny at ~/development/com.nicospencer/lenny)',
        ));

    final result = await Process.run(drive.executable, <String>[
      ...drive.prefixArgs,
      ...subArgs,
      '--vm-uri',
      uri,
    ], workingDirectory: drive.workingDirectory).timeout(callTimeout);

    if (result.exitCode != 0) {
      throw StateError(
        'leonard_drive ${subArgs.join(' ')} exited ${result.exitCode}\n'
        'stdout: ${result.stdout}\nstderr: ${result.stderr}',
      );
    }
    final lines = (result.stdout as String)
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.startsWith('{'))
        .toList();
    if (lines.isEmpty) {
      throw StateError(
        'leonard_drive ${subArgs.join(' ')} printed no JSON object on stdout: '
        '${result.stdout}',
      );
    }
    return jsonDecode(lines.last) as Map<String, Object?>;
  }
}

void _noLog(String _) {}
