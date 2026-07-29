import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:butane_grid_assets/butane_grid_assets.dart';
import 'package:test/test.dart';

const _spec = LaunchSpec(
  app: 'butane_harness',
  target: 'windows',
  role: 'central',
  scenario: 'smoke',
);

Future<Process> _shell(String script) =>
    Process.start('/bin/sh', ['-c', script]);

bool _isSessionQuery(List<String> arguments) =>
    arguments.last.contains('Win32_ComputerSystem');
bool _isPayloadPreparation(List<String> arguments) =>
    arguments.last.contains('FromBase64String');
bool _isScheduledTaskRun(List<String> arguments) =>
    arguments.last == r'schtasks /run /tn "\Butane\InteractiveCentralHarness"';
bool _isLogTail(List<String> arguments) =>
    arguments.last.contains('Get-Content') && arguments.last.contains('-Wait');
bool _isTunnel(List<String> arguments) => arguments.contains('-N');
bool _isTaskkill(List<String> arguments) =>
    arguments.last.startsWith('taskkill /F /T /PID ');

String _kind(List<String> arguments) {
  if (_isSessionQuery(arguments)) return 'query';
  if (_isPayloadPreparation(arguments)) return 'prepare';
  if (_isScheduledTaskRun(arguments)) return 'task';
  if (_isLogTail(arguments)) return 'tail';
  if (_isTunnel(arguments)) return 'tunnel';
  if (_isTaskkill(arguments)) return 'taskkill';
  return 'unknown';
}

Future<Process> _successfulControl(List<String> arguments) {
  if (_isSessionQuery(arguments)) {
    return _shell("printf 'NICOSPENCER\\\\nicks\\n'");
  }
  if (_isPayloadPreparation(arguments) ||
      _isScheduledTaskRun(arguments) ||
      _isTaskkill(arguments)) {
    return _shell('exit 0');
  }
  throw StateError('unexpected control command: ${arguments.last}');
}

String _decodedPayload(List<String> arguments) {
  final match = RegExp(
    r"FromBase64String\('+([^']+)'+\)",
  ).firstMatch(arguments.last);
  expect(match, isNotNull);
  return utf8.decode(base64Decode(match!.group(1)!));
}

