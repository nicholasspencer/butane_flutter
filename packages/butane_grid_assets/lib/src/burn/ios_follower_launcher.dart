/// The iOS [FollowerLauncher] — launches the butane harness on a physical
/// iOS device and publishes a Dart-reachable VM-service endpoint.
///
/// iOS is fundamentally unlike the desktop path (build + direct-binary launch
/// + stdout sentinel). Three hard constraints, all learned live and encoded
/// here (see the `reference-ios-ble-test-setup` memory):
///
///  1. **A debug iOS build cannot run standalone** ("Cannot create a
///     FlutterEngine instance in debug mode without Flutter tooling"). So we
///     launch with **`flutter run --profile`** — a profile app runs without
///     the JIT tooling attached, keeps the Dart VM service, and installs
///     `LeonardBinding` (kProfileMode).
///  2. **The device VM service is loopback-bound.** Flutter's stdout supplies
///     its mac-side usbmux-forwarded loopback URI, which is the primary
///     endpoint and carries its own authentication code.
///  3. **Wireless-only fallback uses mDNS.** macOS Local Network TCC blocks the
///     Dart toolchain from dialing the device over the LAN, so a LAN-exempt
///     `python3` loopback relay publishes that fallback endpoint.
///
/// Teardown reaps `flutter run`'s process group (the reaper) plus, via the
/// [LaunchedDaemon.onReap] seam, the relay process and a best-effort
/// on-device app terminate.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:grid_runtime/grid_runtime.dart'
    show ProcessGroupController, SystemProcessGroupController;
import 'package:meta/meta.dart';

import 'follower.dart';
import 'launch_scrape.dart';

void _noLog(String _) {}

/// The device and harness directory selected for one iOS launch.
typedef IosLaunchInputs = ({String deviceId, String harnessDirectory});

/// One iOS VM-service endpoint advertised through mDNS.
typedef IosMdnsCandidate = ({String ip, int port, String authCode});

typedef _IosReadyEndpoint = ({String wsUri, Process? relay});

Uri _vmServiceWsToHttpBase(String wsUri) {
  final uri = Uri.parse(wsUri);
  final path = uri.path.endsWith('/ws')
      ? uri.path.substring(0, uri.path.length - 2)
      : uri.path;
  return uri.replace(
    scheme: uri.scheme == 'wss' ? 'https' : 'http',
    path: path,
  );
}

/// Reads one VM-service HTTP [uri].
typedef IosVmServiceGet = Future<String> Function(Uri uri);

/// Starts the long-lived Flutter tool process for one iOS launch.
typedef IosProcessStarter =
    Future<Process> Function(
      String executable,
      List<String> arguments, {
      required String workingDirectory,
      required ProcessStartMode mode,
    });

/// Removes a prior on-device harness instance before a fresh launch.
typedef IosPreLaunchCleanup = Future<void> Function(String deviceId);

Future<Process> _startIosProcess(
  String executable,
  List<String> arguments, {
  required String workingDirectory,
  required ProcessStartMode mode,
}) => Process.start(
  executable,
  arguments,
  workingDirectory: workingDirectory,
  mode: mode,
);

/// Whether the butane exploration extension is registered at [base].
@visibleForTesting
Future<bool> isIosExplorationReady(
  Uri base, {
  IosVmServiceGet get = _curlVmServiceBody,
}) async {
  final vm = await get(base.resolve('getVM'));
  final ids = RegExp(
    r'"id"\s*:\s*"isolates\\?/(\d+)"',
  ).allMatches(vm).map((match) => match.group(1)!).toSet();
  for (final id in ids) {
    final isolateUri = base
        .resolve('getIsolate')
        .replace(
          queryParameters: <String, String>{'isolateId': 'isolates/$id'},
        );
    final isolate = await get(isolateUri);
    if (isolate.contains('ext.exploration.butane')) return true;
  }
  return false;
}

Future<String> _curlVmServiceBody(Uri uri) async {
  final result = await Process.run('curl', <String>[
    '-s',
    '-m',
    '4',
    uri.toString(),
  ]);
  return '${result.stdout}';
}

