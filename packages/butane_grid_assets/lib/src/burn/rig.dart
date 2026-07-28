library;

import 'dart:convert';
import 'dart:io';

import 'package:beads_dart/beads_dart.dart' show Bead, IssueType;

/// The infrastructure rig issue type, named locally: hosted beads_dart 0.1.0
/// shipped `IssueType.rig`, 0.1.1 (published from the org mainline) does not —
/// the pack must compile against both vintages, so it owns the constant.
const kRigIssueType = IssueType('rig');

/// Whether a rig device is physical hardware or an emulator/simulator.
enum RigDeviceKind {
  /// A physical device attached to its host.
  physical,

  /// A simulated or emulated device.
  emulator,
}

/// Device and host configuration carried by one infrastructure rig bead.
final class Rig {
  /// Creates an immutable rig declaration.
  const Rig({
    required this.id,
    required this.deviceUdid,
    required this.targetPlatform,
    required this.deviceKind,
    required this.hostPlatform,
    required this.capabilities,
  });

  /// Decodes the `rig.*` metadata envelope from the rig bead named [id].
  factory Rig.fromMetadata(String id, Map<String, Object?> metadata) {
    String requiredString(String key) {
      final value = metadata[key];
      if (value is! String || value.trim().isEmpty) {
        throw StateError('rig $id has invalid $key');
      }
      return value.trim();
    }

    final kindName = requiredString('rig.device_kind');
    final kind = switch (kindName) {
      'physical' => RigDeviceKind.physical,
      'emulator' => RigDeviceKind.emulator,
      _ => throw StateError('rig $id has invalid rig.device_kind: $kindName'),
    };
    final capabilitiesText = requiredString('rig.capabilities');
    Object? decodedCapabilities;
    try {
      decodedCapabilities = jsonDecode(capabilitiesText);
    } on FormatException {
      throw StateError('rig $id has invalid rig.capabilities');
    }
    if (decodedCapabilities is! List ||
        decodedCapabilities.any((value) => value is! String)) {
      throw StateError('rig $id has invalid rig.capabilities');
    }
    return Rig(
      id: id,
      deviceUdid: requiredString('rig.device_udid'),
      targetPlatform: requiredString('rig.target_platform'),
      deviceKind: kind,
      hostPlatform: requiredString('rig.host_platform'),
      capabilities: Set.unmodifiable(decodedCapabilities.cast<String>()),
    );
  }

  /// The bead id referenced by `burn.rig`.
  final String id;

  /// The device id expected in Flutter's live catalog.
  final String deviceUdid;

  /// The Flutter target platform expected for the device.
  final String targetPlatform;

  /// Whether the declared device is physical or emulated.
  final RigDeviceKind deviceKind;

  /// The platform of the host that owns the device.
  final String hostPlatform;

  /// The durable capabilities offered by this rig.
  final Set<String> capabilities;
}

/// One device reported by `flutter devices --machine`.
final class FlutterDevice {
  /// Creates one device catalog entry.
  const FlutterDevice({
    required this.id,
    required this.name,
    required this.targetPlatform,
    required this.emulator,
  });

  /// Flutter's device identifier.
  final String id;

  /// Flutter's human-readable device name.
  final String name;

  /// Flutter's target platform identifier.
  final String targetPlatform;

  /// Whether Flutter reports this device as an emulator/simulator.
  final bool emulator;
}

/// Looks up the existing bead identified by a rig id.
typedef RigBeadLookup = Future<Bead?> Function(String rigId);

/// Result shape used by the injectable Flutter command boundary.
typedef FlutterCommandResult = ({int exitCode, String stdout, String stderr});

/// Runs the Flutter executable with [arguments].
typedef FlutterCommand =
    Future<FlutterCommandResult> Function(
      String executable,
      List<String> arguments,
    );

/// Lists devices currently attached to Flutter.
abstract interface class FlutterDeviceCatalog {
  /// Returns one immutable snapshot of Flutter's attached devices.
  Future<List<FlutterDevice>> listDevices();
}

