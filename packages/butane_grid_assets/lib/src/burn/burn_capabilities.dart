/// The BURN — two capability-scoped orders + two orthogonal channels (ADR-0011
/// D9, M6 Track F), composed at the engine `SessionResolver`/Capability seam
/// (mirroring `grid_assets/src/code`).
///
/// [kBurnCircuit] pours two orders:
///  - **`burn-follower`** ([BurnFollowerCapability]) — LEASED to a peer whose
///    capability profile satisfies the follower requirements by CONTAINMENT
///    (Track C; e.g. `{system-os=macos, flutter-target=ios, radio=ble}`). It
///    leases a slot over the federation BUS, dispatches the launch, and receives
///    the follower's published endpoint (the rendezvous). Declared a
///    [StepKind.daemon] — the follower app is a long-lived daemon on the peer
///    that stays up for the host's drive; on unmount the lease releases → the
///    peer reaps the app.
///  - **`burn-host`** ([BurnHostCapability]) — LOCAL. It awaits the follower
///    endpoint (read pull-free through the threaded `SiblingView`, D-5), attaches
///    `leonard_drive` over the DIRECT perception channel (NOT the bus), runs a
///    SCRIPTED scenario, and collects a [TestReport].
///
/// Two ORTHOGONAL channels (the load-bearing call, ADR-0011 D9):
///  1. the federation BUS = rendezvous + lifecycle (lossy: lease → grant →
///     endpoint handoff → release/teardown), via [StationClient];
///  2. the DIRECT perception channel = `leonard_drive` ↔ `ext.exploration.*`,
///     point-to-point, NEVER tunneled through the bus.
///
/// A capability reads its ambient values (the [SiblingView] rendezvous, the
/// work bead) with the effect verb (`getInheritedSeedOfExactType`) at entry and
/// holds no writer/notifier — the four derailment-invariants hold at depth by
/// layering + the host's single write-locus.
library;

import 'dart:io';

import 'package:beads_dart/beads_dart.dart' show Bead;
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_assets/grid_assets.dart' show BusLease;
import 'package:grid_engine/grid_engine.dart';

import 'burn_report.dart';
import 'burn_order_inputs.dart';
import 'burn_scenario.dart';
import 'follower.dart';
import 'remote_windows_host_launch.dart';

/// The burn resource-asset kind label — what a `burn-follower` order leases. The
/// federation core treats `kind` as an opaque, equality-checked string; this is
/// the BURN domain naming its own kind (ADR-0011 D3).
const String kBurnKind = 'burn';

/// The `burn-follower` step/capability id (the leased order).
const String kBurnFollowerStep = 'burn-follower';

/// The `burn-host` step/capability id (the local order).
const String kBurnHostStep = 'burn-host';

/// The default follower capability requirements (ADR-0011 D9): a macOS peer
/// that can build+deploy a `flutter-target=ios` app to its attached device and
/// exposes a BLE radio. Matched by CONTAINMENT against a peer's advertised
/// profile (Track C; ADR-0011 D6).
final CapabilityFacts kDefaultFollowerRequires = const CapabilityFacts(
  sets: {
    kSystemOs: {'macos'},
    kFlutterTarget: {'ios'},
    kRadio: {'ble'},
  },
);

/// The burn formula (ADR-0011 D9) — the two capability-scoped orders + the
/// rendezvous barrier. `burn-host` `dependsOn` `burn-follower`'s positive
/// terminal (the daemon's `ready` — the endpoint is published), so the host never
/// drives before the follower is up. `restForOne` re-keys a failed step ∪ its
/// dependents (the Burn's strategy, formula.dart); the terminal step is the host,
/// whose completion closes the session (D-2).
const Circuit kBurnCircuit = Circuit(
  id: 'burn',
  terminalStepId: kBurnHostStep,
  supervision: SupervisionStrategy.restForOne,
  steps: [
    CapabilityStep(
      stepId: kBurnFollowerStep,
      capabilityId: kBurnFollowerStep,
      kind: StepKind.daemon,
    ),
    CapabilityStep(
      stepId: kBurnHostStep,
      capabilityId: kBurnHostStep,
      dependsOn: {kBurnFollowerStep},
    ),
  ],
);