/// Parses one `dns-sd -L` transcript and its matching `dns-sd -G v4`
/// transcript into every usable address/port combination.
@visibleForTesting
List<IosMdnsCandidate> resolveIosMdnsCandidates({
  required String lookupOutput,
  required String addressOutput,
}) {
  final pairs = RegExp(
    r'reached at (\S+):(\d+)[\s\S]*?authCode=(\S+)',
  ).allMatches(lookupOutput);
  final byPort = <int, ({int port, String authCode})>{};
  for (final match in pairs) {
    final port = int.parse(match.group(2)!);
    byPort[port] = (port: port, authCode: match.group(3)!);
  }

  final addressRow = RegExp(
    r'\bAdd\b\s+\d+\s+\d+\s+\S+\s+'
    r'(\d{1,3}(?:\.\d{1,3}){3})\s+\d+\s*$',
  );
  final addresses = <String>{};
  for (final line in addressOutput.split('\n')) {
    if (line.contains('No Such Record')) continue;
    final address = addressRow.firstMatch(line)?.group(1);
    if (address == null || address == '0.0.0.0') continue;
    final octets = address.split('.').map(int.parse);
    if (octets.any((octet) => octet > 255)) continue;
    addresses.add(address);
  }

  return <IosMdnsCandidate>[
    for (final pair in byPort.values)
      for (final ip in addresses)
        (ip: ip, port: pair.port, authCode: pair.authCode),
  ];
}

/// The loopback relay, run by the LAN-exempt `python3`. Written to a temp file
/// at launch so the launcher is self-contained (a Dart relay can't work — it
/// would hit the same Local Network gate).
const String _kRelayScript = r'''
import asyncio, sys
LOCAL_PORT = int(sys.argv[1]); DEVICE = sys.argv[2]; DEVICE_PORT = int(sys.argv[3])
async def pipe(r, w):
    try:
        while not r.at_eof():
            data = await r.read(65536)
            if not data: break
            w.write(data); await w.drain()
    except Exception: pass
    finally:
        try: w.close()
        except Exception: pass
async def handle(cr, cw):
    try:
        ur, uw = await asyncio.open_connection(DEVICE, DEVICE_PORT)
    except Exception as e:
        print(f"upstream connect failed: {e}", flush=True); cw.close(); return
    await asyncio.gather(pipe(cr, uw), pipe(ur, cw))
async def main():
    server = await asyncio.start_server(handle, "127.0.0.1", LOCAL_PORT)
    print(f"RELAY_READY 127.0.0.1:{LOCAL_PORT} -> {DEVICE}:{DEVICE_PORT}", flush=True)
    async with server: await server.serve_forever()
asyncio.run(main())
''';

/// Launches the butane harness on a physical iOS device as a burn follower.
class IosFollowerLauncher implements FollowerLauncher {
  /// Creates a launcher for [deviceId] (the device UDID), running
  /// `flutter run` from [harnessDirectory] and publishing under [station].
  /// Flutter's usbmux-forwarded loopback URI is primary. [bundleId] identifies
  /// the wireless-only mDNS fallback; [relayPort] and [python3] provide its
  /// Dart-reachable loopback relay.
  IosFollowerLauncher({
    this.deviceId = '',
    this.harnessDirectory = '',
    this.station = 'butane-ios-follower',
    this.bundleId = 'com.nicospencer.butaneHarness',
    this.relayPort = 50999,
    this.flutterExecutable = 'flutter',
    this.python3 = '/usr/bin/python3',
    this.provisionTimeout = const Duration(minutes: 1),
    this.launchTimeout = const Duration(minutes: 10),
    this.readyTimeout = const Duration(minutes: 4),
    this.lifecycleTimeout = const Duration(minutes: 12),
    this.forwardedPreferenceWindow = const Duration(seconds: 15),
    ProcessGroupController processes = const SystemProcessGroupController(),
    IosProcessStarter processStarter = _startIosProcess,
    IosPreLaunchCleanup? preLaunchCleanup,
    Future<bool> Function(Uri)? explorationReadyProbe,
    Future<List<IosMdnsCandidate>> Function()? mdnsCandidateResolver,
    Future<Process> Function(IosMdnsCandidate)? relayStarter,
    void Function(String)? onLog,
  }) : _processes = processes,
       _processStarter = processStarter,
       _preLaunchCleanup = preLaunchCleanup,
       _explorationReadyProbe = explorationReadyProbe ?? isIosExplorationReady,
       _mdnsCandidateResolver = mdnsCandidateResolver,
       _relayStarter = relayStarter,
       _onLog = onLog ?? _noLog;

