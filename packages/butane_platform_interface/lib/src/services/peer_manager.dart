part of '../interface.dart';

abstract base class PeerManager<T extends Peer> {
  PeerManager({
    @visibleForTesting this.peers = const {},
    @visibleForTesting ButanePlatformInterface? platform,
  }) : _platform = platform;

  Stream<PeerManagerState> get managerStateStream {
    return platform.managerStateStream.map(PeerManagerState.fromApi);
  }

  @protected
  final ButanePlatformInterface? _platform;

  @protected
  ButanePlatformInterface get platform =>
      _platform ?? ButanePlatformInterface.instance;

  @protected
  final Map<Identifier, T> peers;
}

enum PeerManagerState {
  unknown,
  resetting,
  unsupported,
  unauthorized,
  poweredOff,
  poweredOn;

  factory PeerManagerState.fromApi(api.ManagerState state) {
    switch (state) {
      case api.ManagerState.unknown:
        return PeerManagerState.unknown;
      case api.ManagerState.resetting:
        return PeerManagerState.resetting;
      case api.ManagerState.unsupported:
        return PeerManagerState.unsupported;
      case api.ManagerState.unauthorized:
        return PeerManagerState.unauthorized;
      case api.ManagerState.poweredOff:
        return PeerManagerState.poweredOff;
      case api.ManagerState.poweredOn:
        return PeerManagerState.poweredOn;
    }
  }
}
