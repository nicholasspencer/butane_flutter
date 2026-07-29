import 'dart:io';

import 'package:grid_runtime/grid_runtime.dart'
    show ProcessGroupController, SystemProcessGroupController;

import 'follower.dart';
import 'launch_scrape.dart';

typedef MacosProcessStarter =
    Future<Process> Function(
      String executable,
      List<String> arguments, {
      String? workingDirectory,
      ProcessStartMode mode,
    });

Future<Process> _startMacosProcess(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  ProcessStartMode mode = ProcessStartMode.normal,
}) => Process.start(
  executable,
  arguments,
  workingDirectory: workingDirectory,
  mode: mode,
);

void _noLog(String _) {}

/// Launches the host's macOS central harness under Flutter profile mode.
final class MacosCentralLauncher implements FollowerLauncher {
  MacosCentralLauncher({
    this.flutterExecutable = 'flutter',
    this.readyTimeout = const Duration(minutes: 2),
    MacosProcessStarter processStarter = _startMacosProcess,
    ProcessGroupController processes = const SystemProcessGroupController(),
    void Function(String)? onLog,
  }) : _processStarter = processStarter,
       _processes = processes,
       _onLog = onLog ?? _noLog;

  final String flutterExecutable;
  final Duration readyTimeout;
  final MacosProcessStarter _processStarter;
  final ProcessGroupController _processes;
  final void Function(String) _onLog;

  @override
  Future<LaunchedDaemon> launch(LaunchSpec spec) async {
    final role = spec.role.isEmpty ? 'central' : spec.role;
    _onLog(
      'macos central: flutter run --profile -d macos '
      '--dart-define=ROLE=$role',
    );
    final process = await _processStarter(
      flutterExecutable,
      <String>['run', '--profile', '-d', 'macos', '--dart-define=ROLE=$role'],
      workingDirectory: spec.harnessDirectory,
      mode: ProcessStartMode.detachedWithStdio,
    );
    try {
      final wsUri = await scrapeVmServiceWsUri(process).timeout(readyTimeout);
      final pgid = await _processes.resolvePgid(process.pid) ?? process.pid;
      return LaunchedDaemon(
        pid: process.pid,
        pgid: pgid,
        endpoint: FollowerEndpoint(
          vmServiceUri: wsUri,
          station: 'macos-central',
        ),
      );
    } on Object {
      Process.killPid(process.pid, ProcessSignal.sigkill);
      rethrow;
    }
  }
}
