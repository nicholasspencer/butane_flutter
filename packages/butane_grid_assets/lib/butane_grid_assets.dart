/// The butane burn asset domain (ADR-0011 D9, M6 Track F) — the cross-station
/// BURN formula, offline end-to-end.
///
/// The burn is two capability-scoped orders + two orthogonal channels:
///  - **orders** — `burn-follower` ([BurnFollowerCapability]) leased to a
///    capability match + `burn-host` ([BurnHostCapability]) local, composed into
///    [kBurnCircuit] at the engine Capability seam (mirroring
///    `grid_assets/src/code`);
///  - **channels** — the federation BUS (lease + endpoint rendezvous, via
///    the federation bus) and the DIRECT `leonard_drive` ↔
///    `ext.exploration.*` perception channel ([LeonardDrive]), kept orthogonal.
///
/// The follower side ([ButaneFollowerRunner]) provisions/builds/launches the
/// app-under-test exposing exploration ([FollowerLauncher]), publishes its
/// [FollowerEndpoint], and is GUARANTEED to be torn down via the M4
/// `terminateGroup`/pgid reaper. The host runs a SCRIPTED [DriveScenario] (zero
/// inference) and collects a domain [TestReport].
///
/// The LIVE-LOCAL entry pieces (the away-run M-C): [ProcessLeonardDrive] (the
/// real drive — shells lenny's credential-free `leonard_drive` per call),
/// [burnDispatchHandler] (the server-side `burn`-kind dispatch a lessor plugs
/// into a `StationServer`), and [LocalDartFollowerLauncher] (the
/// pipeline-proof follower: a hermetic pure-Dart exploration-hosting daemon in
/// its own process group — butane stays untouched).
///
/// Home: `butane_flutter` — grid assets live with their system (the ADR-0011
/// build-order placement split, landed; the power_station home was the interim).
library;

export 'src/burn/burn_capabilities.dart';
export 'src/burn/burn_dispatch_handler.dart';
export 'src/burn/burn_report.dart';
export 'src/burn/burn_scenario.dart';
export 'src/burn/burn_serve.dart';
export 'src/burn/butane_follower_launcher.dart';
export 'src/burn/follower.dart';
export 'src/burn/ios_follower_launcher.dart';
export 'src/burn/launch_scrape.dart';
export 'src/burn/local_follower_launcher.dart';
export 'src/burn/process_leonard_drive.dart';
export 'src/burn/scenarios.dart';
