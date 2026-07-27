/// The burn LESSOR wiring — what a follower box plugs into the generic
/// `serve` core command (ADR-0011 D3: the core owns the lessor lifecycle,
/// the domain owns the use AND the reap of what it launched).
///
/// `butane_station serve --kind burn --harness-dir <path>`: a dispatched
/// launch builds + boots the harness via the target-specific launcher; the
/// lease's end (explicit release OR any reap) fires `onLeaseEnded` → the
/// runner reaps the launched app through the M4 `terminateGroup` reaper —
/// the guaranteed teardown crossing the bus, no leaked follower.
library;

import 'dart:async';

import 'package:args/args.dart';
import 'package:federated_grid_assets/federated_grid_assets.dart'
    show DispatchHandler;
import 'package:grid_runtime/grid_runtime.dart'
    show SystemProcessGroupController;

import 'burn_dispatch_handler.dart';
import 'android_follower_launcher.dart';
import 'butane_follower_launcher.dart';
import 'follower.dart';
import 'ios_follower_launcher.dart';

/// The burn-domain flags on the generic serve command.
void configureBurnServeFlags(ArgParser parser) => parser
  ..addOption(
    'harness-dir',
    help: 'The butane_harness checkout on this box — built (--debug) and '
        'launched as the follower app-under-test.',
  )
  ..addOption(
    'device-id',
    help: 'The attached device id (required for iOS and Android followers).',
  );

/// Creates one follower launcher when its target is selected.
typedef BurnFollowerLauncherFactory = FollowerLauncher Function();

/// Dispatches each launch to the implementation for [LaunchSpec.target].
class BurnTargetFollowerLauncher implements FollowerLauncher {
  /// Creates target dispatch from the existing platform launchers.
  const BurnTargetFollowerLauncher({
    required this.ios,
    required this.android,
    required this.desktop,
  });

  /// Builds the iOS launcher.
  final BurnFollowerLauncherFactory ios;

  /// Builds the Android launcher.
  final BurnFollowerLauncherFactory android;

  /// Builds the macOS/Linux launcher.
  final BurnFollowerLauncherFactory desktop;

  @override
  Future<LaunchedDaemon> launch(LaunchSpec spec) {
    final launcher = switch (spec.target) {
      'ios' => ios(),
      'android' => android(),
      'macos' || 'linux' => desktop(),
      final target => throw StateError(
          'unsupported burn follower target "$target" '
          '(supported: ios, android, macos, linux)',
        ),
    };
    return launcher.launch(spec);
  }
}

/// Builds the burn lessor pieces from the parsed serve flags: the
/// `burn`-kind dispatch handler over a target-aware [ButaneFollowerRunner], and
/// the
/// lease-end teardown that reaps the launched follower app.
({
  DispatchHandler handler,
  String? banner,
  void Function(String leaseId)? onLeaseEnded,
}) butaneBurnServeHandler(
  ArgResults args,
  void Function(String) log, {
  BurnFollowerLauncherFactory? iosLauncher,
  BurnFollowerLauncherFactory? androidLauncher,
  BurnFollowerLauncherFactory? desktopLauncher,
}) {
  final dir = args.option('harness-dir');
  if (dir == null || dir.isEmpty) {
    throw StateError('serve --kind burn requires --harness-dir');
  }
  final deviceId = args.option('device-id') ?? '';
  final runner = ButaneFollowerRunner(
    launcher: BurnTargetFollowerLauncher(
      ios: iosLauncher ??
          () {
            _requireDeviceId('ios', deviceId);
            return IosFollowerLauncher(
              deviceId: deviceId,
              harnessDirectory: dir,
              onLog: log,
            );
          },
      android: androidLauncher ??
          () {
            _requireDeviceId('android', deviceId);
            return AndroidFollowerLauncher(
              deviceId: deviceId,
              harnessDirectory: dir,
              onLog: log,
            );
          },
      desktop: desktopLauncher ??
          () => ButaneFollowerLauncher(
                harnessDirectory: dir,
                onLog: log,
              ),
    ),
    processes: const SystemProcessGroupController(),
    onLog: log,
  );
  return (
    handler: burnDispatchHandler(runner: runner, onLog: log),
    banner: '  burn lessor: follower harness at $dir '
        '(reaped on lease end)',
    onLeaseEnded: (leaseId) {
      log('lease $leaseId ended → reaping the follower app');
      unawaited(runner.teardown());
    },
  );
}

void _requireDeviceId(String target, String deviceId) {
  if (deviceId.isEmpty) {
    throw StateError(
      'burn follower target "$target" requires serve --device-id',
    );
  }
}
