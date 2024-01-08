part of '../porcelain.dart';

enum ConnectionState {
  disconnected,
  connecting,
  connected,
  disconnecting,
  reconnecting;

  api.ConnectionState toApi() {
    switch (this) {
      case ConnectionState.disconnected:
        return api.ConnectionState.disconnected;
      case ConnectionState.connecting:
        return api.ConnectionState.connecting;
      case ConnectionState.connected:
        return api.ConnectionState.connected;
      case ConnectionState.disconnecting:
        return api.ConnectionState.disconnecting;
      case ConnectionState.reconnecting:
        return api.ConnectionState.reconnecting;
    }
  }
}

base class Peripheral extends Peer {
  Peripheral({
    required PeerManager<Peripheral> super.manager,
    required this.name,
    required super.identifier,
    this.initialRssi,
    this.initialState = ConnectionState.disconnected,
    @visibleForTesting api.ButanePlatformInterface? platform,
  }) : _platform = platform;

  final api.ButanePlatformInterface? _platform;

  @protected
  api.ButanePlatformInterface get platform => _platform ?? manager.platform;

  final String? name;

  final double? initialRssi;

  final ConnectionState initialState;

  @override
  PeerManager<Peripheral> get manager =>
      super.manager as PeerManager<Peripheral>;

  Future<void> connect() async {
    return manager.platform.connect(
      session: session,
    );
  }

  Future<void> cancelConnection() async {
    return manager.platform.cancelConnection(session: session);
  }

  @protected
  StreamSubscription<api.ConnectionState>? stateSubscription;

  @protected
  late final StreamController<ConnectionState> stateController =
      StreamController<ConnectionState>.broadcast(onListen: onStateListen);

  Future<ConnectionState> get state async {
    final state = await platform.connectionState(session: session);

    return state.toConnectionState();
  }

  Stream<ConnectionState> get stateStream {
    /// Subscribe to the api state stream if we aren't already.
    stateSubscription ??= platform
        .connectionStateStream(
          session: session,
        )
        .listen(onState);

    return stateController.stream;
  }

  @protected
  void onState(api.ConnectionState state) {
    stateController.sink.add(state.toConnectionState());
  }

  @protected
  Future<void> onStateListen() async {
    final state = await this.state;

    stateController.sink.add(state);
  }

  Future<void> discoverServices({
    List<UuidIdentifier> serviceUuids = const [],
  }) {
    return manager.platform.discoverServices(
      session: session,
      serviceUuids: serviceUuids.toStrings(),
    );
  }

  Future<Iterable<Service>> get services async {
    final services = await manager.platform.services(
      session: session,
    );

    return services.map(serviceFromData);
  }

  @protected
  api.Peripheral toData() {
    return api.Peripheral(
      session: session,
      name: name,
      rssi: initialRssi,
      state: initialState.toApi(),
    );
  }

  @protected
  Service serviceFromData(api.Service data) {
    return data.toService(peripheral: this);
  }
}

base class AdvertisementData {
  const AdvertisementData({
    this.localName,
    this.txPowerLevel,
    this.manufacturerData,
    this.serviceData,
    this.serviceUuids,
    this.isConnectable = false,
  });

  final String? localName;

  final int? txPowerLevel;

  final Uint8List? manufacturerData;

  final Map<String, Uint8List>? serviceData;

  final List<String>? serviceUuids;

  final bool isConnectable;

  @protected
  api.AdvertisementData toData() {
    return api.AdvertisementData(
      localName: localName,
      txPowerLevel: txPowerLevel,
      manufacturerData: manufacturerData,
      serviceData: serviceData,
      serviceUuids: serviceUuids,
      isConnectable: isConnectable,
    );
  }
}

base class ScanResult {
  const ScanResult({
    required this.peripheral,
    required this.advertisementData,
  });

  final Peripheral peripheral;

  final AdvertisementData advertisementData;
}

extension ApiPeripheralData on api.Peripheral {
  Peripheral toPeripheral({required PeerManager<Peripheral> manager}) {
    return Peripheral(
      identifier: Identifier.parse(session.peripheralIdentifier),
      name: name,
      initialRssi: rssi,
      manager: manager,
    );
  }
}

extension ApiConnectionState on api.ConnectionState {
  ConnectionState toConnectionState() {
    switch (this) {
      case api.ConnectionState.disconnected:
        return ConnectionState.disconnected;
      case api.ConnectionState.connecting:
        return ConnectionState.connecting;
      case api.ConnectionState.connected:
        return ConnectionState.connected;
      case api.ConnectionState.disconnecting:
        return ConnectionState.disconnecting;
      case api.ConnectionState.reconnecting:
        return ConnectionState.reconnecting;
    }
  }
}

extension ApiAdvertisementData on api.AdvertisementData {
  AdvertisementData toAdvertisementData() {
    return AdvertisementData(
      manufacturerData: manufacturerData,
      serviceData: serviceData as Map<String, Uint8List>?,
      serviceUuids: serviceUuids?.nonNulls.toList(),
      txPowerLevel: txPowerLevel,
      localName: localName,
    );
  }
}

extension ApiScanData on api.ScanResult {
  ScanResult toScanResult({required PeerManager<Peripheral> manager}) {
    return ScanResult(
      peripheral: peripheral.toPeripheral(manager: manager),
      advertisementData: advertisementData.toAdvertisementData(),
    );
  }
}