void _noLog(String _) {}

/// A candidate follower peer on the federation bus — its kind-agnostic transport
/// [client], labelled by [id]. The host probes each candidate's presence to find
/// a CONTAINMENT match for the follower requirements.
class FollowerPeer {
  /// Creates a candidate peer [id] reachable over [client].
  const FollowerPeer({required this.id, required this.client});

  /// The peer's station id / human label.
  final String id;

  /// The bus to the peer (the pluggable, kind-agnostic transport seam).
  final StationClient client;
}

/// Selects the first of [peers] whose advertised capability profile SATISFIES
/// [requires] by CONTAINMENT (Track C; ADR-0011 D6) — `station.facts ⊨ requires`.
/// Probes each peer's presence (the DURABLE profile half of the gossip) and
/// returns the first match, or `null` when none matches (fail-closed → the
/// `burn-follower` order is denied). A peer whose presence cannot be read is
/// skipped (it is not a match). (An observation.)
Future<FollowerPeer?> matchFollower({
  required List<FollowerPeer> peers,
  required CapabilityFacts requires,
  void Function(String)? onLog,
}) async {
  final log = onLog ?? _noLog;
  for (final peer in peers) {
    final Presence presence;
    try {
      presence = await peer.client.presence();
    } on FederationException catch (e) {
      log('match: skip ${peer.id} — presence failed: ${e.message}');
      continue;
    }
    final facts = CapabilityFacts.fromProfile(presence.profile);
    if (CapabilityFacts.matches(facts, requires)) {
      log('match: ${peer.id} satisfies $requires');
      return peer;
    }
  }
  log('match: no peer satisfies $requires');
  return null;
}

/// The `burn-follower` order (ADR-0011 D9): lease a matching peer over the bus,
/// dispatch the launch, and receive the follower's published endpoint.
///
/// A HELD daemon lease (ADR-0009 D6 / "leasing is core"): a first-class core
/// [LeaseCapability] over a [BusLease] handle. The engine drives it as a
/// [LeaseAllocation] — [acquire] matches a peer by containment + leases its slot;
/// [dispatchOn] launches the follower + returns its published endpoint as the
/// rendezvous [Ok] payload; [proveFresh]/[release] heartbeat/release over the bus.
/// Because the burn formula's step is [StepKind.daemon], the allocation reports
/// `ready` (a positive terminal that STAYS LIVE, publishing the endpoint) — NOT
/// `complete`. That is the daemon-reap bug the rebuild fixed: the old
/// `Expando<_FollowerHold>` + `Ok`-as-complete shape retired a live daemon (the
/// exact ADR-0009 D1 smell). The grant now lives on the [LeaseAllocation]; `dispose`
/// RELEASES it (→ the peer reaps the launched app via its own `terminateGroup`
/// reaper), even on the failure path.
class BurnFollowerCapability extends LeaseCapability<BusLease> {
  /// Creates the order over the candidate [peers], the [launchSpec] to dispatch,
  /// and the [requires] the peer must satisfy by containment. [lessee] defaults to
  /// the work bead id at mount.
  BurnFollowerCapability({
    required this.peers,
    required this.launchSpec,
    CapabilityFacts? requires,
    this.lessee = '',
    Map<String, String>? environment,
    void Function(String)? onLog,
  }) : requires = requires ?? kDefaultFollowerRequires,
       environment = environment ?? Platform.environment,
       _onLog = onLog ?? _noLog;

  /// The candidate follower peers (matched by containment at mount).
  final List<FollowerPeer> peers;

  /// The launch payload dispatched to the matched follower.
  final LaunchSpec launchSpec;

  /// The capability facts the follower peer must satisfy (containment).
  final CapabilityFacts requires;

  /// The lessee station id (empty ⇒ the work bead id at mount).
  final String lessee;

  /// Compatibility environment consulted only when ORDER metadata is absent.
  final Map<String, String> environment;

  final void Function(String) _onLog;

  /// A stable per-node idempotency key so a retried lease/dispatch dedups at the
  /// owner (never a second grant or a second launch — the lossy-bus hazard).
  String _idem(StepArgs args) =>
      '${lessee.isEmpty ? args.beadId : lessee}/${args.nodePath}';

