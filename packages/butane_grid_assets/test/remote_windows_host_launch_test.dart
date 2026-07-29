import 'dart:async';
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

bool _isTunnel(List<String> arguments) => arguments.contains('-N');

bool _isTaskkill(List<String> arguments) =>
    arguments.last.startsWith('taskkill /F /T /PID ');

void main() {
  test(
    'tunnels a scraped loopback URI and reaps owned resources once',
    () async {
      final calls = <List<String>>[];
      final logs = <String>[];
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
          if (_isTunnel(arguments)) return _shell('sleep 10');
          if (_isTaskkill(arguments)) return _shell('exit 0');
          return _shell(
            "printf 'GRID_REMOTE_PID=42\\n"
            "GRID_VM_URI=ws://127.0.0.1:8181/x/ws\\n'; sleep .5",
          );
        },
        onLog: logs.add,
      );

      final endpoint = await launch.launch(_spec);
      expect(endpoint.vmServiceUri, 'ws://127.0.0.1:49152/x/ws');
      expect(endpoint.station, 'windows-host');
      expect(calls[1], [
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
      expect(calls.first.last, contains(r'C:/repo/packages/butane_harness'));
      expect(
        calls.first.last,
        isNot(contains('packages/butane_windows/example')),
      );
      expect(calls.first.last, contains(r'C:/flutter.bat'));
      expect(calls.first.last, contains('BUTANE_ROLE=central'));
      expect(calls.first.last, contains('BUTANE_SCENARIO=smoke'));
      expect(tunnelProcess, isNotNull);

      await launch.teardown();
      await launch.teardown();
      expect(await tunnelProcess!.exitCode, isNot(0));
      expect(calls.where(_isTunnel), hasLength(1));
      expect(
        calls.where((args) => args.last == 'taskkill /F /T /PID 42'),
        hasLength(1),
      );
      expect(
        logs.where((line) => line.contains('tunnel reaped')),
        hasLength(1),
      );
      expect(logs, contains('teardown-receipt: remote windows host reaped 42'));
    },
  );

  test(
    'tunnel readiness failure reaps tunnel and remote process tree',
    () async {
      final calls = <List<String>>[];
      final logs = <String>[];
      Process? tunnelProcess;
      final launch = RemoteWindowsHostLaunch(
        host: 'yoga-win',
        repository: 'repo',
        flutterExecutable: 'flutter',
        allocatePort: () async => 49152,
        waitForTunnelReady: (_, process, _) async {
          tunnelProcess = process;
          throw StateError('forward refused');
        },
        starter: (_, arguments) {
          calls.add(arguments);
          if (_isTunnel(arguments)) return _shell('sleep 10');
          if (_isTaskkill(arguments)) return _shell('exit 0');
          return _shell(
            "printf 'GRID_REMOTE_PID=43\\n"
            "GRID_VM_URI=ws://localhost:8181/x/ws\\n'; sleep .5",
          );
        },
        onLog: logs.add,
      );

      await expectLater(
        launch.launch(_spec),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'forward refused',
          ),
        ),
      );
      expect(tunnelProcess, isNotNull);
      expect(await tunnelProcess!.exitCode, isNot(0));
      expect(calls.where(_isTunnel), hasLength(1));
      expect(
        calls.where((args) => args.last == 'taskkill /F /T /PID 43'),
        hasLength(1),
      );
      expect(
        logs.where((line) => line.contains('tunnel reaped')),
        hasLength(1),
      );
    },
  );

  test('refuses a non-loopback URI and cleans the remote tree', () async {
    final calls = <List<String>>[];
    final launch = RemoteWindowsHostLaunch(
      host: 'yoga-win',
      repository: 'repo',
      flutterExecutable: 'flutter',
      starter: (_, arguments) {
        calls.add(arguments);
        if (_isTaskkill(arguments)) return _shell('exit 0');
        return _shell(
          "printf 'GRID_REMOTE_PID=44\\n"
          "GRID_VM_URI=ws://yoga-win:8181/x/ws\\n'; sleep .5",
        );
      },
    );

    await expectLater(launch.launch(_spec), throwsA(isA<FormatException>()));
    expect(calls.where(_isTunnel), isEmpty);
    expect(
      calls.where((args) => args.last == 'taskkill /F /T /PID 44'),
      hasLength(1),
    );
  });

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
    'timeout attempts one taskkill and repeated teardown is a no-op',
    () async {
      final calls = <List<String>>[];
      final logs = <String>[];
      final launch = RemoteWindowsHostLaunch(
        host: 'yoga-win',
        repository: 'repo',
        flutterExecutable: 'flutter',
        readyTimeout: const Duration(milliseconds: 20),
        starter: (_, arguments) {
          calls.add(arguments);
          if (_isTaskkill(arguments)) return _shell('exit 0');
          return _shell("printf 'GRID_REMOTE_PID=77\\n'; sleep .1");
        },
        onLog: logs.add,
      );

      await expectLater(launch.launch(_spec), throwsA(isA<TimeoutException>()));
      await launch.teardown();
      await launch.teardown();
      expect(calls.where(_isTunnel), isEmpty);
      expect(
        calls.where((args) => args.last == 'taskkill /F /T /PID 77'),
        hasLength(1),
      );
      expect(logs, contains('teardown-receipt: remote windows host reaped 77'));
    },
  );

  test('non-zero SSH without a pid fails without inventing cleanup', () async {
    final calls = <List<String>>[];
    final launch = RemoteWindowsHostLaunch(
      host: 'yoga-win',
      repository: 'repo',
      flutterExecutable: 'flutter',
      starter: (_, arguments) {
        calls.add(arguments);
        return _shell('exit 9');
      },
    );

    await expectLater(launch.launch(_spec), throwsStateError);
    expect(calls, hasLength(1));
  });

  test('readiness without a pid times out without inventing cleanup', () async {
    final calls = <List<String>>[];
    final launch = RemoteWindowsHostLaunch(
      host: 'yoga-win',
      repository: 'repo',
      flutterExecutable: 'flutter',
      readyTimeout: const Duration(milliseconds: 20),
      starter: (_, arguments) {
        calls.add(arguments);
        return _shell(
          "printf 'GRID_VM_URI=ws://127.0.0.1:8181/x/ws\\n'; sleep .1",
        );
      },
    );

    await expectLater(launch.launch(_spec), throwsA(isA<TimeoutException>()));
    await launch.teardown();
    expect(calls, hasLength(1));
  });

  test('malformed readiness attempts remote tree cleanup', () async {
    final calls = <List<String>>[];
    final launch = RemoteWindowsHostLaunch(
      host: 'yoga-win',
      repository: 'repo',
      flutterExecutable: 'flutter',
      starter: (_, arguments) {
        calls.add(arguments);
        if (_isTaskkill(arguments)) return _shell('exit 0');
        return _shell(
          "printf 'GRID_REMOTE_PID=88\\nGRID_VM_URI=not-a-uri\\n'; sleep .1",
        );
      },
    );

    await expectLater(launch.launch(_spec), throwsA(isA<FormatException>()));
    expect(calls.where(_isTunnel), isEmpty);
    expect(
      calls.where((args) => args.last == 'taskkill /F /T /PID 88'),
      hasLength(1),
    );
  });
}
