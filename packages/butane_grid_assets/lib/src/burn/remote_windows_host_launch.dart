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

/// Allocates an unused local TCP port for the VM-service tunnel.
typedef LocalPortAllocator = Future<int> Function();

/// Waits until an SSH tunnel is accepting connections on [port].
typedef TunnelReadyWaiter =
    Future<void> Function(int port, Process process, Duration timeout);

void _noLog(String _) {}

Future<int> _allocateLoopbackPort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}

Future<void> _waitForTunnel(int port, Process process, Duration timeout) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    final connected =
        await Socket.connect(
          InternetAddress.loopbackIPv4,
          port,
          timeout: const Duration(milliseconds: 100),
        ).then((socket) async {
          await socket.close();
          return true;
        }, onError: (_) => false);
    if (connected) return;
    final exited = await Future.any<Object?>([
      process.exitCode.then<Object?>((code) => code),
      Future<Object?>.delayed(const Duration(milliseconds: 50)),
    ]);
    if (exited is int) {
      throw StateError('Windows VM-service tunnel exited with code $exited');
    }
  }
  throw TimeoutException('Windows VM-service tunnel was not ready', timeout);
}

/// Launches the central harness on Windows over SSH.
final class RemoteWindowsHostLaunch implements HostHarnessLaunch {
  RemoteWindowsHostLaunch({
    required this.host,
    required this.repository,
    required this.flutterExecutable,
    this.station = 'windows-host',
    this.readyTimeout = const Duration(minutes: 5),
    SshProcessStarter starter = Process.start,
    LocalPortAllocator allocatePort = _allocateLoopbackPort,
    TunnelReadyWaiter waitForTunnelReady = _waitForTunnel,
    void Function(String)? onLog,
  }) : _starter = starter,
       _allocatePort = allocatePort,
       _waitForTunnelReady = waitForTunnelReady,
       _onLog = onLog ?? _noLog;

  final String host;
  final String repository;
  final String flutterExecutable;
  final String station;
  final Duration readyTimeout;
  final SshProcessStarter _starter;
  final LocalPortAllocator _allocatePort;
  final TunnelReadyWaiter _waitForTunnelReady;
  final void Function(String) _onLog;
  int? _remotePid;
  Process? _tunnelProcess;
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
      final remoteUri = Uri.parse(values[1] as String);
      if ((remoteUri.scheme != 'ws' && remoteUri.scheme != 'wss') ||
          (remoteUri.host != '127.0.0.1' && remoteUri.host != 'localhost') ||
          remoteUri.port == 0) {
        throw FormatException(
          'invalid loopback VM service WebSocket URI',
          remoteUri,
        );
      }
      final localPort = await _allocatePort();
      final tunnel = await _starter('ssh', [
        ..._sshOptions,
        '-o',
        'ExitOnForwardFailure=yes',
        '-N',
        '-L',
        '127.0.0.1:$localPort:127.0.0.1:${remoteUri.port}',
        host,
      ]);
      _tunnelProcess = tunnel;
      await _waitForTunnelReady(localPort, tunnel, readyTimeout);
      final published = remoteUri
          .replace(host: '127.0.0.1', port: localPort)
          .toString();
      return FollowerEndpoint(vmServiceUri: published, station: station);
    } on Object {
      await _cleanupAfterLaunchFailure();
      rethrow;
    }
  }

  String _launchCommand(LaunchSpec spec) {
    String ps(String value) => "'${value.replaceAll("'", "''")}'";
    final appDirectory = '$repository/packages/${spec.app}';
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
        'Set-Location ${ps(appDirectory)}; '
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
    await _reapTunnel();
    final pid = _remotePid;
    if (pid != null) await _taskkill(pid);
  }

  Future<void> _reapTunnel() async {
    final tunnel = _tunnelProcess;
    if (tunnel == null) return;
    _tunnelProcess = null;
    tunnel.kill(ProcessSignal.sigkill);
    await tunnel.exitCode;
    _onLog(
      'teardown-receipt: remote windows VM-service tunnel reaped '
      '${tunnel.pid}',
    );
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
    await _reapTunnel();
    final pid = _remotePid;
    if (pid != null) await _taskkill(pid);
  }
}