  @override
  Future<LeaseResolution<BusLease>> acquire(
    TreeContext context,
    StepArgs args,
  ) async {
    final who = lessee.isEmpty ? args.beadId : lessee;

    // MATCH a peer by containment (Track C). Fail-closed: no match → no order.
    final peer = await matchFollower(
      peers: peers,
      requires: requires,
      onLog: _onLog,
    );
    if (args.cancel.isCancelled) return const LeaseUnavailable('cancelled');
    if (peer == null) {
      return LeaseUnavailable('no follower peer satisfies $requires');
    }

    // LEASE the matched peer's slot over the bus.
    final LeaseGrant grant;
    try {
      grant = await peer.client.requestLease(
        LeaseRequest(lessee: who, kind: kBurnKind, idempotencyKey: _idem(args)),
      );
    } on LeaseDeniedException catch (e) {
      return LeaseUnavailable('follower lease denied: ${e.message}');
    }
    if (args.cancel.isCancelled) {
      await peer.client.release(grant);
      return const LeaseUnavailable('cancelled');
    }
    _onLog('follower leased ${grant.leaseId} on ${peer.id}');
    return LeaseBound((client: peer.client, grant: grant));
  }

  @override
  Future<StepOutcome> dispatchOn(
    BusLease handle,
    TreeContext context,
    StepArgs args,
  ) async {
    final bead = context.getInheritedSeedOfExactType<Bead>();
    if (bead == null) {
      return Failed('burn-follower requires ambient work bead ${args.beadId}');
    }
    final inputs = BurnOrderInputs.resolve(
      metadata: bead.metadata,
      environment: environment,
      onLog: _onLog,
    );
    final dispatchedSpec = launchSpec.withBurnInputs(inputs);

    // DISPATCH the launch over the bus → the follower publishes its endpoint
    // (the rendezvous handoff rides the dispatch result).
    final Map<String, dynamic> raw;
    try {
      raw = await handle.client.dispatch(
        handle.grant,
        dispatchedSpec.toJson(),
        idempotencyKey: _idem(args),
      );
    } on LeaseInvalidException catch (e) {
      return Failed('follower launch dispatch failed: ${e.message}');
    }
    if (args.cancel.isCancelled) return const Failed('cancelled');

    final endpoint = FollowerEndpoint.fromJson(raw);
    if (!endpoint.isPublished) {
      return const Failed('follower published no endpoint');
    }
    _onLog('follower published ${endpoint.vmServiceUri}');

    // The endpoint rides the daemon's `ready` payload → recorded on the session
    // bead, read by `burn-host` pull-free through the threaded `SiblingView`
    // (D-5). A daemon `ready` stays live; `dispose` releases the held lease.
    return Ok({
      'endpoint': endpoint.vmServiceUri,
      'station': endpoint.station,
      'lease': handle.grant.leaseId,
      'target': launchSpec.target,
    });
  }

  @override
  Future<bool> proveFresh(
    BusLease handle,
    TreeContext context,
    StepArgs args,
  ) async {
    // The daemon adopt freshness proof (live-arm): a fenced heartbeat succeeds
    // only for a grant still live AND ours. Offline this is unreached (adoptable
    // defaults null ⇒ no adopt); wired for the cross-machine arm.
    try {
      await handle.client.heartbeat(handle.grant);
      return !args.cancel.isCancelled;
    } on FederationException {
      return false;
    }
  }

  @override
  Future<void> release(BusLease handle) async {
    // Releasing the lease is what triggers the peer to reap the launched follower
    // app (the guaranteed teardown crosses the bus). Idempotent for the holder.
    try {
      await handle.client.release(handle.grant);
      _onLog('follower lease released ${handle.grant.leaseId}');
      _onLog(
        'teardown-receipt: follower lease released ${handle.grant.leaseId}',
      );
    } on FederationException {
      // Already reaped/invalid — release is idempotent.
    }
  }
}

/// The mutable, per-mount hold for [BurnHostCapability] — the collected report.
class _HostHold {
  TestReport? report;
}

