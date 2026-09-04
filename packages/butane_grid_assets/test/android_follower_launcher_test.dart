@Tags(['integration'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:butane_grid_assets/src/burn/android_follower_launcher.dart';
import 'package:butane_grid_assets/src/burn/follower.dart';
import 'package:butane_grid_assets/src/burn/process_leonard_drive.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

void main() {
  group('AndroidFollowerLauncher command contract', () {
    test('API 31 profile launch grants BLE, forwards and publishes', () async {
      final fixture = await _Fixture.create(sdk: 34);
      addTearDown(fixture.dispose);

      final daemon = await fixture.launcher.launch(
        const LaunchSpec(
          app: 'butane_harness',
          target: 'android',
          role: 'peripheral',
        ),
      );

      expect(
        fixture.commands.flattened,
        containsAllInOrder([
          'flutter build apk --profile --dart-define=ROLE=peripheral',
          'adb -s serial install -r ${fixture.apk.path}',
          'adb -s serial shell getprop ro.build.version.sdk',
          'adb -s serial shell pm grant com.nicospencer.butane_harness '
              'android.permission.BLUETOOTH_SCAN',
          'adb -s serial shell pm grant com.nicospencer.butane_harness '
              'android.permission.BLUETOOTH_CONNECT',
          'adb -s serial shell pm grant com.nicospencer.butane_harness '
              'android.permission.BLUETOOTH_ADVERTISE',
          'adb -s serial shell am start -n '
              'com.nicospencer.butane_harness/.MainActivity',
        ]),
      );
      expect(daemon.endpoint.vmServiceUri, fixture.probed.single.toString());
      expect(Uri.parse(daemon.endpoint.vmServiceUri).host, '127.0.0.1');
      expect(Uri.parse(daemon.endpoint.vmServiceUri).path, '/auth/ws');
      expect(daemon.pgid, 4242);
      expect(
        fixture.commands.flattened,
        contains(matches(r'^adb -s serial forward tcp:\d+ tcp:43210$')),
      );
    });

    test('API 30 grants location and not Android 12 BLE permissions', () async {
      final fixture = await _Fixture.create(sdk: 30);
      addTearDown(fixture.dispose);

      await fixture.launcher.launch(
        const LaunchSpec(app: 'butane_harness', target: 'android'),
      );

      final text = fixture.commands.flattened.join('\n');
      expect(text, contains('android.permission.ACCESS_FINE_LOCATION'));
      expect(text, isNot(contains('android.permission.BLUETOOTH_SCAN')));
      expect(text, isNot(contains('android.permission.BLUETOOTH_CONNECT')));
      expect(text, isNot(contains('android.permission.BLUETOOTH_ADVERTISE')));
    });

    test('invalid target fails before running a command', () async {
      final fixture = await _Fixture.create(sdk: 34);
      addTearDown(fixture.dispose);

      await expectLater(
        fixture.launcher.launch(
          const LaunchSpec(app: 'butane_harness', target: 'ios'),
        ),
        throwsArgumentError,
      );
      expect(fixture.commands.flattened, isEmpty);
    });

    for (final failure in <String, String>{
      'build': 'flutter build ',
      'install': ' install ',
      'scan permission grant': 'android.permission.BLUETOOTH_SCAN',
      'connect permission grant': 'android.permission.BLUETOOTH_CONNECT',
      'advertise permission grant': 'android.permission.BLUETOOTH_ADVERTISE',
      'activity start': ' shell am start ',
    }.entries) {
      test('nonzero ${failure.key} fails loudly', () async {
        final fixture = await _Fixture.create(sdk: 34);
        addTearDown(fixture.dispose);
        fixture.commands.failWhen = failure.value;

        await expectLater(
          fixture.launcher.launch(
            const LaunchSpec(app: 'butane_harness', target: 'android'),
          ),
          throwsA(
            isA<StateError>().having(
              (error) => error.toString(),
              'message',
              contains('exited 1'),
            ),
          ),
        );
        expect(
          fixture.commands.flattened.join('\n'),
          contains(failure.value.trim()),
        );
        if (failure.key == 'activity start') {
          expect(await fixture.logcatExited, isTrue);
        }
      });
    }

    for (final failure in _ReadinessFailure.values) {
      test('${failure.name} readiness failure cleans all resources', () async {
        final fixture = await _Fixture.create(sdk: 34, failure: failure);
        try {
          await expectLater(
            fixture.launcher.launch(
              const LaunchSpec(app: 'butane_harness', target: 'android'),
            ),
            throwsA(anything),
          );
          expect(await fixture.logcatExited, isTrue);
          final commands = fixture.commands.flattened.join('\n');
          expect(commands, contains('shell am force-stop'));
          if (failure == _ReadinessFailure.probe) {
            expect(commands, contains('forward --remove'));
          }
        } finally {
          await fixture.dispose();
        }
      });
    }

    test('onReap ignores remove-forward and force-stop failures', () async {
      final fixture = await _Fixture.create(sdk: 34);
      addTearDown(fixture.dispose);
      final daemon = await fixture.launcher.launch(
        const LaunchSpec(app: 'butane_harness', target: 'android'),
      );

      fixture.commands.throwDuringCleanup = true;

      await expectLater(daemon.onReap!(), completes);
    });
  });

  test(
    'live Android profile follower is driveable and reaped',
    () async {
      final serial = Platform.environment['BURN_ANDROID_DEVICE'];
      if (serial == null || serial.isEmpty) {
        markTestSkipped('set BURN_ANDROID_DEVICE=<adb serial>');
        return;
      }
      if (await ProcessLeonardDrive.discover() == null) {
        markTestSkipped('leonard_drive not discoverable');
        return;
      }
      final launcher = AndroidFollowerLauncher(
        deviceId: serial,
        harnessDirectory: Directory('../butane_harness').absolute.path,
      );
      final runner = ButaneFollowerRunner(
        launcher: launcher,
        processes: const SystemProcessGroupController(),
      );
      try {
        final endpoint = await runner.launch(
          const LaunchSpec(
            app: 'butane_harness',
            target: 'android',
            role: 'peripheral',
          ),
        );
        expect(endpoint.vmServiceUri, startsWith('ws://127.0.0.1:'));
        final drive = ProcessLeonardDrive();
        await drive.attach(endpoint);
        final fragment =
            jsonDecode(await drive.observe('extensions.butane.data'))
                as Map<String, Object?>;
        expect(fragment['role'], 'peripheral');
        final state =
            jsonDecode(
                  await drive.invoke('butane.wait_for_state', {
                    'timeoutMs': 10000,
                  }),
                )
                as Map<String, Object?>;
        expect(state['ok'], isTrue);
        expect((state['value']! as Map)['matched'], isTrue);
      } finally {
        await runner.teardown();
        expect(runner.isRunning, isFalse);
      }
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}

enum _ReadinessFailure { malformedSentinel, probe, timeout }

final class _RecordedCommand {
  const _RecordedCommand(
    this.executable,
    this.arguments,
    this.workingDirectory,
  );

  final String executable;
  final List<String> arguments;
  final String? workingDirectory;

  String get flattened => '$executable ${arguments.join(' ')}';
}

final class _FakeCommandRunner {
  _FakeCommandRunner(this.sdk);

  final int sdk;
  final List<_RecordedCommand> calls = [];
  String? failWhen;
  bool throwDuringCleanup = false;

  List<String> get flattened => [for (final call in calls) call.flattened];

  Future<ProcessResult> call(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Duration? timeout,
  }) async {
    final call = _RecordedCommand(
      executable,
      List<String>.of(arguments),
      workingDirectory,
    );
    calls.add(call);
    final text = call.flattened;
    final cleanup =
        text.contains('forward --remove') ||
        text.contains('shell am force-stop');
    if (throwDuringCleanup && cleanup) {
      throw ProcessException(executable, arguments, 'cleanup failure');
    }
    if (failWhen case final match? when text.contains(match)) {
      return ProcessResult(100, 1, '', 'programmed failure');
    }
    return ProcessResult(
      100,
      0,
      text.contains('getprop ro.build.version.sdk') ? '$sdk\n' : '',
      '',
    );
  }
}

final class _FakeProcessStarter {
  _FakeProcessStarter(this.helper);

  final File helper;
  Process? process;

  Future<Process> call(String executable, List<String> arguments) async {
    process = await Process.start(Platform.resolvedExecutable, [
      'run',
      helper.path,
    ], mode: ProcessStartMode.detachedWithStdio);
    return process!;
  }
}

final class _FakeProcessGroups implements ProcessGroupController {
  @override
  int currentGroupId() => 999999;

  @override
  bool processAlive(int pid) => false;

  @override
  Future<List<int>> groupMembers(int pgid) async => const <int>[];

  @override
  Future<int?> resolvePgid(int pid) async => 4242;

  @override
  bool signalGroup(int pgid, ProcessSignal signal) => true;
}

final class _Fixture {
  _Fixture._({
    required this.directory,
    required this.apk,
    required this.commands,
    required this.starter,
    required this.launcher,
    required this.probed,
  });

  final Directory directory;
  final File apk;
  final _FakeCommandRunner commands;
  final _FakeProcessStarter starter;
  final AndroidFollowerLauncher launcher;
  final List<Uri> probed;

  static Future<_Fixture> create({
    required int sdk,
    _ReadinessFailure? failure,
  }) async {
    final directory = await Directory.systemTemp.createTemp(
      'android_follower_launcher_test.',
    );
    final apk = File(
      '${directory.path}/build/app/outputs/flutter-apk/app-profile.apk',
    );
    await apk.parent.create(recursive: true);
    await apk.writeAsBytes(const []);
    final helper = File('${directory.path}/logcat_helper.dart');
    final line = switch (failure) {
      _ReadinessFailure.malformedSentinel =>
        'GRID_VM_URI=http://127.0.0.1:43210/auth/ws',
      _ReadinessFailure.timeout => '',
      _ => 'GRID_VM_URI=ws://127.0.0.1:43210/auth/ws',
    };
    await helper.writeAsString('''
import 'dart:async';
void main() async {
  ${line.isEmpty ? '' : "print(${jsonEncode(line)});"}
  await Completer<void>().future;
}
''');
    final commands = _FakeCommandRunner(sdk);
    final starter = _FakeProcessStarter(helper);
    final probed = <Uri>[];
    final launcher = AndroidFollowerLauncher(
      deviceId: 'serial',
      harnessDirectory: directory.path,
      buildTimeout: const Duration(seconds: 1),
      readyTimeout: failure == _ReadinessFailure.timeout
          ? const Duration(milliseconds: 50)
          : const Duration(seconds: 2),
      processes: _FakeProcessGroups(),
      commandRunner: commands.call,
      processStarter: starter.call,
      endpointProbe: (Uri uri) async {
        probed.add(uri);
        if (failure == _ReadinessFailure.probe) {
          throw const SocketException('programmed probe failure');
        }
      },
    );
    return _Fixture._(
      directory: directory,
      apk: apk,
      commands: commands,
      starter: starter,
      launcher: launcher,
      probed: probed,
    );
  }

  Future<bool> get logcatExited async {
    final process = starter.process;
    if (process == null) return false;
    final deadline = DateTime.now().add(const Duration(seconds: 2));
    while (DateTime.now().isBefore(deadline)) {
      if (!Process.killPid(process.pid, ProcessSignal.sigwinch)) return true;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    return false;
  }

  Future<void> dispose() async {
    final process = starter.process;
    if (process != null) {
      Process.killPid(process.pid, ProcessSignal.sigkill);
    }
    if (directory.existsSync()) {
      await directory.delete(recursive: true);
    }
  }
}