void main() {
  test(
    'tunnels a scheduled-task log URI and reaps owned resources once',
    () async {
      final calls = <List<String>>[];
      final logs = <String>[];
      Process? tailProcess;
      Process? tunnelProcess;
      final launch = RemoteWindowsHostLaunch(
        host: 'yoga-win',
        repository: r'C:/repo',
        flutterExecutable: r'C:/flutter.bat',
        allocatePort: () async => 49152,
        waitForTunnelReady: (port, process, timeout) async {
          expect(port, 49152);
          expect(timeout, const Duration(minutes: 5));
          tunnelProcess = process;
        },
        starter: (executable, arguments) {
          expect(executable, 'ssh');
          calls.add(arguments);
          if (_isLogTail(arguments)) {
            return _shell(
              "printf 'GRID_REMOTE_PID=42\\n"
              "GRID_VM_URI=ws://127.0.0.1:8181/x/ws\\n'; sleep 10",
            ).then((process) {
              tailProcess = process;
              return process;
            });
          }
          if (_isTunnel(arguments)) return _shell('sleep 10');
          return _successfulControl(arguments);
        },
        onLog: logs.add,
      );

      final endpoint = await launch.launch(_spec);
      expect(endpoint.vmServiceUri, 'ws://127.0.0.1:49152/x/ws');
      expect(endpoint.station, 'windows-host');
      expect(calls.take(5).map(_kind), [
        'query',
        'prepare',
        'task',
        'tail',
        'tunnel',
      ]);
      expect(calls[4], [
        '-o',
        'BatchMode=yes',
        '-o',
        'ConnectTimeout=15',
        '-o',
        'ExitOnForwardFailure=yes',
        '-N',
        '-L',
        '127.0.0.1:49152:127.0.0.1:8181',
        'yoga-win',
      ]);
      expect(calls[1].last, contains(r'C:/repo/.grid'));
      expect(calls[1].last, contains(r'remote_windows_host_launch.ps1'));
      expect(calls[1].last, contains(r'remote_windows_host_launch.log'));
      final payload = _decodedPayload(calls[1]);
      expect(payload, contains(r'C:/repo/packages/butane_harness'));
      expect(
        payload,
        contains(r'C:/repo/.grid/remote_windows_host_launch.log'),
      );
      expect(payload, contains(r'C:/flutter.bat'));
      expect(payload, contains('BUTANE_ROLE=central'));
      expect(payload, contains('BUTANE_SCENARIO=smoke'));

      await launch.teardown();
      await launch.teardown();
      expect(await tunnelProcess!.exitCode, isNot(0));
      expect(await tailProcess!.exitCode, isNot(0));
      expect(calls.where(_isTunnel), hasLength(1));
      expect(calls.where(_isLogTail), hasLength(1));
      expect(
        calls.where((a) => a.last == 'taskkill /F /T /PID 42'),
        hasLength(1),
      );
      expect(logs.where((l) => l.contains('tunnel reaped')), hasLength(1));
      expect(
        logs.where((l) => l.contains('launch-log tail reaped')),
        hasLength(1),
      );
      expect(logs, contains('teardown-receipt: remote windows host reaped 42'));
    },
  );

  test('tunnel readiness failure reaps tunnel, tail, and process tree', () async {
    final calls = <List<String>>[];
    Process? tail;
    Process? tunnel;
    final launch = RemoteWindowsHostLaunch(
      host: 'yoga-win',
      repository: 'repo',
      flutterExecutable: 'flutter',
      allocatePort: () async => 49152,
      waitForTunnelReady: (_, process, _) async {
        tunnel = process;
        throw StateError('forward refused');
      },
      starter: (_, arguments) {
        calls.add(arguments);
        if (_isLogTail(arguments)) {
          return _shell(
            "printf 'GRID_REMOTE_PID=43\\nGRID_VM_URI=ws://localhost:8181/x/ws\\n'; sleep 10",
          ).then((p) {
            tail = p;
            return p;
          });
        }
        if (_isTunnel(arguments)) return _shell('sleep 10');
        return _successfulControl(arguments);
      },
    );
    await expectLater(launch.launch(_spec), throwsA(isA<StateError>()));
    expect(await tunnel!.exitCode, isNot(0));
    expect(await tail!.exitCode, isNot(0));
    expect(
      calls.where((a) => a.last == 'taskkill /F /T /PID 43'),
      hasLength(1),
    );
  });

  test(
    'refuses a non-loopback URI and cleans the tail and remote tree',
    () async {
      final calls = <List<String>>[];
      Process? tail;
      final launch = RemoteWindowsHostLaunch(
        host: 'yoga-win',
        repository: 'repo',
        flutterExecutable: 'flutter',
        starter: (_, arguments) {
          calls.add(arguments);
          if (_isLogTail(arguments)) {
            return _shell(
              "printf 'GRID_REMOTE_PID=44\\nGRID_VM_URI=ws://yoga-win:8181/x/ws\\n'; sleep 10",
            ).then((p) {
              tail = p;
              return p;
            });
          }
          return _successfulControl(arguments);
        },
      );
      await expectLater(launch.launch(_spec), throwsA(isA<FormatException>()));
      expect(await tail!.exitCode, isNot(0));
      expect(calls.where(_isTunnel), isEmpty);
      expect(
        calls.where((a) => a.last == 'taskkill /F /T /PID 44'),
        hasLength(1),
      );
    },
  );

  test('refuses a non-Windows target before starting SSH', () async {
    var starts = 0;
    final launch = RemoteWindowsHostLaunch(
      host: 'yoga-win',
      repository: 'repo',
      flutterExecutable: 'flutter',
      starter: (_, _) {
        starts++;
        return _shell('exit 0');
      },
    );
    await expectLater(
      launch.launch(const LaunchSpec(app: 'example', target: 'macos')),
      throwsArgumentError,
    );
    expect(starts, 0);
  });

  test(
    'no active interactive session fails before scheduled task launch',
    () async {
      final calls = <List<String>>[];
      final launch = RemoteWindowsHostLaunch(
        host: 'yoga-win',
        repository: 'repo',
        flutterExecutable: 'flutter',
        starter: (_, arguments) {
          calls.add(arguments);
          expect(_isSessionQuery(arguments), isTrue);
          return _shell('exit 23');
        },
      );
      await expectLater(
        launch.launch(_spec),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('interactive-session query exited with code 23'),
          ),
        ),
      );
      expect(calls, hasLength(1));
    },
  );

  for (final entry in [('prepare', 6), ('task', 5)]) {
    test('scheduled task launch failure during ${entry.$1}', () async {
      final calls = <List<String>>[];
      final launch = RemoteWindowsHostLaunch(
        host: 'yoga-win',
        repository: 'repo',
        flutterExecutable: 'flutter',
        starter: (_, arguments) {
          calls.add(arguments);
          if (_isSessionQuery(arguments) ||
              (entry.$1 == 'task' && _isPayloadPreparation(arguments))) {
            return _successfulControl(arguments);
          }
          return _shell('exit ${entry.$2}');
        },
      );
      await expectLater(launch.launch(_spec), throwsA(isA<StateError>()));
      expect(calls.where(_isLogTail), isEmpty);
      expect(calls.where(_isTunnel), isEmpty);
      expect(calls.where(_isTaskkill), isEmpty);
    });
  }

  test('scheduled task log timeout reaps logged pid once', () async {
    final calls = <List<String>>[];
    Process? tail;
    final launch = RemoteWindowsHostLaunch(
      host: 'yoga-win',
      repository: 'repo',
      flutterExecutable: 'flutter',
      readyTimeout: const Duration(milliseconds: 20),
      starter: (_, arguments) {
        calls.add(arguments);
        if (_isLogTail(arguments)) {
          return _shell("printf 'GRID_REMOTE_PID=77\\n'; sleep 10").then((p) {
            tail = p;
            return p;
          });
        }
        return _successfulControl(arguments);
      },
    );
    await expectLater(launch.launch(_spec), throwsA(isA<TimeoutException>()));
    await launch.teardown();
    expect(await tail!.exitCode, isNot(0));
    expect(
      calls.where((a) => a.last == 'taskkill /F /T /PID 77'),
      hasLength(1),
    );
  });

  test('readiness without a pid times out and reaps only the tail', () async {
    final calls = <List<String>>[];
    Process? tail;
    final launch = RemoteWindowsHostLaunch(
      host: 'yoga-win',
      repository: 'repo',
      flutterExecutable: 'flutter',
      readyTimeout: const Duration(milliseconds: 20),
      starter: (_, arguments) {
        calls.add(arguments);
        if (_isLogTail(arguments)) {
          return _shell(
            "printf 'GRID_VM_URI=ws://127.0.0.1:8181/x/ws\\n'; sleep 10",
          ).then((p) {
            tail = p;
            return p;
          });
        }
        return _successfulControl(arguments);
      },
    );
    await expectLater(launch.launch(_spec), throwsA(isA<TimeoutException>()));
    expect(await tail!.exitCode, isNot(0));
    expect(calls.where(_isTaskkill), isEmpty);
  });

  test('premature zero log-tail exit fails without invented cleanup', () async {
    final calls = <List<String>>[];
    final launch = RemoteWindowsHostLaunch(
      host: 'yoga-win',
      repository: 'repo',
      flutterExecutable: 'flutter',
      starter: (_, arguments) {
        calls.add(arguments);
        if (_isLogTail(arguments)) return _shell('exit 0');
        return _successfulControl(arguments);
      },
    );
    await expectLater(
      launch.launch(_spec),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('launch-log tail exited with code 0 before readiness'),
        ),
      ),
    );
    expect(calls.where(_isTaskkill), isEmpty);
  });

  test('malformed readiness reaps the tail and remote tree', () async {
    final calls = <List<String>>[];
    final launch = RemoteWindowsHostLaunch(
      host: 'yoga-win',
      repository: 'repo',
      flutterExecutable: 'flutter',
      starter: (_, arguments) {
        calls.add(arguments);
        if (_isLogTail(arguments)) {
          return _shell(
            "printf 'GRID_REMOTE_PID=88\\nGRID_VM_URI=not-a-uri\\n'; sleep 10",
          );
        }
        return _successfulControl(arguments);
      },
    );
    await expectLater(launch.launch(_spec), throwsA(isA<FormatException>()));
    expect(
      calls.where((a) => a.last == 'taskkill /F /T /PID 88'),
      hasLength(1),
    );
  });
}
