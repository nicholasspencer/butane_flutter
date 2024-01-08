part of '../porcelain.dart';

base class Central extends Peer {
  const Central({
    required PeerManager<Central> super.manager,
    required super.identifier,
  });

  @override
  PeerManager<Central> get manager => super.manager as PeerManager<Central>;
}
