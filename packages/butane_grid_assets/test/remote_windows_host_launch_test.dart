import 'dart:async';
import 'dart:io';

import 'package:butane_grid_assets/butane_grid_assets.dart';
import 'package:test/test.dart';

const _spec = LaunchSpec(
  app: 'butane_windows_example',
  target: 'windows',
  role: 'central',
  scenario: 'smoke',
);

Future<Process> _shell(String script) =>
    Process.start('/bin/sh', ['-c', script]);

void main() {
  test('launches with non-interactive SSH and publishes a LAN URI', () async {
    final calls = <List<String>>[];
    final logs = <String>[];
    String? executable;
    List<String>? arguments;
    final launch = RemoteWindowsHostLaunch(
      host: 'yoga-win',
      repository: r'C:/repo',
      flutterExecutable: r'C:/flutter.bat',
      starter: (exe, args) {
        calls.add(args);
        executable = exe;
        arguments = args;
        if (calls.length == 2) return _shell('exit 0');
        return _shell(
          "printf 'GRID_REMOTE_PID=42\\nGRID_VM_URI=ws://127.0.0.1:8181/x/ws\\n'; sleep .2",
        );
      },
      onLog: logs.add,
    );

    final endpoint = await launch.launch(_spec);
    expect(endpoint.vmServiceUri, 'ws://yoga-win:8181/x/ws');
    expect(endpoint.station, 'windows-host');
    expect(executable, 'ssh');
    expect(arguments!.take(5), [
      '-o',
      'BatchMode=yes',
      '-o',
      'ConnectTimeout=15',
      'yoga-win',
    ]);
    expect(
      arguments!.last,
      contains(r'C:/repo/packages/butane_windows/example'),
    );
    expect(arguments!.last, contains(r'C:/flutter.bat'));
    expect(arguments!.last, contains('BUTANE_ROLE=central'));
    expect(arguments!.last, contains('BUTANE_SCENARIO=smoke'));

    await launch.teardown();
    await launch.teardown();
    expect(
      calls.where((args) => args.last == 'taskkill /F /T /PID 42'),
      hasLength(1),
    );
    expect(logs, contains('teardown-receipt: remote windows host reaped 42'));
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
        starter: (_, args) {
          calls.add(args);
          if (calls.length == 1) {
            return _shell("printf 'GRID_REMOTE_PID=77\\n'; sleep .1");
          }
          return _shell('exit 0');
        },
        onLog: logs.add,
      );

      await expectLater(launch.launch(_spec), throwsA(isA<TimeoutException>()));
      await launch.teardown();
      await launch.teardown();
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
      starter: (_, args) {
        calls.add(args);
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
      starter: (_, args) {
        calls.add(args);
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
      starter: (_, args) {
        calls.add(args);
        if (calls.length == 2) return _shell('exit 0');
        return _shell(
          "printf 'GRID_REMOTE_PID=88\\nGRID_VM_URI=not-a-uri\\n'; sleep .1",
        );
      },
    );

    await expectLater(launch.launch(_spec), throwsA(isA<FormatException>()));
    expect(
      calls.where((args) => args.last == 'taskkill /F /T /PID 88'),
      hasLength(1),
    );
  });
}
