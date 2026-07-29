import 'package:butane_grid_assets/butane_grid_assets.dart';
import 'package:test/test.dart';

void main() {
  group('BurnOrderInputs', () {
    test('metadata wins, is trimmed, and emits no fallback logs', () {
      final logs = <String>[];
      final inputs = BurnOrderInputs.resolve(
        metadata: const {
          BurnOrderInputs.followerDeviceKey: ' order-device ',
          BurnOrderInputs.harnessDirectoryKey: ' /order/harness ',
          BurnOrderInputs.leonardDriveKey: ' /order/leonard ',
          BurnOrderInputs.centralTargetKey: ' windows ',
          BurnOrderInputs.windowsHostKey: ' order-host ',
          BurnOrderInputs.windowsRepoKey: ' C:/order/repo ',
          BurnOrderInputs.windowsFlutterKey: ' C:/order/flutter.bat ',
        },
        environment: const {
          'BURN_IOS_DEVICE': 'environment-device',
          'BURN_HARNESS_DIR': '/environment/harness',
          'LEONARD_DRIVE': '/environment/leonard',
          'BURN_CENTRAL_TARGET': 'macos',
          'BUTANE_WINDOWS_HOST': 'environment-host',
          'BUTANE_WINDOWS_REPO': 'C:/environment/repo',
          'BUTANE_WINDOWS_FLUTTER': 'C:/environment/flutter.bat',
        },
        onLog: logs.add,
      );

      expect(inputs.followerDevice, 'order-device');
      expect(inputs.harnessDirectory, '/order/harness');
      expect(inputs.leonardDrive, '/order/leonard');
      expect(inputs.centralTarget, 'windows');
      expect(inputs.windowsHost, 'order-host');
      expect(inputs.windowsRepo, 'C:/order/repo');
      expect(inputs.windowsFlutter, 'C:/order/flutter.bat');
      expect(logs, isEmpty);
    });

    test('empty metadata uses and logs each matching environment fallback', () {
      final logs = <String>[];
      final inputs = BurnOrderInputs.resolve(
        metadata: const {
          BurnOrderInputs.followerDeviceKey: ' ',
          BurnOrderInputs.harnessDirectoryKey: '',
        },
        environment: const {
          'BURN_IOS_DEVICE': ' device ',
          'BURN_HARNESS_DIR': ' /harness ',
          'LEONARD_DRIVE': ' /leonard ',
        },
        onLog: logs.add,
      );

      expect(inputs.followerDevice, 'device');
      expect(inputs.harnessDirectory, '/harness');
      expect(inputs.leonardDrive, '/leonard');
      expect(logs, [
        'burn input burn.follower_device: metadata absent; '
            'using environment BURN_IOS_DEVICE',
        'burn input burn.harness_dir: metadata absent; '
            'using environment BURN_HARNESS_DIR',
        'burn input burn.leonard_drive: metadata absent; '
            'using environment LEONARD_DRIVE',
      ]);
    });

    test('keeps unresolved inputs empty', () {
      final inputs = BurnOrderInputs.resolve(
        metadata: const {},
        environment: const {},
        onLog: (_) {},
      );

      expect(inputs.followerDevice, isEmpty);
      expect(inputs.harnessDirectory, isEmpty);
      expect(inputs.leonardDrive, isEmpty);
      expect(inputs.centralTarget, 'macos');
      expect(inputs.windowsHost, 'yoga-win');
      expect(inputs.windowsRepo, r'C:/Users/nicks/butane_flutter');
      expect(
        inputs.windowsFlutter,
        r'C:/Users/nicks/fvm/versions/stable/bin/flutter.bat',
      );
    });

    test('uses the exact trimmed Windows environment contract', () {
      final inputs = BurnOrderInputs.resolve(
        metadata: const {},
        environment: const {
          'BURN_CENTRAL_TARGET': ' windows ',
          'BUTANE_WINDOWS_HOST': ' yoga-env ',
          'BUTANE_WINDOWS_REPO': ' C:/repo ',
          'BUTANE_WINDOWS_FLUTTER': ' C:/flutter.bat ',
        },
        onLog: (_) {},
      );

      expect(inputs.centralTarget, 'windows');
      expect(inputs.windowsHost, 'yoga-env');
      expect(inputs.windowsRepo, 'C:/repo');
      expect(inputs.windowsFlutter, 'C:/flutter.bat');
    });
  });

  test('LaunchSpec burn inputs round-trip and absent fields decode empty', () {
    final spec =
        const LaunchSpec(
          app: 'butane_harness',
          target: 'ios',
          scenario: 'smoke',
        ).withBurnInputs(
          const BurnOrderInputs(
            followerDevice: 'device',
            harnessDirectory: '/harness',
            leonardDrive: '/leonard',
          ),
        );

    expect(LaunchSpec.fromJson(spec.toJson()).toJson(), spec.toJson());
    final absent = LaunchSpec.fromJson(const {
      'app': 'butane_harness',
      'target': 'ios',
    });
    expect(absent.followerDevice, isEmpty);
    expect(absent.harnessDirectory, isEmpty);
    expect(absent.leonardDrive, isEmpty);
  });
}
