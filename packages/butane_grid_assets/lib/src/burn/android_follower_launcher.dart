/// Android implementation of the burn follower launcher.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:grid_runtime/grid_runtime.dart'
    show ProcessGroupController, SystemProcessGroupController;

import 'follower.dart';

/// Runs one command and returns its completed result.
typedef AndroidCommandRunner =
    Future<ProcessResult> Function(
      String executable,
      List<String> arguments, {
      String? workingDirectory,
      Duration? timeout,
    });

/// Starts the long-lived logcat process used as the local daemon leader.
typedef AndroidProcessStarter =
    Future<Process> Function(String executable, List<String> arguments);

/// Verifies that a forwarded VM-service WebSocket accepts a connection.
typedef AndroidEndpointProbe = Future<void> Function(Uri uri);

void _noLog(String _) {}

Future<ProcessResult> _runCommand(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  Duration? timeout,
}) {
  final future = Process.run(
    executable,
    arguments,
    workingDirectory: workingDirectory,
  );
  return timeout == null ? future : future.timeout(timeout);
}

Future<Process> _startProcess(String executable, List<String> arguments) =>
    Process.start(
      executable,
      arguments,
      mode: ProcessStartMode.detachedWithStdio,
    );

Future<void> _probeEndpoint(Uri uri) async {
  final socket = await WebSocket.connect(
    uri.toString(),
  ).timeout(const Duration(seconds: 10));
  await socket.close();
}

/// Builds, installs, starts, and publishes the butane harness on Android.
class AndroidFollowerLauncher implements FollowerLauncher {
  /// Creates an Android launcher for [deviceId] and [harnessDirectory].
  AndroidFollowerLauncher({
    required this.deviceId,
    required this.harnessDirectory,
    this.station = 'butane-android-follower',
    this.packageName = 'com.nicospencer.butane_harness',
    this.activityName = '.MainActivity',
    this.flutterExecutable = 'flutter',
    this.adbExecutable = 'adb',
    this.buildTimeout = const Duration(minutes: 10),
    this.readyTimeout = const Duration(minutes: 2),
    ProcessGroupController processes = const SystemProcessGroupController(),
    AndroidCommandRunner commandRunner = _runCommand,
    AndroidProcessStarter processStarter = _startProcess,
    AndroidEndpointProbe endpointProbe = _probeEndpoint,
    void Function(String)? onLog,
  }) : _processes = processes,
       _commandRunner = commandRunner,
       _processStarter = processStarter,
       _endpointProbe = endpointProbe,
       _onLog = onLog ?? _noLog;

  /// The selected adb device serial.
  final String deviceId;

  /// The butane harness package directory.
  final String harnessDirectory;

  /// The station id stamped on the published endpoint.
  final String station;

  /// The installed Android application id.
  final String packageName;

  /// The activity component relative to [packageName].
  final String activityName;

  /// The Flutter executable used to build the profile APK.
  final String flutterExecutable;

  /// The adb executable used for device operations.
  final String adbExecutable;

  /// Maximum duration of the profile APK build.
  final Duration buildTimeout;

  /// Maximum duration of readiness discovery and endpoint probing.
  final Duration readyTimeout;

  final ProcessGroupController _processes;
  final AndroidCommandRunner _commandRunner;
  final AndroidProcessStarter _processStarter;
  final AndroidEndpointProbe _endpointProbe;
  final void Function(String) _onLog;
  LaunchedDaemon? _last;

  /// The most recently launched daemon, or null before a successful launch.
  LaunchedDaemon? get lastLaunched => _last;

