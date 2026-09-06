// Run explicitly: compiling a second package VM in the default parallel suite
// contends with launcher tests that intentionally enforce sub-250ms deadlines.
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  test(
    'SIGTERM during launch does not leave a deadline retaining the process',
    () async {
      if (Platform.isWindows) return;
      final process = await Process.start(Platform.resolvedExecutable, [
        'test/fixtures/pending_burn_follower_daemon.dart',
      ]);
      addTearDown(() async {
        if (process.kill(ProcessSignal.sigkill)) await process.exitCode;
      });
      final stderrOutput = process.stderr.transform(utf8.decoder).join();
      await process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .firstWhere((line) => line == 'launch-started');

      final stopwatch = Stopwatch()..start();
      expect(process.kill(ProcessSignal.sigterm), isTrue);
      expect(await process.exitCode.timeout(const Duration(seconds: 2)), 0);
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 2)));
      expect(
        await stderrOutput,
        allOf(
          contains('termination-receipt: burn follower daemon launch aborted'),
          contains('teardown-receipt: burn follower daemon reaped'),
        ),
      );
    },
  );
}