/// One reusable in-process follower launch/reap lifecycle.
final class LocalFollowerLaunch implements HostHarnessLaunch {
  /// Creates the lifecycle over the existing guaranteed-reap [runner].
  LocalFollowerLaunch({required this.runner, void Function(String)? onLog})
    : _onLog = onLog ?? _noLog;

  /// The existing coordinator that owns launch and once-only process-group reap.
  final ButaneFollowerRunner runner;
  final void Function(String) _onLog;

  /// Launches [spec] in process and returns its published endpoint.
  @override
  Future<FollowerEndpoint> launch(LaunchSpec spec) => runner.launch(spec);

  /// Reaps the launched process group once and emits the resident receipt.
  @override
  Future<void> teardown() async {
    await runner.teardown();
    _onLog('teardown-receipt: resident follower reaped');
  }
}

/// The `burn-host` order (ADR-0011 D9): await the follower endpoint, attach
/// `leonard_drive` over the DIRECT perception channel — and, for the
/// TWO-DRIVE burn, launch the host's own LOCAL harness (the central, per the
/// convention: the leased follower runs the peripheral) and attach a second
/// drive to it — then run a SCRIPTED scenario and collect a [TestReport].
///
/// It reads the follower's published endpoint pull-free through the AMBIENT
/// [SiblingView] (mounted by `SessionScope`; read with the effect verb — D-5,
/// never a subscription/re-query — invariant 1). The drive is
/// the SECOND, orthogonal channel: point-to-point over the follower's VM service,
/// NOT tunneled through the federation bus. UNMOUNT (`teardown`) closes both
/// drive channels and reaps the local harness through [localRunner]'s
/// once-only reaper (the follower app teardown stays the `burn-follower`
/// order's lease release).
class BurnHostCapability extends ServiceCapability {
  /// Creates the host order driving [scenario] over [drive]. [followerStep] is
  /// the sibling step id whose published endpoint to read (default
  /// [kBurnFollowerStep]). For the two-drive burn pass [localRunner] (launch +
  /// guaranteed reap on the host box), [localSpec] (conventionally
  /// `role: central`), and [localDrive] (the second perception channel) —
  /// all three together, or none.
  BurnHostCapability({
    required this.drive,
    required this.scenario,
    this.followerStep = kBurnFollowerStep,
    HostHarnessLaunch? hostLaunch,
    this.localRunner,
    this.localSpec,
    this.localDrive,
    void Function(String)? onLog,
  }) : hostLaunch =
           hostLaunch ??
           (localRunner == null
               ? null
               : LocalFollowerLaunch(runner: localRunner, onLog: onLog)),
       _onLog = onLog ?? _noLog {
    final given = [
      this.hostLaunch,
      localSpec,
      localDrive,
    ].where((p) => p != null).length;
    if (given != 0 && given != 3) {
      throw ArgumentError(
        'two-drive burn-host needs hostLaunch + localSpec + localDrive '
        'together (got $given of 3)',
      );
    }
  }

  /// The direct perception channel to the FOLLOWER (`leonard_drive`; a
  /// scripted fake offline).
  final LeonardDrive drive;

  /// The SCRIPTED scenario to run (zero inference).
  final DriveScenario scenario;

  /// The sibling step id whose published endpoint to await + drive.
  final String followerStep;

  /// Launches + reaps the host's LOCAL harness (two-drive burn); null for a
  /// follower-only burn.
  final ButaneFollowerRunner? localRunner;

  /// Launches and reaps the central harness.
  final HostHarnessLaunch? hostLaunch;

  /// What the central harness boots as (conventionally `role: central`).
  final LaunchSpec? localSpec;

  /// The perception channel to the LOCAL harness.
  final LeonardDrive? localDrive;

  final void Function(String) _onLog;

  static final Expando<_HostHold> _holds = Expando<_HostHold>(
    'grid-burn-host-hold',
  );

