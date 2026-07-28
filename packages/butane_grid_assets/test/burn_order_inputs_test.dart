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
        },
        environment: const {
          'BURN_IOS_DEVICE': 'environment-device',
          'BURN_HARNESS_DIR': '/environment/harness',
          'LEONARD_DRIVE': '/environment/leonard',
        },
        onLog: logs.add,
      );

      expect(inputs.followerDevice, 'order-device');
      expect(inputs.harnessDirectory, '/order/harness');
      expect(inputs.leonardDrive, '/order/leonard');
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
