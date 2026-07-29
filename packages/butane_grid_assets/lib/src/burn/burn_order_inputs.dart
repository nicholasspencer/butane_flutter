/// Inputs carried by a burn ORDER bead.
final class BurnOrderInputs {
  const BurnOrderInputs({
    required this.followerDevice,
    required this.harnessDirectory,
    required this.leonardDrive,
    this.centralTarget = 'macos',
    this.windowsHost = 'yoga-win',
    this.windowsRepo = r'C:/Users/nicks/butane_flutter',
    this.windowsFlutter = r'C:/Users/nicks/fvm/versions/stable/bin/flutter.bat',
  });

  static const followerDeviceKey = 'burn.follower_device';
  static const harnessDirectoryKey = 'burn.harness_dir';
  static const leonardDriveKey = 'burn.leonard_drive';
  static const centralTargetKey = 'burn.central_target';
  static const windowsHostKey = 'burn.windows_host';
  static const windowsRepoKey = 'burn.windows_repo';
  static const windowsFlutterKey = 'burn.windows_flutter';

  final String followerDevice;
  final String harnessDirectory;
  final String leonardDrive;
  final String centralTarget;
  final String windowsHost;
  final String windowsRepo;
  final String windowsFlutter;

  /// Resolves metadata first and logs every environment fallback used.
  factory BurnOrderInputs.resolve({
    required Map<String, dynamic> metadata,
    required Map<String, String> environment,
    required void Function(String) onLog,
  }) {
    String read(String key, String variable, [String defaultValue = '']) {
      final canonical = metadata[key];
      if (canonical is String && canonical.trim().isNotEmpty) {
        return canonical.trim();
      }
      final fallback = environment[variable]?.trim() ?? '';
      if (fallback.isNotEmpty) {
        onLog('burn input $key: metadata absent; using environment $variable');
      }
      return fallback.isEmpty ? defaultValue : fallback;
    }

    return BurnOrderInputs(
      followerDevice: read(followerDeviceKey, 'BURN_IOS_DEVICE'),
      harnessDirectory: read(harnessDirectoryKey, 'BURN_HARNESS_DIR'),
      leonardDrive: read(leonardDriveKey, 'LEONARD_DRIVE'),
      centralTarget: read(centralTargetKey, 'BURN_CENTRAL_TARGET', 'macos'),
      windowsHost: read(windowsHostKey, 'BUTANE_WINDOWS_HOST', 'yoga-win'),
      windowsRepo: read(
        windowsRepoKey,
        'BUTANE_WINDOWS_REPO',
        r'C:/Users/nicks/butane_flutter',
      ),
      windowsFlutter: read(
        windowsFlutterKey,
        'BUTANE_WINDOWS_FLUTTER',
        r'C:/Users/nicks/fvm/versions/stable/bin/flutter.bat',
      ),
    );
  }
}
