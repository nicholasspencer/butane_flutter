part of '../porcelain.dart';

abstract base class PeerManager<T extends Peer> {
  PeerManager({
    this.clientIdentifier,
    this.restorationIdentifier,
    @visibleForTesting api.ButanePlatformInterface? platform,
  }) : _platform = platform;

  final api.ButanePlatformInterface? _platform;

  final String? clientIdentifier;

  final String? restorationIdentifier;

  @protected
  api.ButanePlatformInterface get platform =>
      _platform ?? api.ButanePlatformInterface.instance;

  @protected
  PlatformStreamController<PeerManagerState, api.ClientState>? stateController;

  @protected
  api.Session get session => api.Session(
        clientIdentifier: clientIdentifier,
        restorationIdentifier: restorationIdentifier,
      );

  Future<PeerManagerState> get state async {
    final state = await platform.clientState(session);

    return PeerManagerState.fromApi(state);
  }

  /// Requests that the platform enable its Bluetooth adapter.
  ///
  /// Android opens the system confirmation dialog. Windows and BlueZ directly
  /// request radio power-on; Windows consumers must declare the `radios`
  /// capability. Darwin throws [ButaneException] with
  /// [ButaneErrorCode.unsupported]. Completion means that the request was
  /// accepted or launched, not that the adapter is on. Observe [stateStream]
  /// for [PeerManagerState.poweredOn].
  Future<void> requestEnable() => platform.requestEnable(session: session);

  Stream<PeerManagerState> get stateStream {
    // Subscribe to the api state stream if we aren't already.
    stateController ??= PlatformStreamController(
      debugLabel: 'PeerManager($clientIdentifier).stateStream',
      platform: platform,
      map: (value) => PeerManagerState.fromApi(value),
      createStream: (platform) {
        return platform.clientStateStream(session);
      },
      sinkValue: (platform) async {
        final state = await platform.clientState(session);
        return state;
      },
    );

    return stateController!.stream;
  }

  @mustCallSuper
  void dispose() {
    stateController?.dispose();
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
