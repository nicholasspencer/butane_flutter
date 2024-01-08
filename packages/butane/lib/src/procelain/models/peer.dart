part of '../porcelain.dart';

abstract base class Peer {
  const Peer({
    required this.manager,
    required this.identifier,
    @visibleForTesting api.ButanePlatformInterface? platform,
  }) : _platform = platform;

  final api.ButanePlatformInterface? _platform;

  @protected
  api.ButanePlatformInterface get platform => _platform ?? manager.platform;

  @protected
  final PeerManager manager;

  final Identifier identifier;

  @protected
  api.Session get session => api.Session(
        peripheralIdentifier: identifier.toString(),
        clientIdentifier: manager.clientIdentifier,
        adapterIdentifier: null,
      );

  @mustCallSuper
  void dispose() {}
}
