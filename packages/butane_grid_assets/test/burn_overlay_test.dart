import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('burn is vended as an operator skill', () {
    final manifest = File('extension/mcp/config.yaml').readAsStringSync();
    final skill = File(
      'extension/station_overlay/claude/skills/burn/SKILL.md',
    ).readAsStringSync();
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
}
