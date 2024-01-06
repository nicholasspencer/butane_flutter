part of '../interface.dart';

/// A service that use is used from a "Peripheral" perspective to advertise
/// and interact with centrals.
base class PeripheralManager extends PeerManager<Central> {
  PeripheralManager({
    super.clientIdentifier,
    @visibleForTesting super.peers,
    @visibleForTesting super.platform,
  });
}
