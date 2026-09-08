import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('burn is vended as an operator skill', () {
    const trackedSkillPath =
        'extension/station_overlay/claude/skills/burn/SKILL.md';
    const overlayPrefix = 'extension/station_overlay/';
    final manifest = File('extension/mcp/config.yaml').readAsStringSync();
    final tracked = Process.runSync('git', [
      'ls-files',
      '--cached',
      '--',
      'extension',
    ], workingDirectory: Directory.current.path);
    expect(tracked.exitCode, 0, reason: '${tracked.stderr}');
    final trackedPaths = const LineSplitter().convert(tracked.stdout as String);
    expect(trackedPaths, contains(trackedSkillPath));
    final trackedBurnPath = trackedPaths.singleWhere(
      (path) => path == trackedSkillPath,
    );
    expect(Directory('$overlayPrefix.claude').existsSync(), isFalse);
    final hiddenSegments = trackedPaths
        .where((path) => path.startsWith(overlayPrefix))
        .expand((path) => path.split('/'))
        .where((segment) => segment.startsWith('.'));
    expect(hiddenSegments, isEmpty);
    final manifestSkillPath = RegExp(
      r'^    path: (station_overlay/[^\r\n]+)$',
      multiLine: true,
    ).allMatches(manifest).single.group(1)!;
    expect('extension/$manifestSkillPath', trackedBurnPath);
    expect(manifest, contains('claude: .claude'));
    final sourceSegments = trackedBurnPath
        .substring(overlayPrefix.length)
        .split('/');
    final mappedTarget = <String>[
      sourceSegments.first == 'claude' ? '.claude' : sourceSegments.first,
      ...sourceSegments.skip(1),
    ].join('/');
    expect(mappedTarget, '.claude/skills/burn/SKILL.md');
    final skill = File(trackedBurnPath).readAsStringSync();
    expect(manifest, contains('id: burn'));
    expect(manifest, contains('audience: operator'));
    expect(manifest, contains('claude: .claude'));
    expect(skill, contains('name: burn'));
    expect(skill, contains('bd create'));
    expect(skill, contains('bd update'));
    expect(skill, contains('bd show'));
    expect(skill, isNot(contains('--ephemeral')));
    expect(skill, isNot(contains('--persistent')));
    expect(
      skill,
      contains('New burn requests are persistent from their first `bd create`'),
    );
    for (final forbidden in [
      'runGrid',
      'GridDelegate',
      'butane_station burn',
      'dart run',
    ]) {
      expect(skill, isNot(contains(forbidden)));
    }
  });

  test('burn skill reads durable step-result receipts', () {
    const trackedSkillPath =
        'extension/station_overlay/claude/skills/burn/SKILL.md';
    final skill = File(trackedSkillPath).readAsStringSync();

    expect(skill, contains('burn order bead'));
    expect(
      skill,
      matches(RegExp(r'durable `burn-host` step\s+result payload')),
    );
    for (final key in [
      'scenario',
      'passed',
      'central',
      'follower',
      'steps',
      'failures',
      'observedSteps',
      'centralIdentity',
      'centralRole',
      'centralTarget',
      'centralLaunchOutcome',
      'centralTeardownConfirmation',
      'followerIdentity',
      'followerRole',
      'followerTarget',
      'followerLaunchOutcome',
      'followerTeardownConfirmation',
      'step<N>Role',
      'step<N>Outcome',
      'step<N>DurationMs',
      'failingStepIndex',
      'burn-evidence:',
      'not-observed',
    ]) {
      expect(skill, contains(key), reason: 'missing receipt field $key');
    }
    expect(
      skill,
      isNot(
        contains(
          'Richer per-device audit is tracked separately and is not '
          'synthesized here.',
        ),
      ),
    );
  });
}