  @override
  Future<LaunchedDaemon> launch(LaunchSpec spec) async {
    if (spec.target != 'android') {
      throw ArgumentError.value(spec.target, 'spec.target', 'must be android');
    }
    final role = spec.role.isEmpty ? 'peripheral' : spec.role;
    await _checked(
      flutterExecutable,
      ['build', 'apk', '--profile', '--dart-define=ROLE=$role'],
      workingDirectory: harnessDirectory,
      timeout: buildTimeout,
    );
    final apk = File(
      '$harnessDirectory/build/app/outputs/flutter-apk/app-profile.apk',
    );
    if (!apk.existsSync()) {
      throw StateError('profile APK missing at ${apk.path}');
    }

    await _bestEffortForceStop();
    await _checked(adbExecutable, _adb(['install', '-r', apk.path]));
    final sdkResult = await _checked(
      adbExecutable,
      _adb(['shell', 'getprop', 'ro.build.version.sdk']),
    );
    final sdk = int.tryParse('${sdkResult.stdout}'.trim());
    if (sdk == null) {
      throw StateError('adb returned invalid Android SDK: ${sdkResult.stdout}');
    }
    final permissions = sdk >= 31
        ? const [
            'android.permission.BLUETOOTH_SCAN',
            'android.permission.BLUETOOTH_CONNECT',
            'android.permission.BLUETOOTH_ADVERTISE',
          ]
        : const ['android.permission.ACCESS_FINE_LOCATION'];
    for (final permission in permissions) {
      await _checked(
        adbExecutable,
        _adb(['shell', 'pm', 'grant', packageName, permission]),
      );
    }

    await _checked(adbExecutable, _adb(['logcat', '-c']));
    Process? logcat;
    int? localPort;
    try {
      logcat = await _processStarter(
        adbExecutable,
        _adb(['logcat', '-v', 'raw', 'flutter:I', '*:S']),
      );
      final serviceFuture = _scrapeGridVmUri(logcat);
      await _checked(
        adbExecutable,
        _adb(['shell', 'am', 'start', '-n', '$packageName/$activityName']),
      );
      final deviceUri = await serviceFuture.timeout(readyTimeout);
      if (deviceUri.scheme != 'ws' && deviceUri.scheme != 'wss') {
        throw FormatException('GRID_VM_URI is not WebSocket: $deviceUri');
      }
      if (deviceUri.port == 0) {
        throw FormatException('GRID_VM_URI has no device port: $deviceUri');
      }
      localPort = await _reserveLoopbackPort();
      await _checked(
        adbExecutable,
        _adb(['forward', 'tcp:$localPort', 'tcp:${deviceUri.port}']),
      );
      final forwarded = deviceUri.replace(host: '127.0.0.1', port: localPort);
      await _endpointProbe(forwarded).timeout(readyTimeout);
      final pgid = await _processes.resolvePgid(logcat.pid) ?? logcat.pid;
      final capturedPort = localPort;
      return _last = LaunchedDaemon(
        pid: logcat.pid,
        pgid: pgid,
        endpoint: FollowerEndpoint(
          vmServiceUri: forwarded.toString(),
          station: station,
        ),
        onReap: () async {
          await _bestEffortRemoveForward(capturedPort);
          await _bestEffortForceStop();
        },
      );
    } on Object {
      if (logcat != null) {
        Process.killPid(logcat.pid, ProcessSignal.sigkill);
      }
      if (localPort != null) await _bestEffortRemoveForward(localPort);
      await _bestEffortForceStop();
      rethrow;
    }
  }

  List<String> _adb(List<String> arguments) => ['-s', deviceId, ...arguments];

  Future<ProcessResult> _checked(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Duration? timeout,
  }) async {
    final result = await _commandRunner(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      timeout: timeout,
    );
    if (result.exitCode != 0) {
      throw StateError(
        '$executable ${arguments.join(' ')} exited ${result.exitCode}\n'
        'stdout: ${result.stdout}\nstderr: ${result.stderr}',
      );
    }
    _onLog('android launcher: $executable ${arguments.join(' ')}');
    return result;
  }

  Future<Uri> _scrapeGridVmUri(Process process) {
    final ready = Completer<Uri>();
    void drain(Stream<List<int>> stream) {
      stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            (line) {
              _onLog('  adb: $line');
              if (ready.isCompleted) return;
              final match = RegExp(r'GRID_VM_URI=(\S+)').firstMatch(line);
              if (match == null) return;
              try {
                ready.complete(Uri.parse(match.group(1)!));
              } on Object catch (error, stack) {
                ready.completeError(error, stack);
              }
            },
            onError: (Object error, StackTrace stack) {
              if (!ready.isCompleted) ready.completeError(error, stack);
            },
          );
    }

    drain(process.stdout);
    drain(process.stderr);
    return ready.future;
  }

  Future<int> _reserveLoopbackPort() async {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();
    return port;
  }

  Future<void> _bestEffortRemoveForward(int port) async {
    try {
      await _commandRunner(
        adbExecutable,
        _adb(['forward', '--remove', 'tcp:$port']),
        timeout: const Duration(seconds: 20),
      );
    } on Object {
      // The process-group reap already succeeded; adb cleanup is best-effort.
    }
  }

  Future<void> _bestEffortForceStop() async {
    try {
      await _commandRunner(
        adbExecutable,
        _adb(['shell', 'am', 'force-stop', packageName]),
        timeout: const Duration(seconds: 20),
      );
    } on Object {
      // The device can disconnect during cleanup; release must still finish.
    }
  }
}
