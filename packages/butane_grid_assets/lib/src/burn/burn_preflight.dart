import 'burn_order_inputs.dart';

typedef BurnPathPredicate = bool Function(String path);

/// Validates the three resolved inputs before a live burn starts.
final class BurnPreflight {
  const BurnPreflight({
    required this.directoryExists,
    required this.fileExists,
  });

  final BurnPathPredicate directoryExists;
  final BurnPathPredicate fileExists;

  BurnOrderInputs validate(BurnOrderInputs inputs) {
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
    return inputs;
  }
}
