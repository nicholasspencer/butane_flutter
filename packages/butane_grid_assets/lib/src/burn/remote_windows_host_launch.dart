/// Remote Windows central harness lifecycle for the resident burn.
library;

import 'dart:async';
import 'dart:convert';
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

/// Shared non-interactive SSH options for Windows host probes and lifecycle.
const List<String> kBurnSshOptions = [
  '-o',
  'BatchMode=yes',
  '-o',
  'ConnectTimeout=15',
];

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
  Process? _logTailProcess;
  bool _teardownStarted = false;

  static const _scheduledTaskName = r'\Butane\InteractiveCentralHarness';
  static const _payloadFileName = 'remote_windows_host_launch.ps1';
  static const _logFileName = 'remote_windows_host_launch.log';

  String get _gridDirectory => '$repository/.grid';
  String get _payloadPath => '$_gridDirectory/$_payloadFileName';
  String get _logPath => '$_gridDirectory/$_logFileName';

  Future<String> _runCheckedSsh(String command, String operation) async {
    final process = await _starter('ssh', [...kBurnSshOptions, host, command]);
    final outputFuture = process.stdout.transform(utf8.decoder).join();
    final errorFuture = process.stderr.transform(utf8.decoder).join();
    final code = await process.exitCode;
    final output = await outputFuture;
    final error = await errorFuture;
    if (code != 0) {
      throw StateError(
        'remote Windows $operation exited with code $code: ${error.trim()}',
      );
    }
    return output;
  }

  // Win32_ComputerSystem.UserName, not quser: quser.exe does not exist on
  // Windows Home editions, while the CIM console-user query answers the same
  // question (who is logged on at the interactive console) on every edition
  // without elevation. Empty output = nobody at the console.
  Future<void> _requireInteractiveSession() async {
    final output = await _runCheckedSsh(
      r'''powershell.exe -NoProfile -NonInteractive -Command "'''
          r'''$user = (Get-CimInstance Win32_ComputerSystem).UserName; '''
          r'''if ([string]::IsNullOrWhiteSpace($user)) { exit 23 }; $user"''',
      'interactive-session query',
    );
    if (output.trim().isEmpty) {
      throw StateError(
        'remote Windows host has no active interactive console session; '
        'log on at the bench before launching the central harness',
      );
    }
  }

  String _payload(LaunchSpec spec) {
    String ps(String value) => "'${value.replaceAll("'", "''")}'";
    final appDirectory = '$repository/packages/${spec.app}';
    final arguments = <String>[
      'run',
      '-d',
      'windows',
      '--profile',
      '--dart-define=BUTANE_ROLE=${spec.role}',
      '--dart-define=BUTANE_SCENARIO=${spec.scenario}',
    ].map(ps).join(', ');
    return '''
\$ErrorActionPreference = 'Stop'
Set-Location ${ps(appDirectory)}
Set-Content -LiteralPath ${ps(_logPath)} -Value "GRID_REMOTE_PID=\$PID"
& ${ps(flutterExecutable)} @($arguments) *>> ${ps(_logPath)}
exit \$LASTEXITCODE
''';
  }

  Future<void> _preparePayload(LaunchSpec spec) async {
    final encoded = base64Encode(utf8.encode(_payload(spec)));
    String ps(String value) => "'${value.replaceAll("'", "''")}'";
    final script =
        r"$ErrorActionPreference='Stop'; "
        'New-Item -ItemType Directory -Force -Path ${ps(_gridDirectory)} '
        '| Out-Null; '
        r'$text=[Text.Encoding]::UTF8.GetString('
        '[Convert]::FromBase64String(${ps(encoded)})); '
        '[IO.File]::WriteAllText(${ps(_payloadPath)}, \$text); '
        'Remove-Item -LiteralPath ${ps(_logPath)} -Force '
        '-ErrorAction SilentlyContinue';
    await _runCheckedSsh(
      'powershell.exe -NoProfile -NonInteractive -Command ${ps(script)}',
      'scheduled-task payload preparation',
    );
  }

  Future<void> _runScheduledTask() => _runCheckedSsh(
    'schtasks /run /tn "$_scheduledTaskName"',
    'scheduled task launch',
  ).then((_) {});

  Future<Process> _startLogTail() async {
    String ps(String value) => "'${value.replaceAll("'", "''")}'";
    final script =
        r"$ErrorActionPreference='Stop'; "
        'while (-not (Test-Path -LiteralPath ${ps(_logPath)})) '
        '{ Start-Sleep -Milliseconds 100 }; '
        'Get-Content -LiteralPath ${ps(_logPath)} -Wait';
    return _starter('ssh', [
      ...kBurnSshOptions,
      host,
      'powershell.exe -NoProfile -NonInteractive -Command ${ps(script)}',
    ]);
  }

  @override
  Future<FollowerEndpoint> launch(LaunchSpec spec) async {
    if (spec.target != 'windows') {
      throw ArgumentError.value(
        spec.target,
        'spec.target',
        'remote Windows host only supports windows',
      );
    }
    try {
      await _requireInteractiveSession();
      await _preparePayload(spec);
      await _runScheduledTask();
      final pidReady = Completer<int>();
      final tail = await _startLogTail();
      _logTailProcess = tail;
      final uriFuture = scrapeVmServiceWsUri(
        tail,
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
      final tailExitFailure = tail.exitCode.then<Object>((code) {
        throw StateError(
          'remote Windows launch-log tail exited with code $code before readiness',
        );
      });
      final values = await Future.wait<Object>([
        Future.any<Object>([pidReady.future, tailExitFailure]),
        Future.any<Object>([uriFuture, tailExitFailure]),
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
        ...kBurnSshOptions,
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

  Future<void> _cleanupAfterLaunchFailure() async {
    await _reapTunnel();
    await _reapLogTail();
    final pid = _remotePid;
    if (pid != null) await _taskkill(pid);
  }

  Future<void> _reapLogTail() async {
    final tail = _logTailProcess;
    if (tail == null) return;
    _logTailProcess = null;
    tail.kill(ProcessSignal.sigkill);
    await tail.exitCode;
    _onLog(
      'teardown-receipt: remote windows launch-log tail reaped ${tail.pid}',
    );
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
      ...kBurnSshOptions,
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
    await _reapLogTail();
    final pid = _remotePid;
    if (pid != null) await _taskkill(pid);
  }
}
