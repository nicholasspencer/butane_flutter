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
  const HarnessConfig({required this.role, required this.wsPort});

  /// Creates config from compile-time dart-define values.
  ///
  /// Launch with:
  ///   --dart-define=ROLE=central --dart-define=WS_PORT=9100
  factory HarnessConfig.fromEnvironment() {
    // Try compile-time dart-defines first.
    const roleString = String.fromEnvironment('ROLE', defaultValue: '');
    const wsPort = int.fromEnvironment('WS_PORT', defaultValue: 0);

    // Fall back to runtime environment variables (for direct binary launch).
    final effectiveRole =
        roleString.isNotEmpty ? roleString : Platform.environment['ROLE'] ?? '';
    final effectivePort = wsPort != 0
        ? wsPort
        : int.tryParse(Platform.environment['WS_PORT'] ?? '') ?? 0;

    if (effectiveRole.isEmpty) {
      throw StateError(
        'ROLE not set. Launch with --dart-define=ROLE=central '
        'or set ROLE environment variable.',
      );
    }
    if (effectivePort == 0) {
      throw StateError(
        'WS_PORT not set. Launch with --dart-define=WS_PORT=<port> '
        'or set WS_PORT environment variable.',
      );
    }
    return HarnessConfig(
      role: HarnessRole.parse(effectiveRole),
      wsPort: effectivePort,
    );
  }

  final HarnessRole role;
  final int wsPort;
}
