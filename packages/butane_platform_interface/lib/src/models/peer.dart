part of '../interface.dart';

abstract base class Peer {
  const Peer({
    required this.manager,
    required this.identifier,
  });

  @protected
  final PeerManager manager;

  final Identifier identifier;

  @protected
  api.PeripheralSessionIdentifier get sessionIdentifier =>
      api.PeripheralSessionIdentifier(
        identifier: identifier.toString(),
        clientIdentifier: manager.clientIdentifier,
      );
}
