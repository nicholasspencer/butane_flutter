/// Remote Windows central harness lifecycle for the resident burn.
library;

import 'dart:async';
import 'dart:io';

import 'follower.dart';
import 'launch_scrape.dart';

/// Launches and reaps the burn's host-side harness.
abstract interface class HostHarnessLaunch {
  Future<FollowerEndpoint> launch(LaunchSpec spec);
  Future<void> teardown();
}

/// Injectable process start seam for SSH lifecycle tests.
typedef SshProcessStarter =
    Future<Process> Function(String executable, List<String> arguments);

void _noLog(String _) {}

/// Launches the central example on Windows over SSH.
final class RemoteWindowsHostLaunch implements HostHarnessLaunch {
  RemoteWindowsHostLaunch({
    required this.host,
    required this.repository,
    required this.flutterExecutable,
    this.station = 'windows-host',
    this.readyTimeout = const Duration(minutes: 5),
    SshProcessStarter starter = Process.start,
    void Function(String)? onLog,
  }) : _starter = starter,
       _onLog = onLog ?? _noLog;

  final String host;
  final String repository;
  final String flutterExecutable;
  final String station;
  final Duration readyTimeout;
  final SshProcessStarter _starter;
  final void Function(String) _onLog;
  int? _remotePid;
  bool _teardownStarted = false;

  static const _sshOptions = ['-o', 'BatchMode=yes', '-o', 'ConnectTimeout=15'];

  @override
  Future<FollowerEndpoint> launch(LaunchSpec spec) async {
    if (spec.target != 'windows') {
      throw ArgumentError.value(
        spec.target,
        'spec.target',
        'remote Windows host only supports windows',
      );
    }
    final pidReady = Completer<int>();
    final command = _launchCommand(spec);
    final process = await _starter('ssh', [..._sshOptions, host, command]);
    try {
      final uriFuture = scrapeVmServiceWsUri(
        process,
        onLine: (line) {
          _onLog(line);
          final match = RegExp(r'GRID_REMOTE_PID=(\d+)').firstMatch(line);
          if (match != null && !pidReady.isCompleted) {
            final pid = int.parse(match.group(1)!);
            _remotePid = pid;
            pidReady.complete(pid);
          }
        },
      );
      final exitFailure = process.exitCode.then<Object>((code) {
        throw StateError('remote Windows SSH exited with code $code');
      });
      final values = await Future.wait<Object>([
        Future.any<Object>([pidReady.future, exitFailure]),
        Future.any<Object>([uriFuture, exitFailure]),
      ]).timeout(readyTimeout);
      final uri = Uri.parse(values[1] as String);
      if ((uri.scheme != 'ws' && uri.scheme != 'wss') || uri.host.isEmpty) {
        throw FormatException('invalid VM service WebSocket URI', uri);
      }
      final published = uri
          .replace(
            host: uri.host == '127.0.0.1' || uri.host == 'localhost'
                ? host
                : uri.host,
          )
          .toString();
      return FollowerEndpoint(vmServiceUri: published, station: station);
    } on Object {
      await _cleanupAfterLaunchFailure();
      rethrow;
    }
  }

  String _launchCommand(LaunchSpec spec) {
    String ps(String value) => "'${value.replaceAll("'", "''")}'";
    final example = '$repository/packages/butane_windows/example';
    final flutterArgs = <String>[
      'run',
      '-d',
      'windows',
      '--profile',
      '--dart-define=BUTANE_ROLE=${spec.role}',
      '--dart-define=BUTANE_SCENARIO=${spec.scenario}',
    ].map(ps).join(',');
    final script =
        r"$ErrorActionPreference='Stop'; "
        'Set-Location ${ps(example)}; '
        r"$out=[IO.Path]::GetTempFileName(); $err=[IO.Path]::GetTempFileName(); "
        r"$p=Start-Process -FilePath "
        '${ps(flutterExecutable)} -ArgumentList $flutterArgs '
        r"-RedirectStandardOutput $out -RedirectStandardError $err -PassThru; "
        r'Write-Output "GRID_REMOTE_PID=$($p.Id)"; '
        r"$positions=@{ $out=0; $err=0 }; do { "
        r"foreach($f in @($out,$err)) { $lines=@(Get-Content $f); "
        r"for($i=$positions[$f]; $i -lt $lines.Count; $i++) { $lines[$i] }; "
        r"$positions[$f]=$lines.Count }; if(-not $p.HasExited) { "
        r"Start-Sleep -Milliseconds 100 } } while(-not $p.HasExited); "
        r"$p.WaitForExit(); foreach($f in @($out,$err)) { "
        r"$lines=@(Get-Content $f); for($i=$positions[$f]; "
        r"$i -lt $lines.Count; $i++) { $lines[$i] } }; exit $p.ExitCode";
    return 'powershell.exe -NoProfile -NonInteractive -Command ${ps(script)}';
  }

  Future<void> _cleanupAfterLaunchFailure() async {
    final pid = _remotePid;
    if (pid != null) await _taskkill(pid);
  }

  Future<void> _taskkill(int pid) async {
    _remotePid = null;
    final process = await _starter('ssh', [
      ..._sshOptions,
      host,
      'taskkill /F /T /PID $pid',
    ]);
    final code = await process.exitCode;
    if (code != 0) {
      throw StateError('remote Windows taskkill exited with code $code');
    }
    _onLog('teardown-receipt: remote windows host reaped $pid');
  }

  @override
  Future<void> teardown() async {
    if (_teardownStarted) return;
    _teardownStarted = true;
    final pid = _remotePid;
    if (pid != null) await _taskkill(pid);
  }
}