Future<FlutterCommandResult> _runFlutter(
  String executable,
  List<String> arguments,
) async {
  final result = await Process.run(executable, arguments);
  return (
    exitCode: result.exitCode,
    stdout: result.stdout as String,
    stderr: result.stderr as String,
  );
}

/// Process-backed catalog using `flutter devices --machine`.
final class ProcessFlutterDeviceCatalog implements FlutterDeviceCatalog {
  /// Creates a process-backed catalog using [flutterExecutable].
  ProcessFlutterDeviceCatalog({
    this.flutterExecutable = 'flutter',
    FlutterCommand command = _runFlutter,
  }) : _command = command;

  /// Executable used for Flutter discovery.
  final String flutterExecutable;
  final FlutterCommand _command;

  @override
  Future<List<FlutterDevice>> listDevices() async {
    final result = await _command(flutterExecutable, const [
      'devices',
      '--machine',
    ]);
    if (result.exitCode != 0) {
      throw StateError(
        'flutter devices failed (${result.exitCode}): ${result.stderr.trim()}',
      );
    }
    Object? decoded;
    try {
      decoded = jsonDecode(result.stdout);
    } on FormatException {
      throw StateError('flutter devices returned malformed JSON');
    }
    if (decoded is! List) {
      throw StateError('flutter devices returned a non-list payload');
    }
    return decoded
        .map((entry) {
          if (entry is! Map<String, dynamic> ||
              entry['id'] is! String ||
              entry['name'] is! String ||
              entry['targetPlatform'] is! String ||
              entry['emulator'] is! bool) {
            throw StateError(
              'flutter devices returned a malformed device entry',
            );
          }
          return FlutterDevice(
            id: entry['id'] as String,
            name: entry['name'] as String,
            targetPlatform: entry['targetPlatform'] as String,
            emulator: entry['emulator'] as bool,
          );
        })
        .toList(growable: false);
  }
}

/// Resolves an order's rig reference and verifies its device is attached live.
final class RigPreflight {
  /// Creates a resolver over [lookupRig] and [devices].
  const RigPreflight({required this.lookupRig, required this.devices});

  /// Injected store lookup for the referenced rig bead.
  final RigBeadLookup lookupRig;

  /// Injected live Flutter device boundary.
  final FlutterDeviceCatalog devices;

  /// Resolves `burn.rig` from [orderMetadata] to a verified live device.
  Future<({Rig rig, FlutterDevice device})> resolve(
    Map<String, Object?> orderMetadata,
  ) async {
    final rawRigId = orderMetadata['burn.rig'];
    if (rawRigId is! String || rawRigId.trim().isEmpty) {
      throw StateError('burn order is missing burn.rig');
    }
    final rigId = rawRigId.trim();
    try {
      final bead = await lookupRig(rigId);
      if (bead == null) throw StateError('was not found');
      if (bead.issueType != kRigIssueType) {
        throw StateError('has issue type ${bead.issueType}');
      }
      final rig = Rig.fromMetadata(rigId, bead.metadata);
      final live = await devices.listDevices();
      final matches = live
          .where((device) => device.id == rig.deviceUdid)
          .toList();
      if (matches.isEmpty) {
        throw StateError('device ${rig.deviceUdid} is not attached to Flutter');
      }
      if (matches.length != 1) {
        throw StateError(
          'device ${rig.deviceUdid} was reported more than once',
        );
      }
      final device = matches.single;
      final expectedEmulator = rig.deviceKind == RigDeviceKind.emulator;
      if (device.targetPlatform != rig.targetPlatform ||
          device.emulator != expectedEmulator) {
        throw StateError(
          'device ${rig.deviceUdid} does not match its platform/kind',
        );
      }
      return (rig: rig, device: device);
    } on StateError catch (error) {
      throw StateError('rig $rigId preflight failed: ${error.message}');
    } on Object catch (error) {
      throw StateError('rig $rigId preflight failed: $error');
    }
  }
}
