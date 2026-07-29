import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:butane_grid_assets/src/burn/follower.dart';
import 'package:butane_grid_assets/src/burn/macos_central_launcher.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

void main() {
  test('launches profile macOS central and scrapes its sentinel', () async {
    final fixture = await _Fixture.create(
      sentinel: 'GRID_VM_URI=ws://127.0.0.1:6123/central/ws',
    );
    addTearDown(fixture.dispose);

    final daemon = await fixture.launcher.launch(
      const LaunchSpec(
        app: 'butane_harness',
        target: 'macos',
        role: 'central',
        harnessDirectory: '/harness/from/bead',
      ),
    );

    expect(fixture.starter.executable, 'flutter');
    expect(fixture.starter.arguments, <String>[
      'run',
      '--profile',
      '-d',
      'macos',
      '--dart-define=ROLE=central',
    ]);
    expect(fixture.starter.workingDirectory, '/harness/from/bead');
    expect(fixture.starter.mode, ProcessStartMode.detachedWithStdio);
    expect(daemon.endpoint.vmServiceUri, 'ws://127.0.0.1:6123/central/ws');
    expect(daemon.endpoint.station, 'macos-central');
    expect(daemon.pid, fixture.starter.process!.pid);
    expect(daemon.pgid, 4242);
  });

  test('readiness timeout kills the exact spawned process', () async {
    final fixture = await _Fixture.create(stayAlive: true);
    addTearDown(fixture.dispose);
    final launcher = MacosCentralLauncher(
      readyTimeout: const Duration(milliseconds: 50),
      processStarter: fixture.starter.call,
      processes: _FakeProcessGroups(),
    );

    await expectLater(
      launcher.launch(
        const LaunchSpec(
          app: 'butane_harness',
          target: 'macos',
          role: 'central',
          harnessDirectory: '/harness/from/bead',
        ),
      ),
      throwsA(isA<TimeoutException>()),
    );

    var alive = true;
    for (var attempt = 0; attempt < 100 && alive; attempt++) {
      alive = Process.killPid(
        fixture.starter.process!.pid,
        ProcessSignal.sigcont,
      );
      if (alive) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    }
    expect(alive, isFalse);
  });
}

final class _Fixture {
  _Fixture(this.directory, this.starter, this.launcher);

  final Directory directory;
  final _FakeProcessStarter starter;
  final MacosCentralLauncher launcher;

  static Future<_Fixture> create({
    String? sentinel,
    bool stayAlive = false,
  }) async {
    final directory = await Directory.systemTemp.createTemp(
      'macos_central_launcher_test.',
    );
    final helper = File('${directory.path}/helper.dart');
    await helper.writeAsString('''
import 'dart:async';
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> arguments) async {
  final sentinel = jsonDecode(arguments.single) as String;
  if (sentinel.isNotEmpty) stdout.writeln(sentinel);
  ${stayAlive ? "await Completer<void>().future;" : ''}
}
''');
    final starter = _FakeProcessStarter(
      helper.path,
      jsonEncode(sentinel ?? ''),
    );
    return _Fixture(
      directory,
      starter,
      MacosCentralLauncher(
        processStarter: starter.call,
        processes: _FakeProcessGroups(),
      ),
    );
  }

  Future<void> dispose() async {
    final process = starter.process;
    if (process != null) {
      Process.killPid(process.pid, ProcessSignal.sigkill);
    }
    await directory.delete(recursive: true);
  }
}

final class _FakeProcessStarter {
  _FakeProcessStarter(this.helperPath, this.sentinel);

  final String helperPath;
  final String sentinel;
  String? executable;
  List<String>? arguments;
  String? workingDirectory;
  ProcessStartMode? mode;
  Process? process;

  Future<Process> call(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    ProcessStartMode mode = ProcessStartMode.normal,
  }) async {
    this.executable = executable;
    this.arguments = arguments;
    this.workingDirectory = workingDirectory;
    this.mode = mode;
    process = await Process.start(Platform.resolvedExecutable, [
      'run',
      helperPath,
      sentinel,
    ], mode: mode);
    return process!;
  }
}

final class _FakeProcessGroups implements ProcessGroupController {
  @override
  int currentGroupId() => 999999;

  @override
  bool processAlive(int pid) => false;

  @override
  Future<int?> resolvePgid(int pid) async => 4242;

  @override
  bool signalGroup(int pgid, ProcessSignal signal) => true;
}
