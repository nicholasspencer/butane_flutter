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
///     `LeonardBinding` (kProfileMode). `flutter run` errors on ATTACH (see
///     #3) but the app launches and stays alive.
///  2. **The VM-service URI is not on flutter's stdout** (attach failed), so
///     we discover the device endpoint over mDNS (`dns-sd`), curl-verifying
///     it because mDNS serves stale records after a relaunch.
///  3. **macOS Local Network TCC blocks the Dart toolchain** from dialing the
///     device over the LAN (curl / `python3` are exempt; `dart` /
///     `leonard_drive` get EHOSTUNREACH). So we run a loopback TCP relay under
///     the exempt `python3` and publish `ws://127.0.0.1:<relayPort>/…` — which
///     the burn host's `leonard_drive` reaches without any Local Network
///     grant. (This assumes the burn HOST runs on the same Mac the device is
///     tethered to — the realistic iOS topology.)
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

import 'follower.dart';

void _noLog(String _) {}

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
  /// [bundleId] is the harness app id looked up over mDNS; [wsPort] is the
  /// harness WS control-plane dart-define; [relayPort] is the loopback port
  /// the Dart-reachable endpoint binds (distinct per concurrent follower).
  IosFollowerLauncher({
    required this.deviceId,
    required this.harnessDirectory,
    this.station = 'butane-ios-follower',
    this.bundleId = 'com.nicospencer.butaneHarness',
    this.wsPort = 19100,
    this.relayPort = 50999,
    this.flutterExecutable = 'flutter',
    this.python3 = '/usr/bin/python3',
    this.readyTimeout = const Duration(minutes: 4),
    ProcessGroupController processes = const SystemProcessGroupController(),
    void Function(String)? onLog,
  })  : _processes = processes,
        _onLog = onLog ?? _noLog;

  /// The target device UDID (`flutter run -d`).
  final String deviceId;

  /// The butane_harness package directory (`flutter run` cwd).
  final String harnessDirectory;

  /// The station id stamped on the published endpoint.
  final String station;

  /// The harness app bundle id (mDNS `_dartVmService._tcp` instance name).
  final String bundleId;

  /// The harness WS control-plane port (dart-define).
  final int wsPort;

  /// The loopback port the published (Dart-reachable) endpoint binds.
  final int relayPort;

  /// The flutter tool.
  final String flutterExecutable;

  /// The LAN-exempt python interpreter that runs the relay.
  final String python3;

  /// Bounds the wait for a device VM service + a live relay (a profile build
  /// + install over wireless can be slow).
  final Duration readyTimeout;

  final ProcessGroupController _processes;
  final void Function(String) _onLog;

  LaunchedDaemon? _last;

  /// The most recently launched daemon (teardown-of-last-resort in tests).
  LaunchedDaemon? get lastLaunched => _last;

  @override
  Future<LaunchedDaemon> launch(LaunchSpec spec) async {
    final role = spec.role.isEmpty ? 'peripheral' : spec.role;

    // Terminate any prior instance of THIS app first: a leftover harness stays
    // exploration-ready until the fresh `flutter run` foregrounds its own app
    // and backgrounds the leftover — a race that hands the drive a
    // soon-to-be-suspended app. Scoped to the bundle's install container so a
    // co-installed Flutter app (also `Runner`) is never touched.
    await _terminateExisting();

    _onLog('ios launcher: flutter run --profile -d $deviceId (ROLE=$role)');

    // `flutter run --profile`: launches + holds a profile app (survives the
    // JIT-less standalone constraint). New session/group so the reaper can
    // signal it. It errors on attach (Local Network) but the app comes up.
    final flutter = await Process.start(
      flutterExecutable,
      <String>[
        'run',
        '--profile',
        '-d',
        deviceId,
        '--dart-define=ROLE=$role',
        '--dart-define=WS_PORT=$wsPort',
      ],
      workingDirectory: harnessDirectory,
      mode: ProcessStartMode.detachedWithStdio,
    );
    // Drain flutter's stdio so it never blocks on a full pipe; surface lines.
    for (final s in [flutter.stdout, flutter.stderr]) {
      s.listen(
        (bytes) {
          final line = String.fromCharCodes(bytes).trim();
          if (line.isNotEmpty) _onLog('  flutter: ${line.split('\n').last}');
        },
        onError: (Object _) {},
        cancelOnError: false,
      );
    }

    final deadline = DateTime.now().add(readyTimeout);
    Process? relay;
    try {
      // Discover a curl-reachable device endpoint (mDNS is stale-prone → verify).
      final device = await _discoverReachable(deadline);
      _onLog('ios launcher: device VM at ${device.ip}:${device.port}');

      // Stand up the loopback relay under the exempt python3.
      relay = await _startRelay(device);
      final endpointUri = 'ws://127.0.0.1:$relayPort/${device.authCode}/ws';

      final pgid = await _processes.resolvePgid(flutter.pid) ?? flutter.pid;
      final relayPid = relay.pid;
      _onLog(
        'ios launcher: flutter pid ${flutter.pid} (pgid $pgid), relay pid '
        '$relayPid; published $endpointUri',
      );
      return _last = LaunchedDaemon(
        pid: flutter.pid,
        pgid: pgid,
        endpoint: FollowerEndpoint(vmServiceUri: endpointUri, station: station),
        onReap: () async {
          Process.killPid(relayPid, ProcessSignal.sigkill);
          // Best-effort on-device terminate (the app else backgrounds/suspends).
          try {
            await Process.run('xcrun', [
              'devicectl',
              'device',
              'process',
              'terminate',
              '--device',
              deviceId,
              '--bundle-id',
              bundleId,
            ]).timeout(const Duration(seconds: 20));
          } on Object {
            // devicectl verb/availability varies; the app suspends regardless.
          }
        },
      );
    } on Object {
      // Ready never arrived: reap what we started so nothing leaks.
      relay?.kill(ProcessSignal.sigkill);
      Process.killPid(flutter.pid, ProcessSignal.sigkill);
      rethrow;
    }
  }

  /// Polls mDNS for the device VM service and returns the endpoint whose
  /// **exploration host is actively registered** — the gate that uniquely
  /// picks the FRESH FOREGROUND app: mDNS keeps serving dead/stale records
  /// (an old port after a relaunch, a suspended prior app), and even a fresh
  /// app answers `getVM` before `ext.exploration.*` registers. A suspended
  /// iOS app tears its service extensions down (handshake → -32601), so
  /// "handshake is registered" is exactly the readiness + freshness signal.
  Future<_DeviceEndpoint> _discoverReachable(DateTime deadline) async {
    while (DateTime.now().isBefore(deadline)) {
      final candidates = await _resolveCandidates();
      for (final c in candidates) {
        if (await _explorationReady('http://${c.ip}:${c.port}/${c.authCode}')) {
          return c;
        }
      }
      if (candidates.isNotEmpty) {
        _onLog('ios launcher: ${candidates.length} mDNS record(s), none '
            'exploration-ready yet — retrying');
      }
      await Future<void>.delayed(const Duration(seconds: 3));
    }
    throw StateError(
      'ios launcher: no exploration-ready device VM service for $bundleId '
      'within ${readyTimeout.inSeconds}s (device unlocked? app foreground?)',
    );
  }

  /// One mDNS resolve → ALL advertised (port, authCode) records (a relaunch
  /// leaves the old SRV cached alongside the new), each paired with the
  /// device IPv4. The caller probes each for exploration-readiness.
  Future<List<_DeviceEndpoint>> _resolveCandidates() async {
    final l = await _boundedOutput(
      'dns-sd',
      ['-L', bundleId, '_dartVmService._tcp', 'local.'],
      const Duration(seconds: 3),
    );
    // Each resolution is "reached at HOST:PORT …" followed by its
    // "authCode=…" TXT line; pair each port with the authCode that follows.
    final pairs = RegExp(r'reached at (\S+):(\d+)[\s\S]*?authCode=(\S+)')
        .allMatches(l)
        .toList();
    if (pairs.isEmpty) return const [];
    final host = pairs.first.group(1)!;
    final g = await _boundedOutput(
      'dns-sd',
      ['-G', 'v4', host],
      const Duration(seconds: 3),
    );
    final ip = RegExp(r'(\d+\.\d+\.\d+\.\d+)').firstMatch(g)?.group(1);
    if (ip == null) return const [];
    // De-dup by port, newest last (later records supersede).
    final byPort = <int, _DeviceEndpoint>{};
    for (final m in pairs) {
      final port = int.parse(m.group(2)!);
      byPort[port] = _DeviceEndpoint(ip: ip, port: port, authCode: m.group(3)!);
    }
    return byPort.values.toList();
  }

  /// Whether the butane exploration host is registered at [base]
  /// (`http://ip:port/auth`). Service extensions are NOT callable over a bare
  /// HTTP GET (they need the isolate + WS routing), so the readiness signal
  /// is the isolate's `extensionRPCs` list: getVM → first isolate id →
  /// getIsolate → the registered method names include `ext.exploration.butane`.
  /// This is what distinguishes the FRESH FOREGROUND harness (methods
  /// registered) from a stale/suspended one (methods torn down) and from a
  /// mid-boot app (VM up, not yet registered).
  Future<bool> _explorationReady(String base) async {
    final vm = await _curlBody('$base/getVM');
    // The VM service escapes the slash in JSON: `"id":"isolates\/1234"` — so
    // match an optional backslash and capture just the number. Check every
    // isolate (the exploration host is on the root isolate, usually first).
    final ids = RegExp(r'"id"\s*:\s*"isolates\\?/(\d+)"')
        .allMatches(vm)
        .map((m) => m.group(1)!)
        .toSet();
    for (final id in ids) {
      final isolate =
          await _curlBody('$base/getIsolate?isolateId=isolates/$id');
      if (isolate.contains('ext.exploration.butane')) return true;
    }
    return false;
  }

  Future<String> _curlBody(String url) async {
    final r = await Process.run('curl', ['-s', '-m', '4', url]);
    return '${r.stdout}';
  }

  /// Best-effort: terminate any running instance of [bundleId]. Maps the
  /// bundle → its install-container UUID (`devicectl device info apps`), then
  /// terminates every process whose executable lives under that container
  /// (`devicectl device info processes`) — so a co-installed Flutter app
  /// (also named `Runner`) is never signalled.
  Future<void> _terminateExisting() async {
    try {
      final apps = _decodeList(
        await _devicectlJson(['device', 'info', 'apps']),
        'apps',
      );
      final url = apps
          .cast<Map<String, Object?>>()
          .firstWhere(
            (a) => a['bundleIdentifier'] == bundleId,
            orElse: () => const {},
          )['url'] as String?;
      final uuid =
          RegExp(r'Application/([0-9A-Fa-f-]+)/').firstMatch(url ?? '')?.group(1);
      if (uuid == null) return; // not installed / not found — nothing to reap

      final procs = _decodeList(
        await _devicectlJson(['device', 'info', 'processes']),
        'runningProcesses',
      );
      for (final p in procs.cast<Map<String, Object?>>()) {
        final exec = '${p['executable']}';
        if (!exec.contains('Application/$uuid/')) continue;
        final pid = p['processIdentifier'];
        _onLog('ios launcher: terminating prior harness pid $pid');
        await Process.run('xcrun', [
          'devicectl', 'device', 'process', 'terminate',
          '--device', deviceId, '--pid', '$pid',
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
  Future<String> _devicectlJson(List<String> args) async {
    final out = File(
      '${Directory.systemTemp.path}/butane_devicectl_$relayPort.json',
    );
    await Process.run('xcrun', [
      'devicectl',
      ...args,
      '--device',
      deviceId,
      '--json-output',
      out.path,
    ]).timeout(const Duration(seconds: 30));
    return out.existsSync() ? out.readAsStringSync() : '';
  }

  /// Writes the embedded relay to a temp file and starts it under python3,
  /// waiting for its RELAY_READY line, then curl-verifying the loopback.
  Future<Process> _startRelay(_DeviceEndpoint device) async {
    final scriptFile = File(
      '${Directory.systemTemp.path}/butane_vm_relay_$relayPort.py',
    )..writeAsStringSync(_kRelayScript);
    final relay = await Process.start(
      python3,
      [scriptFile.path, '$relayPort', device.ip, '${device.port}'],
    );
    final ready = Completer<void>();
    relay.stdout.listen((bytes) {
      if (String.fromCharCodes(bytes).contains('RELAY_READY') &&
          !ready.isCompleted) {
        ready.complete();
      }
    }, onError: (Object _) {}, cancelOnError: false);
    relay.stderr.listen((_) {}, onError: (Object _) {}, cancelOnError: false);
    await ready.future.timeout(const Duration(seconds: 10));

    // Confirm the Dart-reachable loopback actually serves the exploration
    // host (not just any TCP forward).
    if (!await _explorationReady('http://127.0.0.1:$relayPort/${device.authCode}')) {
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

/// A resolved, reachable device VM-service endpoint.
class _DeviceEndpoint {
  const _DeviceEndpoint({
    required this.ip,
    required this.port,
    required this.authCode,
  });

  final String ip;
  final int port;
  final String authCode;
}
