part of '../interface.dart';

abstract base class PeerManager<T extends Peer> {
  PeerManager({
    @visibleForTesting this.peers = const {},
    @visibleForTesting ButanePlatform? platform,
  }) : _platform = platform;

  @protected
  final ButanePlatform? _platform;

  @protected
  ButanePlatform get platform => _platform ?? ButanePlatform.instance;

  @protected
  final Map<Identifier, T> peers;
}