  @override
  Future<StepOutcome> run(TreeContext context, StepArgs args) async {
    // The per-incarnation hold is keyed by the [StepArgs] identity — the host
    // hands the SAME instance to run + teardown + reportFor.
    final hold = _holds[args] = _HostHold();
    final configuredCentralTarget = localSpec?.target ?? '';
    var reportEndpoint = '';
    var centralIdentity = '';
    var centralLaunchOutcome = BurnLaunchOutcome.notObserved;
    var followerIdentity = '';
    var followerTarget = BurnStepOutcome.notObserved.wire;
    var followerLaunchOutcome = BurnLaunchOutcome.notObserved;

    TestReport unobservedReport() => unobservedDriveReport(
      scenario: scenario,
      endpoint: reportEndpoint,
      central: configuredCentralTarget.isEmpty
          ? BurnStepOutcome.notObserved.wire
          : configuredCentralTarget,
      follower: followerTarget,
      centralIdentity: centralIdentity,
      centralLaunchOutcome: centralLaunchOutcome,
      followerIdentity: followerIdentity,
      followerLaunchOutcome: followerLaunchOutcome,
    );

    void retainUnobservedReport() {
      hold.report = unobservedReport();
    }

    retainUnobservedReport();

    // AWAIT the follower endpoint, read pull-free from the AMBIENT sibling
    // view at ENTRY (the effect verb, D-5).
    final siblings =
        context.getInheritedSeedOfExactType<SiblingView>() ??
        const SiblingView();
    final followerPath = '${_parentPath(args.nodePath)}/$followerStep';
    final published = siblings.resultOf(followerPath);
    final uri = published['endpoint'] ?? '';
    if (uri.isEmpty) {
      return _failedWithEvidence(
        'no follower endpoint (rendezvous failed)',
        hold.report!,
      );
    }
    reportEndpoint = uri;
    followerIdentity = published['station'] ?? '';
    followerTarget = published['target'] ?? BurnStepOutcome.notObserved.wire;
    followerLaunchOutcome = BurnLaunchOutcome.launched;
    retainUnobservedReport();
    if (followerTarget == BurnStepOutcome.notObserved.wire ||
        followerTarget.isEmpty) {
      return _failedWithEvidence(
        'follower rendezvous published no target',
        hold.report!,
      );
    }
    final centralLaunch = hostLaunch;
    if (centralLaunch != null && configuredCentralTarget.isEmpty) {
      return _failedWithEvidence(
        'two-drive burn published no central target',
        hold.report!,
      );
    }
    final endpoint = FollowerEndpoint(
      vmServiceUri: uri,
      station: published['station'] ?? '',
      leaseId: published['lease'] ?? '',
    );
    if (args.cancel.isCancelled) {
      return _failedWithEvidence('cancelled', hold.report!);
    }

    // ATTACH the DIRECT perception channel (NOT the bus) + run the SCRIPTED
    // scenario. The drive is closed in teardown (the guaranteed channel teardown).
    await drive.attach(endpoint);
    if (args.cancel.isCancelled) {
      return _failedWithEvidence('cancelled', hold.report!);
    }
    _onLog('host attached leonard_drive to ${endpoint.vmServiceUri}');

    // TWO-DRIVE burn: launch the host's own local harness (the central) and
    // attach the second drive. A local launch failure fails the order —
    // teardown still reaps whatever launched (the runner is once-only).
    if (centralLaunch != null) {
      final FollowerEndpoint centralEndpoint;
      try {
        centralEndpoint = await centralLaunch.launch(localSpec!);
      } on Object catch (e) {
        centralLaunchOutcome = BurnLaunchOutcome.failed;
        retainUnobservedReport();
        final label = centralLaunch is LocalFollowerLaunch
            ? 'local'
            : 'central';
        return _failedWithEvidence(
          '$label harness launch failed: $e',
          hold.report!,
        );
      }
      centralIdentity = centralEndpoint.station;
      centralLaunchOutcome = BurnLaunchOutcome.launched;
      retainUnobservedReport();
      if (args.cancel.isCancelled) {
        return _failedWithEvidence('cancelled', hold.report!);
      }
      await localDrive!.attach(centralEndpoint);
      if (args.cancel.isCancelled) {
        return _failedWithEvidence('cancelled', hold.report!);
      }
      _onLog(
        'host attached central leonard_drive to ${centralEndpoint.vmServiceUri}',
      );
    }

    final report = await runDriveScenario(
      drive: drive,
      scenario: scenario,
      endpoint: endpoint,
      central: configuredCentralTarget,
      follower: followerTarget,
      centralIdentity: centralIdentity,
      centralLaunchOutcome: centralLaunchOutcome,
      centralTeardownConfirmation: BurnTeardownConfirmation.notObserved,
      followerIdentity: followerIdentity,
      followerLaunchOutcome: followerLaunchOutcome,
      followerTeardownConfirmation: BurnTeardownConfirmation.notObserved,
      localDrive: localDrive,
      isCancelled: () => args.cancel.isCancelled,
    );
    hold.report = report;
    if (args.cancel.isCancelled) {
      return _failedWithEvidence('cancelled', report);
    }

    _onLog('host collected report: $report');
    if (report.passed) _onLog(report.receipt);
    return report.passed
        ? Ok(burnResultPayload(report))
        : _failedWithEvidence(
            'burn scenario "${report.scenario}" failed: '
            '${report.failures}/${report.total} step(s)',
            report,
          );
  }

