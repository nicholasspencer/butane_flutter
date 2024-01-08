part of '../porcelain.dart';

abstract base class PeerManager<T extends Peer> {
  PeerManager({
    this.clientIdentifier,
    @visibleForTesting api.ButanePlatformInterface? platform,
  }) : _platform = platform;

  final api.ButanePlatformInterface? _platform;

  final String? clientIdentifier;

  @protected
  api.ButanePlatformInterface get platform =>
      _platform ?? api.ButanePlatformInterface.instance;

  @protected
  StreamSubscription<api.ClientState>? stateSubscription;

  @protected
  late final StreamController<PeerManagerState> stateController =
      StreamController<PeerManagerState>.broadcast(onListen: onStateListen);

  Future<PeerManagerState> get state async {
    final state = await platform.clientState(clientIdentifier);

    return PeerManagerState.fromApi(state);
  }

  Stream<PeerManagerState> get stateStream {
    /// Subscribe to the api state stream if we aren't already.
    stateSubscription ??=
        platform.clientStateStream(clientIdentifier).listen(onState);

    return stateController.stream;
  }

  @protected
  void onState(api.ClientState state) {
    stateController.sink.add(PeerManagerState.fromApi(state));
  }

  @protected
  Future<void> onStateListen() async {
    final state = await platform.clientState(clientIdentifier);

    stateController.sink.add(PeerManagerState.fromApi(state));
  }

  @mustCallSuper
  void dispose() {
    stateSubscription?.cancel();
    stateController.close();
  }
}

enum PeerManagerState {
  unknown,
  resetting,
  unsupported,
  unauthorized,
  poweredOff,
  poweredOn;

  factory PeerManagerState.fromApi(api.ClientState state) {
    switch (state) {
      case api.ClientState.unknown:
        return PeerManagerState.unknown;
      case api.ClientState.resetting:
        return PeerManagerState.resetting;
      case api.ClientState.unsupported:
        return PeerManagerState.unsupported;
      case api.ClientState.unauthorized:
        return PeerManagerState.unauthorized;
      case api.ClientState.poweredOff:
        return PeerManagerState.poweredOff;
      case api.ClientState.poweredOn:
        return PeerManagerState.poweredOn;
    }
  }
}
