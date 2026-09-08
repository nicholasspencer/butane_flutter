import 'dart:convert';

/// The environment capability required before a burn may start.
enum BurnPreconditionKind {
  /// The declared follower is attached as a physical iOS device.
  followerIosAttached,

  /// The configured Windows host accepts a non-interactive SSH command.
  windowsHostReachable,

  /// The declared TCP peer accepts a connection.
  peerAnswering,
}

/// One canonical environment precondition declared by a burn order.
final class BurnPrecondition {
  const BurnPrecondition._({required this.kind, this.host, this.port});

  /// Requires the configured follower to be attached as a physical iOS device.
  const BurnPrecondition.followerIosAttached()
    : this._(kind: BurnPreconditionKind.followerIosAttached);

  /// Requires the configured Windows host to accept a non-interactive SSH command.
  const BurnPrecondition.windowsHostReachable()
    : this._(kind: BurnPreconditionKind.windowsHostReachable);

  /// Requires a TCP connection to [host] on [port].
  const BurnPrecondition.peer({required String host, required int port})
    : this._(kind: BurnPreconditionKind.peerAnswering, host: host, port: port);

  /// Parses one canonical burn precondition declaration.
  factory BurnPrecondition.parse(String declaration) {
    switch (declaration) {
      case 'follower-ios-attached':
        return const BurnPrecondition.followerIosAttached();
      case 'windows-host-reachable':
        return const BurnPrecondition.windowsHostReachable();
    }
    final peer = RegExp(r'^peer=([^:\s]+):([0-9]+)$').firstMatch(declaration);
    if (peer == null) {
      throw FormatException('unknown burn precondition', declaration);
    }
    final host = peer.group(1)!;
    final port = int.tryParse(peer.group(2)!);
    if (port == null || port < 1 || port > 65535) {
      throw FormatException('invalid burn peer precondition', declaration);
    }
    return BurnPrecondition.peer(host: host, port: port);
  }

  /// The kind of environment capability this declaration requires.
  final BurnPreconditionKind kind;

  /// The peer host when [kind] is [BurnPreconditionKind.peerAnswering].
  final String? host;

  /// The peer port when [kind] is [BurnPreconditionKind.peerAnswering].
  final int? port;

  /// The canonical metadata declaration.
  String get declaration => switch (kind) {
    BurnPreconditionKind.followerIosAttached => 'follower-ios-attached',
    BurnPreconditionKind.windowsHostReachable => 'windows-host-reachable',
    BurnPreconditionKind.peerAnswering => 'peer=$host:$port',
  };
}

/// Inputs carried by a burn ORDER bead.
final class BurnOrderInputs {
  const BurnOrderInputs({
    required this.followerDevice,
    required this.harnessDirectory,
    required this.leonardDrive,
    this.followerTarget = 'ios',
    this.centralTarget = 'macos',
    this.windowsHost = 'yoga-win',
    this.windowsRepo = r'C:/Users/nicks/butane_flutter',
    this.windowsFlutter = r'C:/Users/nicks/fvm/versions/stable/bin/flutter.bat',
    this.preconditions = const [],
  });

  static const followerDeviceKey = 'burn.follower_device';
  static const harnessDirectoryKey = 'burn.harness_dir';
  static const leonardDriveKey = 'burn.leonard_drive';
  static const followerTargetKey = 'burn.follower_target';
  static const centralTargetKey = 'burn.central_target';
  static const windowsHostKey = 'burn.windows_host';
  static const windowsRepoKey = 'burn.windows_repo';
  static const windowsFlutterKey = 'burn.windows_flutter';
  static const preconditionsKey = 'burn.preconditions';

  final String followerDevice;
  final String harnessDirectory;
  final String leonardDrive;
  final String followerTarget;
  final String centralTarget;
  final String windowsHost;
  final String windowsRepo;
  final String windowsFlutter;
  final List<BurnPrecondition> preconditions;

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

    List<BurnPrecondition> readPreconditions() {
      if (!metadata.containsKey(preconditionsKey)) return const [];
      final raw = metadata[preconditionsKey];
      if (raw is String && raw.trim().isEmpty) return const [];

      Never invalid() =>
          throw StateError('burn input $preconditionsKey invalid: $raw');

      if (raw is! String) invalid();
      final Object? decoded;
      try {
        decoded = jsonDecode(raw);
      } on FormatException {
        invalid();
      }
      if (decoded is! List) invalid();
      final declarations = <String>{};
      final preconditions = <BurnPrecondition>[];
      for (final value in decoded) {
        if (value is! String) invalid();
        final BurnPrecondition precondition;
        try {
          precondition = BurnPrecondition.parse(value);
        } on FormatException {
          invalid();
        }
        if (!declarations.add(precondition.declaration)) invalid();
        preconditions.add(precondition);
      }
      return List.unmodifiable(preconditions);
    }

    return BurnOrderInputs(
      followerDevice: read(followerDeviceKey, 'BURN_IOS_DEVICE'),
      harnessDirectory: read(harnessDirectoryKey, 'BURN_HARNESS_DIR'),
      leonardDrive: read(leonardDriveKey, 'LEONARD_DRIVE'),
      followerTarget: read(followerTargetKey, 'BURN_FOLLOWER_TARGET', 'ios'),
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
      preconditions: readPreconditions(),
    );
  }
}
