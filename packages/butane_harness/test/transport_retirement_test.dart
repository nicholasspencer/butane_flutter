import 'package:flutter_test/flutter_test.dart';

import '../lib/src/butane_leonard_extension.dart';
import '../lib/src/command_registry.dart';
import '../lib/src/config.dart';

void main() {
  test('role-only config feeds the Leonard registry frontend', () async {
    const config = HarnessConfig(role: HarnessRole.central);
    final registry = HarnessCommandRegistry()
      ..register(
        HarnessCommand(
          action: 'probe',
          description: 'Probe the registry.',
          handler: (_) async => <String, dynamic>{'role': config.role.name},
        ),
      );
    final extension = ButaneLeonardExtension(
      registry: registry,
      snapshot: () => <String, Object?>{'role': config.role.name},
    );

    expect(extension.tools.map((tool) => tool.name), <String>['probe']);
    expect(
      await registry.dispatch('probe', const <String, dynamic>{}),
      <String, dynamic>{'role': 'central'},
    );
    expect(extension.buildPerception(), isNotNull);
  });
}