  // The engine's Failed arm has no payload by contract, so this bounded digest
  // is the only durable failure carrier. Returning Ok for a failed burn would
  // suppress supervision and is therefore not an evidence-preserving option.
  Failed _failedWithEvidence(String reason, TestReport report) =>
      Failed('$reason ${burnFailureDigest(report)}');

  /// The report the mount driven by [args] collected (for tests /
  /// introspection), or `null`.
  TestReport? reportFor(StepArgs args) => _holds[args]?.report;

  @override
  Future<void> teardown(StepArgs args) async {
    // Close the DIRECT perception channels (idempotent) and reap the local
    // harness (once-only runner; even on the failure path). The follower app
    // is reaped by the `burn-follower` order's lease release (the bus
    // channel teardown).
    await drive.close();
    _onLog('follower drive closed');
    _onLog('teardown-receipt: follower drive closed');
    final localDrive = this.localDrive;
    if (localDrive != null) {
      await localDrive.close();
      _onLog('central drive closed');
      _onLog('teardown-receipt: central drive closed');
      if (hostLaunch is LocalFollowerLaunch) {
        _onLog('local drive closed');
        _onLog('teardown-receipt: local drive closed');
      }
    }
    await hostLaunch?.teardown();
    _holds[args] = null;
  }
}

/// The parent node path of [nodePath] (`'a/b/burn-host'` → `'a/b'`), so the host
/// computes its sibling `burn-follower` path (`'$parent/burn-follower'`).
String _parentPath(String nodePath) {
  final i = nodePath.lastIndexOf('/');
  return i < 0 ? '' : nodePath.substring(0, i);
}

/// Builds the `burn` registry (mirrors `grid_assets`'s `buildCodeRegistry`): the
/// two burn orders + [kBurnCircuit], with an optional injected [clock] (the
/// backoff seam). A composer provides it as a stable `InheritedSeed<CapabilityRegistry>`
/// above `Station`, alongside a circuit resolver — the live
/// `composeRunTree` swap is the cross-machine arm's concern (Track H).
///
/// [peers]/[launchSpec]/[requires] parameterize the follower order; [drive]/
/// [scenario] the host order; [localRunner]/[localSpec]/[localDrive] (all or
/// none) arm the two-drive host. Offline these are fakes; the live arm wires
/// real `StationClient`s + `leonard_drive` + a real launcher.
DefaultCapabilityRegistry buildBurnRegistry({
  required List<FollowerPeer> peers,
  required LaunchSpec launchSpec,
  required LeonardDrive drive,
  required DriveScenario scenario,
  CapabilityFacts? requires,
  ButaneFollowerRunner? localRunner,
  LaunchSpec? localSpec,
  LeonardDrive? localDrive,
  void Function(String)? onLog,
  DateTime Function()? clock,
}) => DefaultCapabilityRegistry(
  capabilities: {
    kBurnFollowerStep: BurnFollowerCapability(
      peers: peers,
      launchSpec: launchSpec,
      requires: requires,
      onLog: onLog,
    ),
    kBurnHostStep: BurnHostCapability(
      drive: drive,
      scenario: scenario,
      localRunner: localRunner,
      localSpec: localSpec,
      localDrive: localDrive,
      onLog: onLog,
    ),
  },
  circuits: const {'burn': kBurnCircuit},
  clock: clock,
);
