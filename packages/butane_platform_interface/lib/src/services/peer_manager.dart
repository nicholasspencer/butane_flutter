part of '../interface.dart';

abstract base class PeerManager<T extends Peer> {
  PeerManager({
    this.clientIdentifier,
    @visibleForTesting this.peers = const {},
    @visibleForTesting ButanePlatformInterface? platform,
  }) : _platform = platform;

  final ButanePlatformInterface? _platform;

  final String? clientIdentifier;

  @protected
  final Map<Identifier, T> peers;

  @protected
  ButanePlatformInterface get platform =>
      _platform ?? ButanePlatformInterface.instance;

  @protected
  StreamSubscription<api.ClientState>? clientStateSubscription;

  @protected
  late final StreamController<PeerManagerState> stateController =
      StreamController<PeerManagerState>.broadcast(onListen: onStateListen);

  Future<PeerManagerState> get state async {
    final state = await platform.clientState(clientIdentifier);

    return PeerManagerState.fromApi(state);
  }

  Stream<PeerManagerState> get stateStream {
    /// Subscribe to the api state stream if we aren't already.
    clientStateSubscription ??=
        platform.clientStateStream(clientIdentifier).listen(onState);

    return stateController.stream;
  }

  @protected
  void onState(api.ClientState state) {
    stateController.sink.add(PeerManagerState.fromApi(state));
  }

  @protected
  void onStateListen() async {
    final state = await platform.clientState(clientIdentifier);

    stateController.sink.add(PeerManagerState.fromApi(state));
  }

  @mustCallSuper
  void dispose() {}
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
