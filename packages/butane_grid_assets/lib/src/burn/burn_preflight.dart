import 'burn_order_inputs.dart';
import 'rig.dart' show FlutterDeviceCatalog;

typedef BurnPathPredicate = bool Function(String path);

/// Probes whether one host is reachable for burn launch.
typedef BurnHostReachability = Future<bool> Function(String host);

/// Probes whether one TCP peer is answering.
typedef BurnPeerReachability = Future<bool> Function(String host, int port);

/// Validates the three resolved inputs before a live burn starts.
final class BurnPreflight {
  const BurnPreflight({
    required this.directoryExists,
    required this.fileExists,
    required this.devices,
    required this.hostReachable,
    required this.peerReachable,
  });

  final BurnPathPredicate directoryExists;
  final BurnPathPredicate fileExists;
  final FlutterDeviceCatalog devices;
  final BurnHostReachability hostReachable;
  final BurnPeerReachability peerReachable;

  Future<BurnOrderInputs> validate(BurnOrderInputs inputs) async {
    if (inputs.followerDevice.isEmpty) {
      throw StateError('burn preflight missing burn.follower_device');
    }
    if (inputs.harnessDirectory.isEmpty ||
        !directoryExists(inputs.harnessDirectory)) {
      throw StateError(
        'burn preflight invalid burn.harness_dir: ${inputs.harnessDirectory}',
      );
    }
    if (inputs.leonardDrive.isEmpty || !fileExists(inputs.leonardDrive)) {
      throw StateError(
        'burn preflight invalid burn.leonard_drive: ${inputs.leonardDrive}',
      );
    }
    for (final precondition in inputs.preconditions) {
      var satisfied = false;
      try {
        satisfied = switch (precondition.kind) {
          BurnPreconditionKind.followerIosAttached =>
            (await devices.listDevices())
                    .where(
                      (device) =>
                          device.id == inputs.followerDevice &&
                          device.targetPlatform == 'ios' &&
                          !device.emulator,
                    )
                    .length ==
                1,
          BurnPreconditionKind.windowsHostReachable => await hostReachable(
            inputs.windowsHost,
          ),
          BurnPreconditionKind.peerAnswering => await peerReachable(
            precondition.host!,
            precondition.port!,
          ),
        };
      } on Object {
        satisfied = false;
      }
      if (satisfied) continue;
      throw StateError(switch (precondition.kind) {
        BurnPreconditionKind.followerIosAttached =>
          'burn preflight held follower-ios-attached: '
              'device=${inputs.followerDevice}',
        BurnPreconditionKind.windowsHostReachable =>
          'burn preflight held windows-host-reachable: '
              'host=${inputs.windowsHost}',
        BurnPreconditionKind.peerAnswering =>
          'burn preflight held peer: '
              'endpoint=${precondition.host}:${precondition.port}',
      });
    }
    return inputs;
  }
}
