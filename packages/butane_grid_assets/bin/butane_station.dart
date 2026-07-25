import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:butane_grid_assets/butane_grid_assets.dart';
import 'package:federated_grid_assets/federated_grid_assets.dart'
    show ServeCommand;

Future<void> main(List<String> argv) async {
  final runner = CommandRunner<int>(
    'butane_station',
    "butane's follower lessor — the resident station drives burn beads",
  )
    ..addCommand(
      ServeCommand(
        defaultKind: kBurnKind,
        configureFlags: configureBurnServeFlags,
        handlerFor: butaneBurnServeHandler,
      ),
    );
  exit(await runner.run(argv) ?? 64);
}
