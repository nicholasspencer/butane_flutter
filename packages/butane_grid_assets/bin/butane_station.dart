// butane's assembled grid station — the burn domain, self-contained: a
// follower box needs only the butane checkout ("grid assets live with their
// system"). The studio's space_station composes BurnRunCommand too; serve
// --kind burn runs HERE on follower boxes.
//
//   dart run butane_grid_assets:butane_station burn --peer box:8080 \
//     --harness-dir packages/butane_harness --bead <id> --no-dry-run …
//   dart run butane_grid_assets:butane_station serve --kind burn \
//     --harness-dir packages/butane_harness
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:butane_grid_assets/butane_grid_assets.dart';
import 'package:grid_cli/grid_cli.dart' show ServeCommand;

Future<void> main(List<String> argv) async {
  final runner = CommandRunner<int>(
    'butane_station',
    "butane's grid station — the burn domain (host run + follower lessor).",
  )
    ..addCommand(BurnRunCommand())
    ..addCommand(
      ServeCommand(
        defaultKind: kBurnKind,
        configureFlags: configureBurnServeFlags,
        handlerFor: butaneBurnServeHandler,
      ),
    );
  exit(await runner.run(argv) ?? 64);
}
