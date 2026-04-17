import 'dart:async';

import 'package:multicast_dns/multicast_dns.dart';

/// The mDNS service type advertised by butane harness instances.
const String _serviceType = '_butane-harness._tcp';

/// A discovered harness endpoint on the local network.
class HarnessEndpoint {
  /// Creates a [HarnessEndpoint].
  const HarnessEndpoint({
    required this.host,
    required this.port,
    required this.role,
  });

  /// The hostname or IP address of the harness.
  final String host;

  /// The port the harness WebSocket is listening on.
  final int port;

  /// The role of this harness instance (`central` or `peripheral`).
  final String role;

  @override
  String toString() => 'HarnessEndpoint($role @ $host:$port)';
}

/// The result of a successful mDNS discovery containing both harness roles.
class DiscoveredHarnesses {
  /// Creates a [DiscoveredHarnesses].
  const DiscoveredHarnesses({
    required this.central,
    required this.peripheral,
  });

  /// The central-role harness endpoint.
  final HarnessEndpoint central;

  /// The peripheral-role harness endpoint.
  final HarnessEndpoint peripheral;
}

/// Thrown when mDNS discovery times out before finding both harness roles.
class DiscoveryTimeoutException implements Exception {
  /// Creates a [DiscoveryTimeoutException].
  DiscoveryTimeoutException(this.found);

  /// Roles that were found before timeout.
  final Set<String> found;

  @override
  String toString() {
    if (found.isEmpty) {
      return 'DiscoveryTimeoutException: No harness instances found '
          'advertising $_serviceType';
    }
    final missing =
        {'central', 'peripheral'}.difference(found).join(', ');
    final have = found.join(', ');
    return 'DiscoveryTimeoutException: Found $have but not $missing';
  }
}

/// Discovers butane harness instances on the local network via mDNS.
class HarnessDiscovery {
  /// Discovers harness instances via mDNS.
  ///
  /// Performs PTR → SRV → TXT lookups for `_butane-harness._tcp` services.
  /// Polls repeatedly until both `central` and `peripheral` roles are found.
  ///
  /// If [timeout] is provided, throws [DiscoveryTimeoutException] when it
  /// expires before both roles are found. If omitted, polls indefinitely.
  ///
  /// [onProgress] is called between poll rounds with a human-readable status.
  Future<DiscoveredHarnesses> discover({
    Duration? timeout,
    void Function(String message)? onProgress,
  }) async {
    final client = MDnsClient();
    final endpoints = <String, HarnessEndpoint>{};

    try {
      await client.start();

      final completer = Completer<DiscoveredHarnesses>();

      unawaited(_pollLoop(client, endpoints, completer, onProgress));

      if (timeout != null) {
        final result = await Future.any<DiscoveredHarnesses?>([
          completer.future,
          Future<DiscoveredHarnesses?>.delayed(timeout),
        ]);
        if (result != null) return result;
        throw DiscoveryTimeoutException(endpoints.keys.toSet());
      }

      return await completer.future;
    } finally {
      client.stop();
    }
  }

  /// Repeatedly polls mDNS until both roles are discovered.
  Future<void> _pollLoop(
    MDnsClient client,
    Map<String, HarnessEndpoint> endpoints,
    Completer<DiscoveredHarnesses> completer,
    void Function(String)? onProgress,
  ) async {
    var round = 0;
    while (!completer.isCompleted) {
      round++;
      if (round > 1 && onProgress != null) {
        final found = endpoints.keys.toSet();
        if (found.isEmpty) {
          onProgress('Still looking for harness instances...');
        } else {
          final missing = {'central', 'peripheral'}.difference(found);
          onProgress(
            'Found ${found.join(", ")}, looking for ${missing.join(", ")}...',
          );
        }
      }
      await _poll(client, endpoints, completer);
      if (!completer.isCompleted) {
        await Future<void>.delayed(const Duration(seconds: 2));
      }
    }
  }

  /// Single mDNS poll pass.
  Future<void> _poll(
    MDnsClient client,
    Map<String, HarnessEndpoint> endpoints,
    Completer<DiscoveredHarnesses> completer,
  ) async {
    try {
      // PTR lookup — find all registered harness service instances.
      await for (final ptr in client.lookup<PtrResourceRecord>(
        ResourceRecordQuery.serverPointer(_serviceType),
      )) {
        if (completer.isCompleted) return;

        String? host;
        int? port;
        String? role;

        // SRV lookup — get host and port for this instance.
        await for (final srv in client.lookup<SrvResourceRecord>(
          ResourceRecordQuery.service(ptr.domainName),
        )) {
          host = srv.target;
          port = srv.port;
        }

        // TXT lookup — get role from TXT record.
        await for (final txt in client.lookup<TxtResourceRecord>(
          ResourceRecordQuery.text(ptr.domainName),
        )) {
          // TXT record text is e.g. 'role=central'
          final text = txt.text;
          for (final entry in text.split('\n')) {
            final parts = entry.split('=');
            if (parts.length == 2 && parts[0].trim() == 'role') {
              role = parts[1].trim();
            }
          }
        }

        if (host != null && port != null && role != null) {
          // Dedup by role — first discovered instance wins.
          endpoints.putIfAbsent(
            role,
            () => HarnessEndpoint(host: host!, port: port!, role: role!),
          );

          // Check if we have both roles.
          if (endpoints.containsKey('central') &&
              endpoints.containsKey('peripheral') &&
              !completer.isCompleted) {
            completer.complete(
              DiscoveredHarnesses(
                central: endpoints['central']!,
                peripheral: endpoints['peripheral']!,
              ),
            );
            return;
          }
        }
      }
    } catch (e) {
      if (!completer.isCompleted) {
        // Let the timeout handle it — don't propagate mDNS errors.
      }
    }
  }
}
