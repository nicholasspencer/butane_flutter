part of '../porcelain.dart';

abstract base class Peer {
  const Peer({
    required this.manager,
    required this.identifier,
  });

  @protected
  final PeerManager manager;

  final Identifier identifier;

  @protected
  api.Session get session => api.Session(
        peripheralIdentifier: identifier.toString(),
        clientIdentifier: manager.clientIdentifier,
        adapterIdentifier: null,
      );
}
