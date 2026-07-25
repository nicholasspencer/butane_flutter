import 'dart:io';

enum HarnessRole {
  central,
  peripheral;

  static HarnessRole parse(String value) {
    switch (value.toLowerCase()) {
      case 'central':
        return HarnessRole.central;
      case 'peripheral':
        return HarnessRole.peripheral;
      default:
        throw ArgumentError(
          'Invalid ROLE "$value". Must be "central" or "peripheral".',
        );
    }
  }

  String get displayName => switch (this) {
        HarnessRole.central => 'Central',
        HarnessRole.peripheral => 'Peripheral',
      };
}

class HarnessConfig {
  const HarnessConfig({required this.role});

  factory HarnessConfig.fromEnvironment() {
    const roleDefine = String.fromEnvironment('ROLE', defaultValue: '');
    final role =
        roleDefine.isNotEmpty ? roleDefine : Platform.environment['ROLE'] ?? '';
    if (role.isEmpty) {
      throw StateError(
        'ROLE not set. Launch with --dart-define=ROLE=central '
        'or set ROLE environment variable.',
      );
    }
    return HarnessConfig(role: HarnessRole.parse(role));
  }

  final HarnessRole role;
}