  /// The target device UDID (`flutter run -d`).
  final String deviceId;

  /// The butane_harness package directory (`flutter run` cwd).
  final String harnessDirectory;

  /// The station id stamped on the published endpoint.
  final String station;

  /// The harness app bundle id (mDNS `_dartVmService._tcp` instance name).
  final String bundleId;

  /// The loopback port the wireless-only fallback relay binds.
  final int relayPort;

  /// The flutter tool.
  final String flutterExecutable;

  /// The LAN-exempt python interpreter that runs the wireless fallback relay.
  final String python3;

  /// Maximum duration of prior-app cleanup.
  final Duration provisionTimeout;

  /// Maximum duration from Flutter spawn through endpoint discovery.
  final Duration launchTimeout;

  /// Maximum duration of one exploration-readiness probe or relay start.
  final Duration readyTimeout;

  /// Hard bound for the complete iOS launcher lifecycle.
  final Duration lifecycleTimeout;

  /// How long endpoint discovery waits for Flutter's forwarded URI before
  /// falling back to wireless mDNS discovery.
  final Duration forwardedPreferenceWindow;

  final ProcessGroupController _processes;
  final IosProcessStarter _processStarter;
  final IosPreLaunchCleanup? _preLaunchCleanup;
  final Future<bool> Function(Uri) _explorationReadyProbe;
  final Future<List<IosMdnsCandidate>> Function()? _mdnsCandidateResolver;
  final Future<Process> Function(IosMdnsCandidate)? _relayStarter;
  final void Function(String) _onLog;

  LaunchedDaemon? _last;

  /// The most recently launched daemon (teardown-of-last-resort in tests).
  LaunchedDaemon? get lastLaunched => _last;

  /// Resolves ORDER-carried inputs ahead of constructor compatibility inputs.
  @visibleForTesting
  IosLaunchInputs resolveIosLaunchInputs(LaunchSpec spec) {
    final resolvedDeviceId = spec.followerDevice.trim().isNotEmpty
        ? spec.followerDevice.trim()
        : deviceId.trim();
    final resolvedHarnessDirectory = spec.harnessDirectory.trim().isNotEmpty
        ? spec.harnessDirectory.trim()
        : harnessDirectory.trim();
    if (resolvedDeviceId.isEmpty) {
      throw StateError(
        'iOS burn follower requires burn.follower_device '
        '(or compatibility deviceId)',
      );
    }
    if (resolvedHarnessDirectory.isEmpty) {
      throw StateError(
        'iOS burn follower requires burn.harness_dir '
        '(or compatibility harnessDirectory)',
      );
    }
    return (
      deviceId: resolvedDeviceId,
      harnessDirectory: resolvedHarnessDirectory,
    );
  }

  @override
  Future<LaunchedDaemon> launch(LaunchSpec spec) =>
      _phase<LaunchedDaemon>('lifecycle', lifecycleTimeout, _launch(spec));

