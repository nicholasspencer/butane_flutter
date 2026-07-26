import 'dart:io';

import 'package:butane_grid_assets/butane_grid_assets.dart';
import 'package:federated_grid_assets/federated_grid_assets.dart'
    show ServeCommand;
import 'package:test/test.dart';

void main() {
  test('butane_station exposes the follower lessor only', () {
    expect(ServeCommand, isNotNull);
    final source = File('bin/butane_station.dart').readAsStringSync();
    expect(source, contains('ServeCommand('));
    expect(source, isNot(contains('BurnRunCommand')));
  });

  test('the burn asset never boots a second grid', () {
    final sources = <File>[
      ...Directory('lib').listSync(recursive: true).whereType<File>(),
      ...Directory('bin').listSync(recursive: true).whereType<File>(),
    ].where((file) => file.path.endsWith('.dart'));
    final text = sources.map((file) => file.readAsStringSync()).join('\n');
    expect(text, isNot(contains('runGrid(')));
    expect(text, isNot(contains('GridDelegate')));
    expect(text, isNot(contains('StationRunCommand')));
  });

  test('burn circuit remains a resident-runtime composition value', () {
    expect(kBurnCircuit.id, 'burn');
    expect(kBurnCircuit.terminalStepId, kBurnHostStep);
  });
}
