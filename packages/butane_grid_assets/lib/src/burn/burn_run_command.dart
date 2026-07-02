/// `burn` — the butane asset's run command (the CLI-SDK model: the pack
/// exports the Command, a runner assembles it — `bin/butane_station.dart`
/// here, space_station at the studio).
///
/// Directly parallel to the code asset's `CodeRunCommand`: supplies the
/// asset trio to [StationRunCommand]. The burn's registry depends on its own
/// flags (peers, scenario, launcher paths), so it builds per-invocation via
/// [registryFor] rather than at construction.
library;

import 'dart:io';

import 'package:args/args.dart';
import 'package:grid_cli/grid_cli.dart' show StationRunCommand;
import 'package:grid_controller/grid_controller.dart' show Bead;
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_federation/grid_federation.dart' show HttpStationClient;
import 'package:grid_runtime/grid_runtime.dart'
    show SystemProcessGroupController;

import 'burn_capabilities.dart';
import 'butane_follower_launcher.dart';
import 'follower.dart';
import 'process_leonard_drive.dart';
import 'scenarios.dart';

Formula _burnFormula(Bead _) => kBurnFormula;

/// The butane burn run command: lease a follower peer, launch the local
/// central, drive the scripted scenario over two leonard_drives, report.
class BurnRunCommand extends StationRunCommand {
  /// Creates the command. The construction-time registry is a placeholder —
  /// [registryFor] builds the real one from this invocation's flags.
  BurnRunCommand()
      : super(
          resolver: const FormulaResolver(_burnFormula),
          registry: _placeholder,
        ) {
    argParser
      ..addMultiOption(
        'peer',
        help: 'A candidate follower peer as host:port (repeatable) — matched '
            'by capability containment, first satisfier leased.',
      )
      ..addOption(
        'peer-token',
        help: 'Optional shared secret sent to peers as X-Grid-Token.',
      )
      ..addOption(
        'scenario',
        defaultsTo: 'smoke',
        allowed: kButaneScenarios.keys,
        help: 'The named scripted scenario to drive.',
      )
      ..addOption(
        'harness-dir',
        help: 'The butane_harness checkout on THIS box — built + launched as '
            'the local central (required unless --no-local).',
      )
      ..addOption(
        'follower-target',
        defaultsTo: 'linux',
        help: "The follower's flutter build target (matched against the "
            'peer capability profile).',
      )
      ..addFlag(
        'local',
        defaultsTo: true,
        help: 'Two-drive burn: launch a local central harness alongside the '
            'leased follower peripheral. --no-local drives the follower only.',
      );
  }

  static final DefaultCapabilityRegistry _placeholder = buildBurnRegistry(
    peers: const [],
    launchSpec: const LaunchSpec(app: 'butane_harness', target: 'linux'),
    drive: ProcessLeonardDrive(),
    scenario: kSmokeScenario,
  );

  @override
  final String name = 'burn';

  @override
  final String description =
      'Run the butane BURN: lease a follower peer over the federation bus, '
      'launch the harness on both ends, drive a scripted scenario over '
      'leonard_drive, and collect a TestReport.';

  @override
  CapabilityRegistry registryFor(ArgResults args) {
    final peers = <FollowerPeer>[
      for (final peer in args.multiOption('peer'))
        FollowerPeer(
          id: peer,
          client: HttpStationClient(
            host: peer.split(':').first,
            port: int.parse(peer.split(':').last),
            token: args.option('peer-token'),
          ),
        ),
    ];
    final local = args.flag('local');
    final harnessDir = args.option('harness-dir');
    if (local && (harnessDir == null || harnessDir.isEmpty)) {
      usageException('--harness-dir is required for the two-drive burn '
          '(or pass --no-local)');
    }
    final localTarget = Platform.isMacOS ? 'macos' : 'linux';
    void log(String m) => stdout.writeln('  $m');
    return buildBurnRegistry(
      peers: peers,
      launchSpec: LaunchSpec(
        app: 'butane_harness',
        target: args.option('follower-target')!,
      ),
      drive: ProcessLeonardDrive(),
      scenario: kButaneScenarios[args.option('scenario')]!,
      localRunner: !local
          ? null
          : ButaneFollowerRunner(
              launcher: ButaneFollowerLauncher(
                harnessDirectory: harnessDir!,
                wsPort: 8972,
                onLog: log,
              ),
              processes: const SystemProcessGroupController(),
              onLog: log,
            ),
      localSpec: !local
          ? null
          : LaunchSpec(
              app: 'butane_harness',
              target: localTarget,
              role: 'central',
            ),
      localDrive: !local ? null : ProcessLeonardDrive(),
      onLog: log,
    );
  }
}