  Future<LaunchedDaemon> _launch(LaunchSpec spec) async {
    final inputs = resolveIosLaunchInputs(spec);
    final resolvedDeviceId = inputs.deviceId;
    final resolvedHarnessDirectory = inputs.harnessDirectory;
    final role = spec.role.isEmpty ? 'peripheral' : spec.role;

    // Terminate any prior instance of THIS app first: a leftover harness stays
    // exploration-ready until the fresh `flutter run` foregrounds its own app
    // and backgrounds the leftover — a race that hands the drive a
    // soon-to-be-suspended app. Scoped to the bundle's install container so a
    // co-installed Flutter app (also `Runner`) is never touched.
    await _provision(resolvedDeviceId);

    _onLog(
      'ios launcher: flutter run --profile -d $resolvedDeviceId (ROLE=$role)',
    );

    // `flutter run --profile`: launches + holds a profile app (survives the
    // JIT-less standalone constraint). New session/group so the reaper can
    // signal it. It errors on attach (Local Network) but the app comes up.
    final flutter = await _phase<Process>(
      'install+launch',
      launchTimeout,
      _processStarter(
        flutterExecutable,
        <String>[
          'run',
          '--profile',
          '-d',
          resolvedDeviceId,
          '--dart-define=ROLE=$role',
        ],
        workingDirectory: resolvedHarnessDirectory,
        mode: ProcessStartMode.detachedWithStdio,
      ),
    );
    final forwarded = Completer<String>();
    final flutterOutput = StringBuffer();
    final flutterOutputTail = <String>[];
    void rememberAndScrape(String line) {
      _rememberOutput(flutterOutputTail, line);
      flutterOutput.writeln(line);
      final uri = flutterForwardedVmServiceWsUri(flutterOutput.toString());
      if (uri != null && !forwarded.isCompleted) {
        forwarded.complete(uri);
      }
    }

    final stdoutSubscription = flutter.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(rememberAndScrape, cancelOnError: false);
    final stderrSubscription = flutter.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(rememberAndScrape, cancelOnError: false);
    final stdoutDone = stdoutSubscription.asFuture<void>();
    final stderrDone = stderrSubscription.asFuture<void>();
    final flutterStreamsDone = Future.wait<void>([stdoutDone, stderrDone]);

    Process? relay;
    try {
      final ready = await _phase<_IosReadyEndpoint>(
        'install+launch',
        launchTimeout,
        Future.any<_IosReadyEndpoint>([
          _discoverEndpoint(DateTime.now().add(launchTimeout), forwarded),
          _flutterExitFailure(flutterStreamsDone, flutterOutputTail),
        ]),
      );
      relay = ready.relay;
      final endpointUri = ready.wsUri;

      final pgid = await _processes.resolvePgid(flutter.pid) ?? flutter.pid;
      final relayPid = relay?.pid;
      _onLog(
        'ios launcher: flutter pid ${flutter.pid} (pgid $pgid)'
        '${relayPid == null ? '' : ', relay pid $relayPid'}; '
        'published $endpointUri',
      );
      return _last = LaunchedDaemon(
        pid: flutter.pid,
        pgid: pgid,
        endpoint: FollowerEndpoint(vmServiceUri: endpointUri, station: station),
        exited: flutterStreamsDone,
        onReap: () async {
          if (relayPid != null) {
            Process.killPid(relayPid, ProcessSignal.sigkill);
          }
          // Best-effort on-device terminate (the app else backgrounds/suspends).
          try {
            await Process.run('xcrun', [
              'devicectl',
              'device',
              'process',
              'terminate',
              '--device',
              resolvedDeviceId,
              '--bundle-id',
              bundleId,
            ]).timeout(const Duration(seconds: 20));
          } on Object {
            // devicectl verb/availability varies; the app suspends regardless.
          }
        },
      );
    } on Object catch (error, stack) {
      // Ready never arrived: reap what we started so nothing leaks.
      relay?.kill(ProcessSignal.sigkill);
      await _reapFailedFlutter(flutter, flutterStreamsDone);
      Error.throwWithStackTrace(error, stack);
    }
  }

  Future<T> _phase<T>(String name, Duration timeout, Future<T> future) =>
      future.timeout(
        timeout,
        onTimeout: () => throw TimeoutException(
          'ios launcher: $name timed out after ${timeout.inMilliseconds}ms',
          timeout,
        ),
      );

  Future<void> _provision(String resolvedDeviceId) => _phase<void>(
    'provision',
    provisionTimeout,
    _preLaunchCleanup?.call(resolvedDeviceId) ??
        _terminateExisting(resolvedDeviceId),
  );

  Future<Never> _flutterExitFailure(
    Future<void> flutterStreamsDone,
    List<String> outputTail,
  ) async {
    await flutterStreamsDone;
    throw StateError(
      'ios launcher: flutter exited before readiness\n'
      'output tail:\n${outputTail.join('\n')}',
    );
  }

