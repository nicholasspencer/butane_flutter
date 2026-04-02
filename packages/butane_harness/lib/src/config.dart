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
  const HarnessConfig({required this.role, required this.wsPort});

  factory HarnessConfig.fromEnvironment() {
    const roleString = String.fromEnvironment('ROLE', defaultValue: '');
    if (roleString.isEmpty) {
      throw StateError(
        'ROLE not set. Launch with --dart-define=ROLE=central or --dart-define=ROLE=peripheral',
      );
    }
    const wsPort = int.fromEnvironment('WS_PORT', defaultValue: 0);
    if (wsPort == 0) {
      throw StateError(
        'WS_PORT not set. Launch with --dart-define=WS_PORT=<port>',
      );
    }
    return HarnessConfig(
      role: HarnessRole.parse(roleString),
      wsPort: wsPort,
    );
  }

  final HarnessRole role;
  final int wsPort;
}
