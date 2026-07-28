/// Inputs carried by a burn ORDER bead.
final class BurnOrderInputs {
  const BurnOrderInputs({
    required this.followerDevice,
    required this.harnessDirectory,
    required this.leonardDrive,
  });

  static const followerDeviceKey = 'burn.follower_device';
  static const harnessDirectoryKey = 'burn.harness_dir';
  static const leonardDriveKey = 'burn.leonard_drive';

  final String followerDevice;
  final String harnessDirectory;
  final String leonardDrive;

  /// Resolves metadata first and logs every environment fallback used.
  factory BurnOrderInputs.resolve({
    required Map<String, dynamic> metadata,
    required Map<String, String> environment,
    required void Function(String) onLog,
  }) {
    String read(String key, String variable) {
      final canonical = metadata[key];
      if (canonical is String && canonical.trim().isNotEmpty) {
        return canonical.trim();
      }
      final fallback = environment[variable]?.trim() ?? '';
      if (fallback.isNotEmpty) {
        onLog('burn input $key: metadata absent; using environment $variable');
      }
      return fallback;
    }

    return BurnOrderInputs(
      followerDevice: read(followerDeviceKey, 'BURN_IOS_DEVICE'),
      harnessDirectory: read(harnessDirectoryKey, 'BURN_HARNESS_DIR'),
      leonardDrive: read(leonardDriveKey, 'LEONARD_DRIVE'),
    );
  }
}
