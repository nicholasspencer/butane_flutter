import 'dart:developer' as developer;

import 'package:leonard_flutter/leonard_flutter.dart';

import 'src/butane_leonard_extension.dart';
import 'src/central_role.dart';
import 'src/command_registry.dart';
import 'src/config.dart';
import 'src/harness_app.dart';
import 'src/harness_log.dart';
import 'src/peripheral_role.dart';

void main() => LeonardBinding.run(ButaneHarness());

/// The harness as a [LeonardApp]: `LeonardBinding` claims the
/// `WidgetsBinding` slot first (debug/profile; in release no binding installs
/// and [build] still runs), exposing `ext.exploration.*` so `leonard_drive` /
/// the burn's host order can perceive and drive this app.
class ButaneHarness implements LeonardApp {
  @override
  LeonardAppConfig build(LeonardAppContext ctx) {
    final config = HarnessConfig.fromEnvironment();
    final log = HarnessLog();
    final registry = HarnessCommandRegistry();

    CentralRole? centralRole;
    PeripheralRole? peripheralRole;
    final Map<String, Object?> Function() snapshot;

    switch (config.role) {
      case HarnessRole.central:
        centralRole = CentralRole(log: log);
        registry.registerAll(centralRole.commands);
        snapshot = centralRole.perceptionSnapshot;
      case HarnessRole.peripheral:
        peripheralRole = PeripheralRole(log: log);
        registry.registerAll(peripheralRole.commands);
        snapshot = peripheralRole.perceptionSnapshot;
    }

    _publishVmServiceUri(ctx, log);

    return LeonardAppConfig(
      extensions: <LeonardExtension>[
        ButaneLeonardExtension(registry: registry, snapshot: snapshot),
      ],
      app: HarnessApp(
        config: config,
        log: log,
        onDispose: () {
          centralRole?.dispose();
          peripheralRole?.dispose();
        },
      ),
    );
  }

  /// Prints the `GRID_VM_URI=<ws://…/ws>` readiness sentinel AFTER the
  /// exploration host has registered every extension tool — the barrier a
  /// burn `FollowerLauncher` scrapes from stdout, so the first
  /// `leonard_drive` call can never race extension registration. A no-op in
  /// release (no binding) and when the VM service is not enabled.
  void _publishVmServiceUri(LeonardAppContext ctx, HarnessLog log) {
    final binding = ctx.binding;
    if (binding == null) return;
    binding.extensionsReady.then((_) async {
      final info = await developer.Service.getInfo();
      final serverUri = info.serverUri;
      if (serverUri == null) return;
      final wsUri = _toWs(serverUri);
      // The sentinel IS the contract: a launcher scrapes this exact line
      // from stdout (burn follower readiness) — print, not debugPrint.
      // ignore: avoid_print
      print('GRID_VM_URI=$wsUri');
      log.add('exploration ready at $wsUri');
    });
  }

  /// `http://…/[token/]` → `ws://…/[token/]ws` (the launcher/attach form).
  static String _toWs(Uri serverUri) {
    final path = serverUri.path.endsWith('/')
        ? '${serverUri.path}ws'
        : '${serverUri.path}/ws';
    return serverUri
        .replace(scheme: serverUri.scheme == 'https' ? 'wss' : 'ws', path: path)
        .toString();
  }
}
