import 'dart:io';

import 'burn_preflight.dart';
import 'remote_windows_host_launch.dart' show kBurnSshOptions;
import 'rig.dart' show FlutterDeviceCatalog, ProcessFlutterDeviceCatalog;

/// Runs one process-backed reachability probe and returns its exit code.
typedef BurnProcessProbe =
    Future<int> Function(String executable, List<String> arguments);

/// Attempts one bounded TCP connection.
typedef BurnSocketProbe =
    Future<void> Function(String host, int port, Duration timeout);

Future<int> _runProcess(String executable, List<String> arguments) async =>
    (await Process.run(executable, arguments)).exitCode;

Future<void> _connectSocket(String host, int port, Duration timeout) async {
  final socket = await Socket.connect(host, port, timeout: timeout);
  await socket.close();
}

/// Creates the process-backed preflight used by live burn entry points.
BurnPreflight systemBurnPreflight({
  BurnPathPredicate? directoryExists,
  BurnPathPredicate? fileExists,
  FlutterDeviceCatalog? devices,
  BurnProcessProbe? processProbe,
  BurnSocketProbe? socketProbe,
}) {
  final resolvedProcessProbe = processProbe ?? _runProcess;
  final resolvedSocketProbe = socketProbe ?? _connectSocket;
  return BurnPreflight(
    directoryExists: directoryExists ?? (path) => Directory(path).existsSync(),
    fileExists: fileExists ?? (path) => File(path).existsSync(),
    devices: devices ?? ProcessFlutterDeviceCatalog(),
    hostReachable: (host) async =>
        await resolvedProcessProbe('ssh', [
          ...kBurnSshOptions,
          host,
          'exit 0',
        ]) ==
        0,
    peerReachable: (host, port) async {
      await resolvedSocketProbe(host, port, const Duration(seconds: 3));
      return true;
    },
  );
}