  void _rememberOutput(List<String> tail, String line) {
    if (line.trim().isEmpty) return;
    _onLog('  flutter: $line');
    tail.add(line);
    if (tail.length > 40) tail.removeAt(0);
  }

  Future<void> _reapFailedFlutter(
    Process flutter,
    Future<void> flutterStreamsDone,
  ) async {
    Process.killPid(flutter.pid, ProcessSignal.sigkill);
    try {
      await flutterStreamsDone.timeout(const Duration(seconds: 2));
    } on Object {
      _onLog('ios launcher: flutter pid ${flutter.pid} reap did not confirm');
    }
  }

  /// Prefers flutter's usbmux-forwarded endpoint, then tries wireless mDNS.
  Future<_IosReadyEndpoint> _discoverEndpoint(
    DateTime deadline,
    Completer<String> forwarded,
  ) async {
    final preferenceDeadline = DateTime.now().add(forwardedPreferenceWindow);
    while (!forwarded.isCompleted &&
        DateTime.now().isBefore(deadline) &&
        DateTime.now().isBefore(preferenceDeadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }

    while (DateTime.now().isBefore(deadline)) {
      if (forwarded.isCompleted) {
        final wsUri = await forwarded.future;
        final explorationReady = await _phase<bool>(
          'readiness',
          readyTimeout,
          _explorationReadyProbe(_vmServiceWsToHttpBase(wsUri)),
        );
        if (explorationReady) {
          return (wsUri: wsUri, relay: null);
        }
      }
      final candidates =
          await (_mdnsCandidateResolver?.call() ?? _resolveCandidates());
      for (final candidate in candidates) {
        final base = Uri.parse(
          'http://${candidate.ip}:${candidate.port}/${candidate.authCode}/',
        );
        final explorationReady = await _phase<bool>(
          'readiness',
          readyTimeout,
          _explorationReadyProbe(base),
        );
        if (explorationReady) {
          final relay = await _phase<Process>(
            'readiness',
            readyTimeout,
            _relayStarter?.call(candidate) ?? _startRelay(candidate),
          );
          return (
            wsUri: 'ws://127.0.0.1:$relayPort/${candidate.authCode}/ws',
            relay: relay,
          );
        }
      }
      if (candidates.isNotEmpty) {
        _onLog(
          'ios launcher: ${candidates.length} mDNS record(s), none '
          'exploration-ready yet — retrying',
        );
      }
      await Future<void>.delayed(const Duration(seconds: 3));
    }
    throw StateError(
      'ios launcher: no exploration-ready VM service for $bundleId '
      'within ${readyTimeout.inSeconds}s (device unlocked? app foreground?)',
    );
  }

  /// One mDNS resolve → ALL advertised (port, authCode) records (a relaunch
  /// leaves the old SRV cached alongside the new), each paired with the
  /// device IPv4 addresses. The caller probes each for exploration-readiness.
  Future<List<IosMdnsCandidate>> _resolveCandidates() async {
    final lookupOutput = await _boundedOutput('dns-sd', [
      '-L',
      bundleId,
      '_dartVmService._tcp',
      'local.',
    ], const Duration(seconds: 3));
    final host = RegExp(
      r'reached at (\S+):\d+',
    ).firstMatch(lookupOutput)?.group(1);
    if (host == null) return const [];
    final addressOutput = await _boundedOutput('dns-sd', [
      '-G',
      'v4',
      host,
    ], const Duration(seconds: 3));
    return resolveIosMdnsCandidates(
      lookupOutput: lookupOutput,
      addressOutput: addressOutput,
    );
  }

  /// Best-effort: terminate any running instance of [bundleId]. Maps the
  /// bundle → its install-container UUID (`devicectl device info apps`), then
  /// terminates every process whose executable lives under that container
  /// (`devicectl device info processes`) — so a co-installed Flutter app
  /// (also named `Runner`) is never signalled.
  Future<void> _terminateExisting(String resolvedDeviceId) async {
    try {
      final apps = _decodeList(
        await _devicectlJson(['device', 'info', 'apps'], resolvedDeviceId),
        'apps',
      );
      final url =
          apps.cast<Map<String, Object?>>().firstWhere(
                (a) => a['bundleIdentifier'] == bundleId,
                orElse: () => const {},
              )['url']
              as String?;
      final uuid = RegExp(
        r'Application/([0-9A-Fa-f-]+)/',
      ).firstMatch(url ?? '')?.group(1);
      if (uuid == null) return; // not installed / not found — nothing to reap

      final procs = _decodeList(
        await _devicectlJson(['device', 'info', 'processes'], resolvedDeviceId),
        'runningProcesses',
      );
      for (final p in procs.cast<Map<String, Object?>>()) {
        final exec = '${p['executable']}';
        if (!exec.contains('Application/$uuid/')) continue;
        final pid = p['processIdentifier'];
        _onLog('ios launcher: terminating prior harness pid $pid');
        await Process.run('xcrun', [
          'devicectl',
          'device',
          'process',
          'terminate',
          '--device',
          resolvedDeviceId,
          '--pid',
          '$pid',
        ]).timeout(const Duration(seconds: 15));
      }
    } on Object catch (e) {
      _onLog('ios launcher: pre-launch cleanup skipped: $e');
    }
  }

  List<Object?> _decodeList(String json, String key) {
    if (json.isEmpty) return const [];
    final result = (jsonDecode(json) as Map<String, Object?>)['result'];
    final list = (result as Map<String, Object?>?)?[key];
    return list is List ? list : const [];
  }

  /// Runs `xcrun devicectl <args> --json-output <tmp>` and returns the JSON.
  Future<String> _devicectlJson(
    List<String> args,
    String resolvedDeviceId,
  ) async {
    final out = File(
      '${Directory.systemTemp.path}/butane_devicectl_$relayPort.json',
    );
    await Process.run('xcrun', [
      'devicectl',
      ...args,
      '--device',
      resolvedDeviceId,
      '--json-output',
      out.path,
    ]).timeout(const Duration(seconds: 30));
    return out.existsSync() ? out.readAsStringSync() : '';
  }

  /// Writes the embedded relay to a temp file and starts it under python3,
  /// waiting for its RELAY_READY line, then curl-verifying the loopback.
  Future<Process> _startRelay(IosMdnsCandidate device) async {
    final scriptFile = File(
      '${Directory.systemTemp.path}/butane_vm_relay_$relayPort.py',
    )..writeAsStringSync(_kRelayScript);
    final relay = await Process.start(python3, [
      scriptFile.path,
      '$relayPort',
      device.ip,
      '${device.port}',
    ]);
    final ready = Completer<void>();
    relay.stdout.listen(
      (bytes) {
        if (String.fromCharCodes(bytes).contains('RELAY_READY') &&
            !ready.isCompleted) {
          ready.complete();
        }
      },
      onError: (Object _) {},
      cancelOnError: false,
    );
    relay.stderr.listen((_) {}, onError: (Object _) {}, cancelOnError: false);
    await ready.future.timeout(const Duration(seconds: 10));

    // Confirm the Dart-reachable loopback actually serves the exploration
    // host (not just any TCP forward).
    final base = Uri.parse('http://127.0.0.1:$relayPort/${device.authCode}/');
    final explorationReady = await _phase<bool>(
      'readiness',
      readyTimeout,
      isIosExplorationReady(base),
    );
    if (!explorationReady) {
      relay.kill(ProcessSignal.sigkill);
      throw StateError('ios launcher: relay loopback not exploration-ready');
    }
    return relay;
  }

  /// Runs [exe] [args] for [window], then SIGTERMs it and returns the output
  /// collected (for the browse-style `dns-sd` calls that never self-exit).
  Future<String> _boundedOutput(
    String exe,
    List<String> args,
    Duration window,
  ) async {
    final p = await Process.start(exe, args);
    final buf = StringBuffer();
    final out = p.stdout.listen((b) => buf.write(String.fromCharCodes(b)));
    final err = p.stderr.listen((_) {});
    await Future<void>.delayed(window);
    p.kill(ProcessSignal.sigterm);
    await out.cancel();
    await err.cancel();
    return buf.toString();
  }
}
