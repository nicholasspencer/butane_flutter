library;

import 'package:beads_dart/beads_dart.dart' show Bead, IssueType;

import 'burn_capabilities.dart' show kBurnCircuit;
import 'burn_order_inputs.dart';
import 'rig.dart';

/// Looks up the infrastructure rig beads visible to this landing round.
typedef BurnRigCandidates = Future<List<Bead>> Function();

/// Why a landing round deliberately minted no burn order.
enum BurnOrderSkipReason {
  /// The diff contains no supported platform path.
  noPlatformDiff,

  /// No candidate rig for the touched platform is attached and verified.
  noAttachedMatchingRig,
}

/// Inputs owned by the landing caller; paths are values, never ambient reads.
final class BurnOrderLandingRequest {
  /// Creates one immutable landing request.
  const BurnOrderLandingRequest({
    required this.orderId,
    required this.sourceBeadId,
    required this.changedPaths,
    required this.harnessDirectory,
    required this.leonardDrive,
  });

  /// Id reserved by the caller for the newly filed order.
  final String orderId;

  /// The landed work bead whose diff requires the burn.
  final String sourceBeadId;

  /// Repository-relative changed paths from the landing diff.
  final List<String> changedPaths;

  /// Explicit butane harness checkout path bound onto the order.
  final String harnessDirectory;

  /// Explicit Leonard executable path bound onto the order.
  final String leonardDrive;
}

/// Pure outcome handed back to the caller's existing filing boundary.
final class BurnOrderLandingResult {
  const BurnOrderLandingResult._({this.order, this.skipReason});

  /// A burn order was minted and is ready for the caller to persist.
  const BurnOrderLandingResult.filed(Bead order) : this._(order: order);

  /// No order was minted for the named reason.
  const BurnOrderLandingResult.skipped(BurnOrderSkipReason reason)
    : this._(skipReason: reason);

  /// The minted order, present only for a filed result.
  final Bead? order;

  /// The named skip, present only for a skipped result.
  final BurnOrderSkipReason? skipReason;
}

/// Converts a landing diff into at most one static-circuit burn order bead.
final class BurnOrderLanding {
  /// Creates the seam over candidate-rig lookup and the existing live preflight.
  const BurnOrderLanding({
    required this.lookupRigs,
    required this.devices,
    required this.onLog,
  });

  /// Candidate infrastructure rigs supplied by the landing composition.
  final BurnRigCandidates lookupRigs;

  /// Existing attached-device catalog used by [RigPreflight].
  final FlutterDeviceCatalog devices;

  /// Required loud observation boundary for every skip.
  final void Function(String message) onLog;

  /// Mints one order for the first verified rig, sorted by rig id.
  Future<BurnOrderLandingResult> file(BurnOrderLandingRequest request) async {
    final targets = _platformTargets(request.changedPaths);
    if (targets.isEmpty) {
      onLog('burn order skipped: no-platform-diff');
      return const BurnOrderLandingResult.skipped(
        BurnOrderSkipReason.noPlatformDiff,
      );
    }
    final candidates = [...await lookupRigs()];
    candidates.sort((left, right) => left.id.compareTo(right.id));
    for (final candidate in candidates) {
      try {
        final declared = Rig.fromMetadata(candidate.id, candidate.metadata);
        if (!targets.contains(declared.targetPlatform)) continue;
        final resolved = await RigPreflight(
          lookupRig: (id) async => id == candidate.id ? candidate : null,
          devices: devices,
        ).resolve({'burn.rig': candidate.id});
        final metadata = <String, dynamic>{
          'grid.circuit.formula': kBurnCircuit.id,
          'burn.rig': resolved.rig.id,
          BurnOrderInputs.followerDeviceKey: resolved.device.id,
          BurnOrderInputs.harnessDirectoryKey: request.harnessDirectory,
          BurnOrderInputs.leonardDriveKey: request.leonardDrive,
          'burn.target_platform': resolved.rig.targetPlatform,
          'burn.source_bead': request.sourceBeadId,
        };
        return BurnOrderLandingResult.filed(
          Bead(
            id: request.orderId,
            title: 'Burn ${request.sourceBeadId} on ${resolved.rig.id}',
            issueType: IssueType.task,
            metadata: metadata,
          ),
        );
      } on StateError catch (error) {
        onLog('burn rig ${candidate.id} refused: ${error.message}');
      }
    }
    final names = targets.toList()..sort();
    onLog('burn order skipped: no-attached-matching-rig:${names.join(',')}');
    return const BurnOrderLandingResult.skipped(
      BurnOrderSkipReason.noAttachedMatchingRig,
    );
  }
}

Set<String> _platformTargets(List<String> paths) {
  final targets = <String>{};
  for (final raw in paths) {
    final path = raw.replaceAll(r'\', '/');
    if (path.startsWith('packages/butane_android/') ||
        path.startsWith('packages/butane_harness/android/')) {
      targets.add('android');
    }
    if (path.startsWith('packages/butane_core_bluetooth/')) {
      targets.addAll(const {'ios', 'macos'});
    }
    if (path.startsWith('packages/butane_dart_bluez/') ||
        path.startsWith('packages/butane_bluez/') ||
        path.startsWith('packages/butane_harness/linux/')) {
      targets.add('linux');
    }
    if (path.startsWith('packages/butane_windows/')) targets.add('windows');
    if (path.startsWith('packages/butane_harness/ios/')) targets.add('ios');
    if (path.startsWith('packages/butane_harness/macos/')) targets.add('macos');
  }
  return targets;
}
