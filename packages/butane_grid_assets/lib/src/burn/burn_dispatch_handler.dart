/// The SERVER-side burn dispatch handler — what a lessor station plugs into
/// `grid_federation`'s [StationServer] to OWN the `burn` kind (ADR-0011 D3):
/// decode the opaque bus payload as a [LaunchSpec], launch the follower app via
/// the [ButaneFollowerRunner], and return the published [FollowerEndpoint] as
/// the opaque dispatch result (the rendezvous handoff).
///
/// **The release seam (gap CLOSED).** The lessor's GUARANTEED teardown rides
/// `StationServer.start(onLeaseEnded: …)` — fired on explicit release AND
/// every reap path — which the burn's serve composition (`burn_serve.dart`)
/// wires to [ButaneFollowerRunner.teardown] (idempotent; a double reap is a
/// no-op). This handler wires the LAUNCH half; the lease end reaps.
library;

import 'package:grid_federation/grid_federation.dart';

import 'follower.dart';

void _noLog(String _) {}

/// Builds the `burn`-kind [DispatchHandler] over [runner]: parse the payload as
/// a [LaunchSpec], `launch` it (provision + build + launch the follower app,
/// publishing its endpoint), and return the endpoint's JSON as the dispatch
/// result. A launch failure throws — [StationServer] surfaces it to the lessee
/// as a failed dispatch (the `burn-follower` order fails closed).
///
/// [onLog] observes events (lib stays print-free; a CLI wires stdout).
DispatchHandler burnDispatchHandler({
  required ButaneFollowerRunner runner,
  void Function(String)? onLog,
}) {
  final log = onLog ?? _noLog;
  return (Map<String, dynamic> payload) async {
    final spec = LaunchSpec.fromJson(payload);
    log('burn dispatch: launch ${spec.app} for ${spec.target}');
    final endpoint = await runner.launch(spec);
    log('burn dispatch: published ${endpoint.vmServiceUri}');
    return endpoint.toJson();
  };
}
