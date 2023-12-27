part of '../interface.dart';

/// A service that use is used from a "Central" perspective to scan for
/// and interact with peripherals.
base class CentralManager extends PeerManager<Peripheral> {
  CentralManager({
    @visibleForTesting super.peers,
    @visibleForTesting super.platform,
  });

  Stream<Peripheral> scan({
    List<UuidIdentifier>? forServices,
  }) {
    return platform.scan(
      forServices: forServices,
    );
  }

  Future<Iterable<Peripheral>> connectedPeripherals({
    List<UuidIdentifier> services = const [],
  }) async {
    return platform.connectedPeripherals(
      services: services,
    );
  }

  Future<Iterable<Peripheral>> peripherals({
    List<Identifier> identifiers = const [],
  }) async {
    return platform.peripherals(
      identifiers: identifiers,
    );
  }
}
