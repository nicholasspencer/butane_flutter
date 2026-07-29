import 'dart:io';

import 'package:grid_runtime/grid_runtime.dart'
    show ProcessGroupController, SystemProcessGroupController;

import 'follower.dart';
import 'launch_scrape.dart';

typedef MacosFollowerProcessStarter =
    Future<Process> Function(
      String executable,
      List<String> arguments, {
      String? workingDirectory,
      ProcessStartMode mode,
    });

Future<Process> _startMacosFollowerProcess(
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

/// Launches the host's macOS peripheral harness under Flutter profile mode.
final class MacosFollowerLauncher implements FollowerLauncher {
  MacosFollowerLauncher({
    this.flutterExecutable = 'flutter',
    this.readyTimeout = const Duration(minutes: 2),
    MacosFollowerProcessStarter processStarter = _startMacosFollowerProcess,
    ProcessGroupController processes = const SystemProcessGroupController(),
    void Function(String)? onLog,
  }) : _processStarter = processStarter,
       _processes = processes,
       _onLog = onLog ?? _noLog;

  final String flutterExecutable;
  final Duration readyTimeout;
  final MacosFollowerProcessStarter _processStarter;
  final ProcessGroupController _processes;
  final void Function(String) _onLog;

  @override
  Future<LaunchedDaemon> launch(LaunchSpec spec) async {
    const role = 'peripheral';
    _onLog(
      'macos follower: flutter run --profile -d macos '
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
          station: 'macos-follower',
        ),
      );
    } on Object {
      Process.killPid(process.pid, ProcessSignal.sigkill);
      rethrow;
    }
  }
}
