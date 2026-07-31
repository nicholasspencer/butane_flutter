import 'dart:async';
import 'dart:typed_data';

import 'package:meta/meta.dart';

import 'package:butane_dart/interface.dart';
import 'api.g.dart' as api;

/// The client session, when supplied, and its latest native client state.
typedef ClientStateResult = ({
  Session? session,
  api.ClientState state,
});

/// A peripheral and its latest native connection state.
typedef ConnectionStateResult = ({
  api.Peripheral peripheral,
  api.ConnectionState state,
});

/// A characteristic value delivered for a peripheral.
typedef CharacteristicValueResult = ({
  api.Peripheral peripheral,
  api.Characteristic characteristic,
  Uint8List value,
});

/// A peripheral and its latest received signal strength indicator.
typedef RssiResult = ({
  api.Peripheral peripheral,
  int rssi,
});

/// The UUID and optional native error reported after adding a service.
typedef ServiceAddedResult = ({
  String serviceUuid,
  String? error,
});

/// Identifies a central subscription to a local characteristic.
typedef CentralSubscriptionResult = ({
  String? clientIdentifier,
  String centralIdentifier,
  String serviceUuid,
  String characteristicUuid,
});

/// A default implementation of [ButanePlatformInterface] which uses generated
/// method channels to call platform-specific code.
base class ButanePlatform extends ButanePlatformInterface {
  /// Registers the method-channel implementation as the active backend.
  static void registerWith() {
    ButanePlatformInterface.instance = ButanePlatform();
  }

  /// Host API used to invoke native BLE operations.
  @protected
  late final api.ButaneHostApi hostApi = api.ButaneHostApi();

  /// Flutter API that receives native BLE callbacks.
  @protected
  late final ButaneFlutterApi flutterApi = ButaneFlutterApi();

  @override
  Future<ClientState> clientState([
    Session? session,
  ]) async {
    final state = await hostApi.state(session: session?.toSession());
    return state.toClientState();
  }

  @override
  Stream<ClientState> clientStateStream([
    Session? session,
  ]) =>
      flutterApi.clientStateStream
          .where(
            (e) => e.session?.clientIdentifier == session?.clientIdentifier,
          )
          .map((e) => e.state.toClientState());

  @override
  Future<void> scan({
    Iterable<String>? forServices,
    Session? session,
  }) async {
    hostApi.scan(
      session: session?.toSession(),
      forServices: forServices?.toList(),
    );
  }

  @override
  Stream<ScanResult> scanStream([
    Session? session,
  ]) {
    return flutterApi.scanStream.where((e) {
      return e.peripheral.session.clientIdentifier == session?.clientIdentifier;
    }).map(ScanResultConverter.fromScanResult);
  }

  @override
  Future<void> cancelScan({
    Session? session,
  }) {
    return hostApi.cancelScan(
      session: session?.toSession(),
    );
  }

  @override
  Future<Iterable<Peripheral>> peripherals({
    Iterable<String> peripheralIdentifiers = const [],
    Session? session,
  }) async {
    final peripherals = await hostApi.peripherals(
      peripheralIdentifiers: peripheralIdentifiers.toList(),
      session: session?.toSession(),
    );

    return peripherals.nonNulls.map((e) => e.toPeripheral());
  }

  @override
  Future<Iterable<Peripheral>> connectedPeripherals({
    Iterable<String> serviceUuids = const [],
    Session? session,
  }) async {
    final peripherals = await hostApi.connectedPeripherals(
      serviceUuids: serviceUuids.toList(),
      session: session?.toSession(),
    );

    return peripherals.nonNulls.map((e) => e.toPeripheral());
  }

  @override
  Future<void> connect({
    required PeripheralSession session,
  }) async {
    return hostApi.connect(
      session: session.toSession(),
    );
  }

  @override
  Future<void> cancelConnection({
    required PeripheralSession session,
  }) async {
    return hostApi.cancelConnection(
      session: session.toSession(),
    );
  }

  @override
  Future<ConnectionState> connectionState({
    required PeripheralSession session,
  }) async {
    final state = await hostApi.connectionState(
      session: session.toSession(),
    );

    return state.toConnectionState();
  }

  @override
  Stream<ConnectionState> connectionStateStream({
    required PeripheralSession session,
  }) {
    return flutterApi.connectionStateStream.where(
      (event) {
        return event.peripheral.session.clientIdentifier ==
                session.clientIdentifier &&
            event.peripheral.session.peripheralIdentifier ==
                session.peripheralIdentifier;
      },
    ).map((event) => event.state.toConnectionState());
  }

  @override
  Future<void> discoverServices({
    required PeripheralSession session,
    Iterable<String>? serviceUuids,
  }) async {
    await hostApi.discoverServices(
      session: session.toSession(),
      serviceUuids: serviceUuids?.toList(),
    );
  }

  @override
  Future<Iterable<Service>> services({
    required PeripheralSession session,
  }) async {
    final services = await hostApi.services(
      session: session.toSession(),
    );

    return services.nonNulls.map(ServiceConverter.fromService);
  }

  @override
  Future<void> discoverCharacteristics({
    required PeripheralSession session,
    required String serviceUuid,
    Iterable<String>? characteristicUuids,
  }) async {
    await hostApi.discoverCharacteristics(
      session: session.toSession(),
      serviceUuid: serviceUuid,
      characteristicUuids: characteristicUuids?.toList(),
    );
  }

  @override
  Future<Iterable<Characteristic>> characteristics({
    required PeripheralSession session,
    required String serviceUuid,
  }) async {
    final characteristics = await hostApi.characteristics(
      session: session.toSession(),
      serviceUuid: serviceUuid,
    );

    return characteristics.nonNulls.map(
      CharacteristicConverter.fromCharacteristic,
    );
  }

  @override
  Future<Uint8List> readCharacteristic({
    required PeripheralSession session,
    required String serviceUuid,
    required String characteristicUuid,
  }) async {
    return hostApi.readCharacteristic(
      session: session.toSession(),
      serviceUuid: serviceUuid,
      characteristicUuid: characteristicUuid,
    );
  }

  @override
  Future<void> writeCharacteristic({
    required PeripheralSession session,
    required String serviceUuid,
    required String characteristicUuid,
    required Uint8List value,
    bool withoutResponse = false,
  }) {
    return hostApi.writeCharacteristic(
      session: session.toSession(),
      serviceUuid: serviceUuid,
      characteristicUuid: characteristicUuid,
      value: value,
      withoutResponse: withoutResponse,
    );
  }

  /// Updates the observability of notifications and indications of
  /// the characteristic.
  @override
  Future<void> observeCharacteristic({
    required PeripheralSession session,
    required String serviceUuid,
    required String characteristicUuid,
    bool observe = true,
  }) {
    return hostApi.observeCharacteristic(
      observe: observe,
      session: session.toSession(),
      serviceUuid: serviceUuid,
      characteristicUuid: characteristicUuid,
    );
  }

  @override
  Stream<Uint8List> characteristicValueStream({
    required PeripheralSession session,
    required String serviceUuid,
    required String characteristicUuid,
  }) {
    return flutterApi.characteristicValueStream
        .forCharacteristic(
          characteristicUuid: characteristicUuid,
          peripheralIdentifier: session.peripheralIdentifier,
        )
        .map((result) => result.value);
  }

  /// Requests a read of the RSSI for the peripheral.
  @override
  Future<int> readRssi({
    required PeripheralSession session,
  }) {
    return hostApi.readRssi(
      session: session.toSession(),
    );
  }

  // Peripheral Manager

  @override
  Future<ClientState> peripheralManagerState([
    PeripheralManagerSession? session,
  ]) async {
    final state = await hostApi.peripheralManagerState(
      session: session?.toPeripheralManagerSession() ??
          api.PeripheralManagerSession(),
    );
    return state.toClientState();
  }

  @override
  Stream<ClientState> peripheralManagerStateStream([
    PeripheralManagerSession? session,
  ]) =>
      flutterApi.peripheralManagerStateStream
          .where(
            (e) => e.session?.clientIdentifier == session?.clientIdentifier,
          )
          .map((e) => e.state.toClientState());

  @override
  Future<void> startAdvertising({
    PeripheralManagerSession? session,
    String? localName,
    Iterable<String>? serviceUuids,
  }) {
    return hostApi.startAdvertising(
      session: session?.toPeripheralManagerSession() ??
          api.PeripheralManagerSession(),
      localName: localName,
      serviceUuids: serviceUuids?.toList(),
    );
  }

  @override
  Future<void> stopAdvertising({
    PeripheralManagerSession? session,
  }) {
    return hostApi.stopAdvertising(
      session: session?.toPeripheralManagerSession() ??
          api.PeripheralManagerSession(),
    );
  }

  @override
  Future<void> addService({
    PeripheralManagerSession? session,
    required MutableService service,
  }) {
    return hostApi.addService(
      session: session?.toPeripheralManagerSession() ??
          api.PeripheralManagerSession(),
      service: service.toMutableService(),
    );
  }

  @override
  Stream<({String serviceUuid, String? error})> serviceAddedStream([
    PeripheralManagerSession? session,
  ]) =>
      flutterApi.serviceAddedStream.map(
        (e) => (serviceUuid: e.serviceUuid, error: e.error),
      );

  @override
  Future<void> removeService({
    PeripheralManagerSession? session,
    required String serviceUuid,
  }) {
    return hostApi.removeService(
      session: session?.toPeripheralManagerSession() ??
          api.PeripheralManagerSession(),
      serviceUuid: serviceUuid,
    );
  }

  @override
  Future<void> removeAllServices({
    PeripheralManagerSession? session,
  }) {
    return hostApi.removeAllServices(
      session: session?.toPeripheralManagerSession() ??
          api.PeripheralManagerSession(),
    );
  }

  @override
  Future<void> respondToRequest({
    PeripheralManagerSession? session,
    required int requestId,
    required AttResult result,
    Uint8List? value,
  }) {
    return hostApi.respondToRequest(
      session: session?.toPeripheralManagerSession() ??
          api.PeripheralManagerSession(),
      requestId: requestId,
      result: result.toAttResult(),
      value: value,
    );
  }

  @override
  Future<bool> updateValue({
    PeripheralManagerSession? session,
    required String serviceUuid,
    required String characteristicUuid,
    required Uint8List value,
  }) {
    return hostApi.updateValue(
      session: session?.toPeripheralManagerSession() ??
          api.PeripheralManagerSession(),
      serviceUuid: serviceUuid,
      characteristicUuid: characteristicUuid,
      value: value,
    );
  }

  @override
  Stream<AttRequest> readRequestStream([
    PeripheralManagerSession? session,
  ]) =>
      flutterApi.readRequestStream.map(
        (e) => e.toAttRequest(),
      );

  @override
  Stream<List<AttRequest>> writeRequestsStream([
    PeripheralManagerSession? session,
  ]) =>
      flutterApi.writeRequestsStream.map(
        (requests) => requests.map((e) => e.toAttRequest()).toList(),
      );
}

/// Receives generated native callbacks and exposes typed event streams.
base class ButaneFlutterApi extends api.ButaneFlutterApi {
  /// Creates and registers a receiver for generated native callbacks.
  ButaneFlutterApi() {
    api.ButaneFlutterApi.setUp(this);
  }

  // Client State

  /// Emits native client-state changes.
  Stream<ClientStateResult> get clientStateStream =>
      clientStateController.stream;

  @protected
  final clientStateController = StreamController<ClientStateResult>.broadcast();

  @protected
  @override
  void onClientState(String? clientIdentifier, api.ClientState state) {
    clientStateController.sink.add(
      (
        session: Session(
          clientIdentifier: clientIdentifier,
        ),
        state: state,
      ),
    );
  }

  // Scan Result

  /// Emits native scan results.
  Stream<api.ScanResult> get scanStream => scanController.stream;

  @protected
  final scanController = StreamController<api.ScanResult>.broadcast();

  @protected
  @override
  void onScanResult(api.ScanResult scanResult) {
    scanController.sink.add(scanResult);
  }

  // Connection State

  @protected
  final connectionStateController =
      StreamController<ConnectionStateResult>.broadcast();

  /// Emits native peripheral connection-state changes.
  Stream<ConnectionStateResult> get connectionStateStream =>
      connectionStateController.stream;

  @protected
  @override
  void onConnectionState(
    api.Peripheral peripheral,
    api.ConnectionState state,
  ) {
    connectionStateController.sink.add(
      (
        peripheral: peripheral,
        state: state,
      ),
    );
  }

  // Characteristic Value

  /// Emits native characteristic-value updates.
  Stream<CharacteristicValueResult> get characteristicValueStream =>
      characteristicValueController.stream;

  @protected
  final characteristicValueController =
      StreamController<CharacteristicValueResult>.broadcast();

  @protected
  @override
  void onCharacteristicValue(
    api.Peripheral peripheral,
    api.Characteristic characteristic,
    Uint8List value,
  ) {
    characteristicValueController.sink.add(
      (
        peripheral: peripheral,
        characteristic: characteristic,
        value: value,
      ),
    );
  }

  // Descriptor Value

  @override
  void onDescriptorValue(
    api.Peripheral peripheral,
    api.Descriptor descriptor,
    Uint8List value,
  ) {
    // TODO: implement onDescriptorValue
  }

  // Peripheral Manager State

  /// Emits native peripheral-manager state changes.
  Stream<ClientStateResult> get peripheralManagerStateStream =>
      peripheralManagerStateController.stream;

  @protected
  final peripheralManagerStateController =
      StreamController<ClientStateResult>.broadcast();

  @protected
  @override
  void onPeripheralManagerState(
    String? clientIdentifier,
    api.ClientState state,
  ) {
    peripheralManagerStateController.sink.add(
      (
        session: Session(
          clientIdentifier: clientIdentifier,
        ),
        state: state,
      ),
    );
  }

  // Service Added

  /// Emits results of adding local services.
  Stream<ServiceAddedResult> get serviceAddedStream =>
      serviceAddedController.stream;

  @protected
  final serviceAddedController =
      StreamController<ServiceAddedResult>.broadcast();

  @protected
  @override
  void onServiceAdded(String serviceUuid, String? error) {
    serviceAddedController.sink.add(
      (
        serviceUuid: serviceUuid,
        error: error,
      ),
    );
  }

  // Read Request

  /// Emits native ATT read requests.
  Stream<api.AttRequest> get readRequestStream => readRequestController.stream;

  @protected
  final readRequestController = StreamController<api.AttRequest>.broadcast();

  @protected
  @override
  void onReadRequest(api.AttRequest request) {
    readRequestController.sink.add(request);
  }

  // Write Requests

  /// Emits batches of native ATT write requests.
  Stream<List<api.AttRequest>> get writeRequestsStream =>
      writeRequestsController.stream;

  @protected
  final writeRequestsController =
      StreamController<List<api.AttRequest>>.broadcast();

  @protected
  @override
  void onWriteRequests(List<api.AttRequest> requests) {
    writeRequestsController.sink.add(requests);
  }

  // Central Subscribed

  /// Emits central-subscription events.
  Stream<CentralSubscriptionResult> get centralSubscribedStream =>
      centralSubscribedController.stream;

  @protected
  final centralSubscribedController =
      StreamController<CentralSubscriptionResult>.broadcast();

  @protected
  @override
  void onCentralSubscribed(
    String? clientIdentifier,
    String centralIdentifier,
    String serviceUuid,
    String characteristicUuid,
  ) {
    centralSubscribedController.sink.add(
      (
        clientIdentifier: clientIdentifier,
        centralIdentifier: centralIdentifier,
        serviceUuid: serviceUuid,
        characteristicUuid: characteristicUuid,
      ),
    );
  }

  // Central Unsubscribed

  /// Emits central-unsubscription events.
  Stream<CentralSubscriptionResult> get centralUnsubscribedStream =>
      centralUnsubscribedController.stream;

  @protected
  final centralUnsubscribedController =
      StreamController<CentralSubscriptionResult>.broadcast();

  @protected
  @override
  void onCentralUnsubscribed(
    String? clientIdentifier,
    String centralIdentifier,
    String serviceUuid,
    String characteristicUuid,
  ) {
    centralUnsubscribedController.sink.add(
      (
        clientIdentifier: clientIdentifier,
        centralIdentifier: centralIdentifier,
        serviceUuid: serviceUuid,
        characteristicUuid: characteristicUuid,
      ),
    );
  }

  // Ready to Update Subscribers

  /// Emits client identifiers ready for another subscriber update.
  Stream<String?> get readyToUpdateSubscribersStream =>
      readyToUpdateSubscribersController.stream;

  @protected
  final readyToUpdateSubscribersController =
      StreamController<String?>.broadcast();

  @protected
  @override
  void onReadyToUpdateSubscribers(String? clientIdentifier) {
    readyToUpdateSubscribersController.sink.add(clientIdentifier);
  }
}

/// Filters characteristic-value callback streams.
extension CharacteristicValueResultStreamFilter
    on Stream<CharacteristicValueResult> {
  /// Returns events matching [peripheralIdentifier] and [characteristicUuid].
  Stream<CharacteristicValueResult> forCharacteristic({
    required String? peripheralIdentifier,
    required String characteristicUuid,
  }) {
    return where(
      (result) =>
          result.peripheral.session.peripheralIdentifier ==
              peripheralIdentifier &&
          result.characteristic.uuid == characteristicUuid,
    );
  }
}

/// Records

/// Converts between domain session values and generated channel values.
extension SessionConverter on Session {
  /// Creates a domain session from [session].
  static Session fromClientSession(api.ClientSession session) {
    return Session(
      peripheralIdentifier: session.peripheralIdentifier,
      clientIdentifier: session.clientIdentifier,
      adapterIdentifier: session.adapterIdentifier,
      restorationIdentifier: session.restorationIdentifier,
    );
  }

  /// Returns this session in the generated channel representation.
  api.ClientSession toSession() {
    return api.ClientSession(
      peripheralIdentifier: peripheralIdentifier,
      clientIdentifier: clientIdentifier,
      adapterIdentifier: adapterIdentifier,
      restorationIdentifier: restorationIdentifier,
    );
  }
}

/// Converts between domain peripheral session values and generated channel values.
extension PeripheralSessionConverter on PeripheralSession {
  /// Creates a domain peripheral session from [session].
  static PeripheralSession fromSession(api.PeripheralSession session) {
    return PeripheralSession(
      peripheralIdentifier: session.peripheralIdentifier,
      clientIdentifier: session.clientIdentifier,
      adapterIdentifier: session.adapterIdentifier,
      restorationIdentifier: session.restorationIdentifier,
    );
  }

  /// Returns this peripheral session in the generated channel representation.
  api.PeripheralSession toSession() {
    return api.PeripheralSession(
      peripheralIdentifier: peripheralIdentifier,
      clientIdentifier: clientIdentifier,
      adapterIdentifier: adapterIdentifier,
      restorationIdentifier: restorationIdentifier,
    );
  }
}

/// Converts between domain peripheral session values and generated channel values.
extension PeripheralChannelSessionConverter on api.PeripheralSession {
  /// Creates a channel peripheral session from [session].
  static api.PeripheralSession fromSession(PeripheralSession session) {
    return api.PeripheralSession(
      peripheralIdentifier: session.peripheralIdentifier,
      clientIdentifier: session.clientIdentifier,
      adapterIdentifier: session.adapterIdentifier,
      restorationIdentifier: session.restorationIdentifier,
    );
  }

  /// Returns this channel peripheral session in the domain representation.
  PeripheralSession toSession() {
    return PeripheralSession(
      peripheralIdentifier: peripheralIdentifier,
      clientIdentifier: clientIdentifier,
      adapterIdentifier: adapterIdentifier,
      restorationIdentifier: restorationIdentifier,
    );
  }
}

/// Converts between domain client state values and generated channel values.
extension ClientStateConverter on ClientState {
  /// Creates a domain client state from [state].
  static ClientState fromClientState(api.ClientState state) {
    switch (state) {
      case api.ClientState.unknown:
        return ClientState.unknown;
      case api.ClientState.resetting:
        return ClientState.resetting;
      case api.ClientState.unsupported:
        return ClientState.unsupported;
      case api.ClientState.unauthorized:
        return ClientState.unauthorized;
      case api.ClientState.poweredOff:
        return ClientState.poweredOff;
      case api.ClientState.poweredOn:
        return ClientState.poweredOn;
    }
  }

  /// Returns this client state in the generated channel representation.
  api.ClientState toClientState() {
    switch (this) {
      case ClientState.unknown:
        return api.ClientState.unknown;
      case ClientState.resetting:
        return api.ClientState.resetting;
      case ClientState.unsupported:
        return api.ClientState.unsupported;
      case ClientState.unauthorized:
        return api.ClientState.unauthorized;
      case ClientState.poweredOff:
        return api.ClientState.poweredOff;
      case ClientState.poweredOn:
        return api.ClientState.poweredOn;
    }
  }
}

/// Converts between domain client state values and generated channel values.
extension ClientStateChannelConverter on api.ClientState {
  /// Creates a channel client state from [state].
  static api.ClientState fromClientState(ClientState state) {
    switch (state) {
      case ClientState.unknown:
        return api.ClientState.unknown;
      case ClientState.resetting:
        return api.ClientState.resetting;
      case ClientState.unsupported:
        return api.ClientState.unsupported;
      case ClientState.unauthorized:
        return api.ClientState.unauthorized;
      case ClientState.poweredOff:
        return api.ClientState.poweredOff;
      case ClientState.poweredOn:
        return api.ClientState.poweredOn;
    }
  }

  /// Returns this channel client state in the domain representation.
  ClientState toClientState() {
    switch (this) {
      case api.ClientState.unknown:
        return ClientState.unknown;
      case api.ClientState.resetting:
        return ClientState.resetting;
      case api.ClientState.unsupported:
        return ClientState.unsupported;
      case api.ClientState.unauthorized:
        return ClientState.unauthorized;
      case api.ClientState.poweredOff:
        return ClientState.poweredOff;
      case api.ClientState.poweredOn:
        return ClientState.poweredOn;
    }
  }
}

/// Converts between domain connection state values and generated channel values.
extension ConnectionStateConverter on ConnectionState {
  /// Creates a domain connection state from [state].
  static ConnectionState fromConnectionState(api.ConnectionState state) {
    switch (state) {
      case api.ConnectionState.disconnected:
        return ConnectionState.disconnected;
      case api.ConnectionState.connecting:
        return ConnectionState.connecting;
      case api.ConnectionState.reconnecting:
        return ConnectionState.reconnecting;
      case api.ConnectionState.connected:
        return ConnectionState.connected;
      case api.ConnectionState.disconnecting:
        return ConnectionState.disconnecting;
    }
  }

  /// Returns this connection state in the generated channel representation.
  api.ConnectionState toConnectionState() {
    switch (this) {
      case ConnectionState.disconnected:
        return api.ConnectionState.disconnected;
      case ConnectionState.connecting:
        return api.ConnectionState.connecting;
      case ConnectionState.reconnecting:
        return api.ConnectionState.reconnecting;
      case ConnectionState.connected:
        return api.ConnectionState.connected;
      case ConnectionState.disconnecting:
        return api.ConnectionState.disconnecting;
    }
  }
}

/// Converts between domain connection state values and generated channel values.
extension ConnectionStateChannelConverter on api.ConnectionState {
  /// Creates a channel connection state from [state].
  static api.ConnectionState fromConnectionState(ConnectionState state) {
    switch (state) {
      case ConnectionState.disconnected:
        return api.ConnectionState.disconnected;
      case ConnectionState.connecting:
        return api.ConnectionState.connecting;
      case ConnectionState.reconnecting:
        return api.ConnectionState.reconnecting;
      case ConnectionState.connected:
        return api.ConnectionState.connected;
      case ConnectionState.disconnecting:
        return api.ConnectionState.disconnecting;
    }
  }

  /// Returns this channel connection state in the domain representation.
  ConnectionState toConnectionState() {
    switch (this) {
      case api.ConnectionState.disconnected:
        return ConnectionState.disconnected;
      case api.ConnectionState.connecting:
        return ConnectionState.connecting;
      case api.ConnectionState.reconnecting:
        return ConnectionState.reconnecting;
      case api.ConnectionState.connected:
        return ConnectionState.connected;
      case api.ConnectionState.disconnecting:
        return ConnectionState.disconnecting;
    }
  }
}

/// Converts between domain peripheral values and generated channel values.
extension PeripheralConverter on Peripheral {
  /// Creates a domain peripheral from [peripheral].
  static Peripheral fromPeripheral(api.Peripheral peripheral) {
    return Peripheral(
      session: PeripheralSessionConverter.fromSession(peripheral.session),
      name: peripheral.name,
      rssi: peripheral.rssi,
      state: ConnectionStateConverter.fromConnectionState(peripheral.state),
    );
  }

  /// Returns this peripheral in the generated channel representation.
  api.Peripheral toPeripheral() {
    return api.Peripheral(
      session: session.toSession(),
      name: name,
      rssi: rssi,
      state: state.toConnectionState(),
    );
  }
}

/// Converts between domain peripheral values and generated channel values.
extension PeripheralChannelConverter on api.Peripheral {
  /// Creates a channel peripheral from [peripheral].
  static api.Peripheral fromPeripheral(Peripheral peripheral) {
    return api.Peripheral(
      session:
          PeripheralChannelSessionConverter.fromSession(peripheral.session),
      name: peripheral.name,
      rssi: peripheral.rssi,
      state: ConnectionStateChannelConverter.fromConnectionState(
        peripheral.state,
      ),
    );
  }

  /// Returns this channel peripheral in the domain representation.
  Peripheral toPeripheral() {
    return Peripheral(
      session: session.toSession(),
      name: name,
      rssi: rssi,
      state: state.toConnectionState(),
    );
  }
}

/// Converts between domain advertisement data values and generated channel values.
extension AdvertisementDataConverter on AdvertisementData {
  /// Creates a domain advertisement data from [advertisementData].
  static AdvertisementData fromAdvertisementData(
    api.AdvertisementData advertisementData,
  ) {
    return AdvertisementData(
      localName: advertisementData.localName,
      manufacturerData: advertisementData.manufacturerData,
      serviceUuids: advertisementData.serviceUuids?.nonNulls.toList(),
      serviceData: advertisementData.serviceData?.nonNulls.cast(),
      txPowerLevel: advertisementData.txPowerLevel,
      isConnectable: advertisementData.isConnectable,
    );
  }

  /// Returns this advertisement data in the generated channel representation.
  api.AdvertisementData toAdvertisementData() {
    return api.AdvertisementData(
      localName: localName,
      manufacturerData: manufacturerData,
      serviceUuids: serviceUuids?.nonNulls.toList(),
      serviceData: serviceData,
      txPowerLevel: txPowerLevel,
      isConnectable: isConnectable,
    );
  }
}

/// Converts between domain advertisement data values and generated channel values.
extension AdvertisementDataChannelConverter on api.AdvertisementData {
  /// Creates a channel advertisement data from [advertisementData].
  static api.AdvertisementData fromAdvertisementData(
    AdvertisementData advertisementData,
  ) {
    return api.AdvertisementData(
      localName: advertisementData.localName,
      manufacturerData: advertisementData.manufacturerData,
      serviceUuids: advertisementData.serviceUuids,
      serviceData: advertisementData.serviceData,
      txPowerLevel: advertisementData.txPowerLevel,
      isConnectable: advertisementData.isConnectable,
    );
  }

  /// Returns this channel advertisement data in the domain representation.
  AdvertisementData toAdvertisementData() {
    return AdvertisementData(
      localName: localName,
      manufacturerData: manufacturerData,
      serviceUuids: serviceUuids?.nonNulls.toList(),
      serviceData: serviceData?.nonNulls.cast(),
      txPowerLevel: txPowerLevel,
      isConnectable: isConnectable,
    );
  }
}

/// Converts between domain scan result values and generated channel values.
extension ScanResultConverter on ScanResult {
  /// Creates a domain scan result from [scanResult].
  static ScanResult fromScanResult(api.ScanResult scanResult) {
    return ScanResult(
      peripheral: PeripheralConverter.fromPeripheral(scanResult.peripheral),
      advertisementData: AdvertisementDataConverter.fromAdvertisementData(
        scanResult.advertisementData,
      ),
    );
  }

  /// Returns this scan result in the generated channel representation.
  api.ScanResult toScanResult() {
    return api.ScanResult(
      peripheral: peripheral.toPeripheral(),
      advertisementData: advertisementData.toAdvertisementData(),
    );
  }
}

/// Converts between domain scan result values and generated channel values.
extension ScanResultChannelConverter on api.ScanResult {
  /// Creates a channel scan result from [scanResult].
  static api.ScanResult fromScanResult(ScanResult scanResult) {
    return api.ScanResult(
      peripheral:
          PeripheralChannelConverter.fromPeripheral(scanResult.peripheral),
      advertisementData:
          AdvertisementDataChannelConverter.fromAdvertisementData(
        scanResult.advertisementData,
      ),
    );
  }

  /// Returns this channel scan result in the domain representation.
  ScanResult toScanResult() {
    return ScanResult(
      peripheral: peripheral.toPeripheral(),
      advertisementData: advertisementData.toAdvertisementData(),
    );
  }
}

/// Converts between domain service values and generated channel values.
extension ServiceConverter on Service {
  /// Creates a domain service from [service].
  static Service fromService(api.Service service) {
    return Service(
      uuid: service.uuid,
      isPrimary: service.isPrimary,
    );
  }

  /// Returns this service in the generated channel representation.
  api.Service toService() {
    return api.Service(
      uuid: uuid,
      isPrimary: isPrimary,
    );
  }
}

/// Converts between domain service values and generated channel values.
extension ServiceChannelConverter on api.Service {
  /// Creates a channel service from [service].
  static api.Service fromService(Service service) {
    return api.Service(
      uuid: service.uuid,
      isPrimary: service.isPrimary,
    );
  }

  /// Returns this channel service in the domain representation.
  Service toService() {
    return Service(
      uuid: uuid,
      isPrimary: isPrimary,
    );
  }
}

/// Converts between domain characteristic values and generated channel values.
extension CharacteristicConverter on Characteristic {
  /// Creates a domain characteristic from [characteristic].
  static Characteristic fromCharacteristic(api.Characteristic characteristic) {
    return Characteristic(
      uuid: characteristic.uuid,
      value: characteristic.value,
      descriptors: characteristic.descriptors?.nonNulls
          .map(DescriptorConverter.fromDescriptor)
          .toList(),
      properties: characteristic.properties != null
          ? CharacteristicPropertyConverter.fromCharacteristicProperty(
              characteristic.properties!,
            )
          : null,
    );
  }

  /// Returns this characteristic in the generated channel representation.
  api.Characteristic toCharacteristic() {
    return api.Characteristic(
      uuid: uuid,
      value: value,
      descriptors: descriptors?.nonNulls.map((e) => e.toDescriptor()).toList(),
      properties: properties?.toCharacteristicProperty(),
    );
  }
}

/// Converts between domain characteristic values and generated channel values.
extension CharacteristicChannelConverter on api.Characteristic {
  /// Creates a channel characteristic from [characteristic].
  static api.Characteristic fromCharacteristic(Characteristic characteristic) {
    return api.Characteristic(
      uuid: characteristic.uuid,
      value: characteristic.value,
      descriptors: characteristic.descriptors
          ?.map(DescriptorChannelConverter.fromDescriptor)
          .toList(),
      properties: characteristic.properties != null
          ? CharacteristicPropertyChannelConverter.fromCharacteristicProperty(
              characteristic.properties!,
            )
          : null,
    );
  }

  /// Returns this channel characteristic in the domain representation.
  Characteristic toCharacteristic() {
    return Characteristic(
      uuid: uuid,
      value: value,
      descriptors: descriptors?.nonNulls.map((e) => e.toDescriptor()).toList(),
      properties: properties?.toCharacteristicProperty(),
    );
  }
}

/// Converts between domain descriptor values and generated channel values.
extension DescriptorConverter on Descriptor {
  /// Creates a domain descriptor from [descriptor].
  static Descriptor fromDescriptor(api.Descriptor descriptor) {
    return Descriptor(
      uuid: descriptor.uuid,
      value: descriptor.value,
    );
  }

  /// Returns this descriptor in the generated channel representation.
  api.Descriptor toDescriptor() {
    return api.Descriptor(
      uuid: uuid,
      value: value,
    );
  }
}

/// Converts between domain descriptor values and generated channel values.
extension DescriptorChannelConverter on api.Descriptor {
  /// Creates a channel descriptor from [descriptor].
  static api.Descriptor fromDescriptor(Descriptor descriptor) {
    return api.Descriptor(
      uuid: descriptor.uuid,
      value: descriptor.value,
    );
  }

  /// Returns this channel descriptor in the domain representation.
  Descriptor toDescriptor() {
    return Descriptor(
      uuid: uuid,
      value: value,
    );
  }
}

/// Converts between domain characteristic property values and generated channel values.
extension CharacteristicPropertyConverter on CharacteristicProperty {
  /// Creates a domain characteristic property from [property].
  static CharacteristicProperty fromCharacteristicProperty(
    api.CharacteristicProperty property,
  ) {
    return CharacteristicProperty(
      broadcast: property.broadcast,
      read: property.read,
      writeWithoutResponse: property.writeWithoutResponse,
      write: property.write,
      notify: property.notify,
      indicate: property.indicate,
      authenticatedSignedWrites: property.authenticatedSignedWrites,
      extendedProperties: property.extendedProperties,
      notifyEncryptionRequired: property.notifyEncryptionRequired,
      indicateEncryptionRequired: property.indicateEncryptionRequired,
    );
  }

  /// Returns this characteristic property in the generated channel representation.
  api.CharacteristicProperty toCharacteristicProperty() {
    return api.CharacteristicProperty(
      broadcast: broadcast,
      read: read,
      writeWithoutResponse: writeWithoutResponse,
      write: write,
      notify: notify,
      indicate: indicate,
      authenticatedSignedWrites: authenticatedSignedWrites,
      extendedProperties: extendedProperties,
      notifyEncryptionRequired: notifyEncryptionRequired,
      indicateEncryptionRequired: indicateEncryptionRequired,
    );
  }
}

/// Converts between domain characteristic property values and generated channel values.
extension CharacteristicPropertyChannelConverter on api.CharacteristicProperty {
  /// Creates a channel characteristic property from [property].
  static api.CharacteristicProperty fromCharacteristicProperty(
    CharacteristicProperty property,
  ) {
    return api.CharacteristicProperty(
      broadcast: property.broadcast,
      read: property.read,
      writeWithoutResponse: property.writeWithoutResponse,
      write: property.write,
      notify: property.notify,
      indicate: property.indicate,
      authenticatedSignedWrites: property.authenticatedSignedWrites,
      extendedProperties: property.extendedProperties,
      notifyEncryptionRequired: property.notifyEncryptionRequired,
      indicateEncryptionRequired: property.indicateEncryptionRequired,
    );
  }

  /// Returns this channel characteristic property in the domain representation.
  CharacteristicProperty toCharacteristicProperty() {
    return CharacteristicProperty(
      broadcast: broadcast,
      read: read,
      writeWithoutResponse: writeWithoutResponse,
      write: write,
      notify: notify,
      indicate: indicate,
      authenticatedSignedWrites: authenticatedSignedWrites,
      extendedProperties: extendedProperties,
      notifyEncryptionRequired: notifyEncryptionRequired,
      indicateEncryptionRequired: indicateEncryptionRequired,
    );
  }
}

/// Converts between domain peripheral-manager session values and generated channel values.
extension PeripheralManagerSessionConverter on PeripheralManagerSession {
  /// Creates a domain peripheral-manager session from [session].
  static PeripheralManagerSession fromPeripheralManagerSession(
    api.PeripheralManagerSession session,
  ) {
    return PeripheralManagerSession(
      clientIdentifier: session.clientIdentifier,
      adapterIdentifier: session.adapterIdentifier,
      restorationIdentifier: session.restorationIdentifier,
    );
  }

  /// Returns this peripheral-manager session in the generated channel representation.
  api.PeripheralManagerSession toPeripheralManagerSession() {
    return api.PeripheralManagerSession(
      clientIdentifier: clientIdentifier,
      adapterIdentifier: adapterIdentifier,
      restorationIdentifier: restorationIdentifier,
    );
  }
}

/// Converts between domain peripheral-manager session values and generated channel values.
extension PeripheralManagerSessionChannelConverter
    on api.PeripheralManagerSession {
  /// Creates a channel peripheral-manager session from [session].
  static api.PeripheralManagerSession fromPeripheralManagerSession(
    PeripheralManagerSession session,
  ) {
    return api.PeripheralManagerSession(
      clientIdentifier: session.clientIdentifier,
      adapterIdentifier: session.adapterIdentifier,
      restorationIdentifier: session.restorationIdentifier,
    );
  }

  /// Returns this channel peripheral-manager session in the domain representation.
  PeripheralManagerSession toPeripheralManagerSession() {
    return PeripheralManagerSession(
      clientIdentifier: clientIdentifier,
      adapterIdentifier: adapterIdentifier,
      restorationIdentifier: restorationIdentifier,
    );
  }
}

/// Converts between domain characteristic permission values and generated channel values.
extension CharacteristicPermissionConverter on CharacteristicPermission {
  /// Creates a domain characteristic permission from [permission].
  static CharacteristicPermission fromCharacteristicPermission(
    api.CharacteristicPermission permission,
  ) {
    return CharacteristicPermission(
      readable: permission.readable,
      writeable: permission.writeable,
      readEncryptionRequired: permission.readEncryptionRequired,
      writeEncryptionRequired: permission.writeEncryptionRequired,
    );
  }

  /// Returns this characteristic permission in the generated channel representation.
  api.CharacteristicPermission toCharacteristicPermission() {
    return api.CharacteristicPermission(
      readable: readable,
      writeable: writeable,
      readEncryptionRequired: readEncryptionRequired,
      writeEncryptionRequired: writeEncryptionRequired,
    );
  }
}

/// Converts between domain characteristic permission values and generated channel values.
extension CharacteristicPermissionChannelConverter
    on api.CharacteristicPermission {
  /// Creates a channel characteristic permission from [permission].
  static api.CharacteristicPermission fromCharacteristicPermission(
    CharacteristicPermission permission,
  ) {
    return api.CharacteristicPermission(
      readable: permission.readable,
      writeable: permission.writeable,
      readEncryptionRequired: permission.readEncryptionRequired,
      writeEncryptionRequired: permission.writeEncryptionRequired,
    );
  }

  /// Returns this channel characteristic permission in the domain representation.
  CharacteristicPermission toCharacteristicPermission() {
    return CharacteristicPermission(
      readable: readable,
      writeable: writeable,
      readEncryptionRequired: readEncryptionRequired,
      writeEncryptionRequired: writeEncryptionRequired,
    );
  }
}

/// Converts between domain ATT result values and generated channel values.
extension AttResultConverter on AttResult {
  /// Creates a domain ATT result from [result].
  static AttResult fromAttResult(api.AttResult result) {
    switch (result) {
      case api.AttResult.success:
        return AttResult.success;
      case api.AttResult.invalidHandle:
        return AttResult.invalidHandle;
      case api.AttResult.readNotPermitted:
        return AttResult.readNotPermitted;
      case api.AttResult.writeNotPermitted:
        return AttResult.writeNotPermitted;
      case api.AttResult.invalidOffset:
        return AttResult.invalidOffset;
      case api.AttResult.attributeNotFound:
        return AttResult.attributeNotFound;
      case api.AttResult.unlikelyError:
        return AttResult.unlikelyError;
    }
  }

  /// Returns this ATT result in the generated channel representation.
  api.AttResult toAttResult() {
    switch (this) {
      case AttResult.success:
        return api.AttResult.success;
      case AttResult.invalidHandle:
        return api.AttResult.invalidHandle;
      case AttResult.readNotPermitted:
        return api.AttResult.readNotPermitted;
      case AttResult.writeNotPermitted:
        return api.AttResult.writeNotPermitted;
      case AttResult.invalidOffset:
        return api.AttResult.invalidOffset;
      case AttResult.attributeNotFound:
        return api.AttResult.attributeNotFound;
      case AttResult.unlikelyError:
        return api.AttResult.unlikelyError;
    }
  }
}

/// Converts between domain ATT result values and generated channel values.
extension AttResultChannelConverter on api.AttResult {
  /// Creates a channel ATT result from [result].
  static api.AttResult fromAttResult(AttResult result) {
    switch (result) {
      case AttResult.success:
        return api.AttResult.success;
      case AttResult.invalidHandle:
        return api.AttResult.invalidHandle;
      case AttResult.readNotPermitted:
        return api.AttResult.readNotPermitted;
      case AttResult.writeNotPermitted:
        return api.AttResult.writeNotPermitted;
      case AttResult.invalidOffset:
        return api.AttResult.invalidOffset;
      case AttResult.attributeNotFound:
        return api.AttResult.attributeNotFound;
      case AttResult.unlikelyError:
        return api.AttResult.unlikelyError;
    }
  }

  /// Returns this channel ATT result in the domain representation.
  AttResult toAttResult() {
    switch (this) {
      case api.AttResult.success:
        return AttResult.success;
      case api.AttResult.invalidHandle:
        return AttResult.invalidHandle;
      case api.AttResult.readNotPermitted:
        return AttResult.readNotPermitted;
      case api.AttResult.writeNotPermitted:
        return AttResult.writeNotPermitted;
      case api.AttResult.invalidOffset:
        return AttResult.invalidOffset;
      case api.AttResult.attributeNotFound:
        return AttResult.attributeNotFound;
      case api.AttResult.unlikelyError:
        return AttResult.unlikelyError;
    }
  }
}

/// Converts between domain ATT request values and generated channel values.
extension AttRequestConverter on AttRequest {
  /// Creates a domain ATT request from [request].
  static AttRequest fromAttRequest(api.AttRequest request) {
    return AttRequest(
      requestId: request.requestId,
      centralIdentifier: request.centralIdentifier,
      characteristicUuid: request.characteristicUuid,
      serviceUuid: request.serviceUuid,
      offset: request.offset,
      value: request.value,
    );
  }

  /// Returns this ATT request in the generated channel representation.
  api.AttRequest toAttRequest() {
    return api.AttRequest(
      requestId: requestId,
      centralIdentifier: centralIdentifier,
      characteristicUuid: characteristicUuid,
      serviceUuid: serviceUuid,
      offset: offset,
      value: value,
    );
  }
}

/// Converts between domain ATT request values and generated channel values.
extension AttRequestChannelConverter on api.AttRequest {
  /// Creates a channel ATT request from [request].
  static api.AttRequest fromAttRequest(AttRequest request) {
    return api.AttRequest(
      requestId: request.requestId,
      centralIdentifier: request.centralIdentifier,
      characteristicUuid: request.characteristicUuid,
      serviceUuid: request.serviceUuid,
      offset: request.offset,
      value: request.value,
    );
  }

  /// Returns this channel ATT request in the domain representation.
  AttRequest toAttRequest() {
    return AttRequest(
      requestId: requestId,
      centralIdentifier: centralIdentifier,
      characteristicUuid: characteristicUuid,
      serviceUuid: serviceUuid,
      offset: offset,
      value: value,
    );
  }
}

/// Converts between domain mutable descriptor values and generated channel values.
extension MutableDescriptorConverter on MutableDescriptor {
  /// Creates a domain mutable descriptor from [descriptor].
  static MutableDescriptor fromMutableDescriptor(
    api.MutableDescriptor descriptor,
  ) {
    return MutableDescriptor(
      uuid: descriptor.uuid,
      value: descriptor.value,
    );
  }

  /// Returns this mutable descriptor in the generated channel representation.
  api.MutableDescriptor toMutableDescriptor() {
    return api.MutableDescriptor(
      uuid: uuid,
      value: value,
    );
  }
}

/// Converts between domain mutable descriptor values and generated channel values.
extension MutableDescriptorChannelConverter on api.MutableDescriptor {
  /// Creates a channel mutable descriptor from [descriptor].
  static api.MutableDescriptor fromMutableDescriptor(
    MutableDescriptor descriptor,
  ) {
    return api.MutableDescriptor(
      uuid: descriptor.uuid,
      value: descriptor.value,
    );
  }

  /// Returns this channel mutable descriptor in the domain representation.
  MutableDescriptor toMutableDescriptor() {
    return MutableDescriptor(
      uuid: uuid,
      value: value,
    );
  }
}

/// Converts between domain mutable characteristic values and generated channel values.
extension MutableCharacteristicConverter on MutableCharacteristic {
  /// Creates a domain mutable characteristic from [characteristic].
  static MutableCharacteristic fromMutableCharacteristic(
    api.MutableCharacteristic characteristic,
  ) {
    return MutableCharacteristic(
      uuid: characteristic.uuid,
      properties: characteristic.properties != null
          ? CharacteristicPropertyConverter.fromCharacteristicProperty(
              characteristic.properties!,
            )
          : null,
      permissions: characteristic.permissions != null
          ? CharacteristicPermissionConverter.fromCharacteristicPermission(
              characteristic.permissions!,
            )
          : null,
      value: characteristic.value,
      descriptors: characteristic.descriptors?.nonNulls
          .map(MutableDescriptorConverter.fromMutableDescriptor)
          .toList(),
    );
  }

  /// Returns this mutable characteristic in the generated channel representation.
  api.MutableCharacteristic toMutableCharacteristic() {
    return api.MutableCharacteristic(
      uuid: uuid,
      properties: properties?.toCharacteristicProperty(),
      permissions: permissions?.toCharacteristicPermission(),
      value: value,
      descriptors: descriptors?.map((e) => e.toMutableDescriptor()).toList(),
    );
  }
}

/// Converts between domain mutable characteristic values and generated channel values.
extension MutableCharacteristicChannelConverter on api.MutableCharacteristic {
  /// Creates a channel mutable characteristic from [characteristic].
  static api.MutableCharacteristic fromMutableCharacteristic(
    MutableCharacteristic characteristic,
  ) {
    return api.MutableCharacteristic(
      uuid: characteristic.uuid,
      properties: characteristic.properties != null
          ? CharacteristicPropertyChannelConverter.fromCharacteristicProperty(
              characteristic.properties!,
            )
          : null,
      permissions: characteristic.permissions != null
          ? CharacteristicPermissionChannelConverter
              .fromCharacteristicPermission(
              characteristic.permissions!,
            )
          : null,
      value: characteristic.value,
      descriptors: characteristic.descriptors
          ?.map(MutableDescriptorChannelConverter.fromMutableDescriptor)
          .toList(),
    );
  }

  /// Returns this channel mutable characteristic in the domain representation.
  MutableCharacteristic toMutableCharacteristic() {
    return MutableCharacteristic(
      uuid: uuid,
      properties: properties?.toCharacteristicProperty(),
      permissions: permissions?.toCharacteristicPermission(),
      value: value,
      descriptors:
          descriptors?.nonNulls.map((e) => e.toMutableDescriptor()).toList(),
    );
  }
}

/// Converts between domain mutable service values and generated channel values.
extension MutableServiceConverter on MutableService {
  /// Creates a domain mutable service from [service].
  static MutableService fromMutableService(api.MutableService service) {
    return MutableService(
      uuid: service.uuid,
      isPrimary: service.isPrimary,
      characteristics: service.characteristics.nonNulls
          .map(MutableCharacteristicConverter.fromMutableCharacteristic)
          .toList(),
    );
  }

  /// Returns this mutable service in the generated channel representation.
  api.MutableService toMutableService() {
    return api.MutableService(
      uuid: uuid,
      isPrimary: isPrimary,
      characteristics:
          characteristics.map((e) => e.toMutableCharacteristic()).toList(),
    );
  }
}

/// Converts between domain mutable service values and generated channel values.
extension MutableServiceChannelConverter on api.MutableService {
  /// Creates a channel mutable service from [service].
  static api.MutableService fromMutableService(MutableService service) {
    return api.MutableService(
      uuid: service.uuid,
      isPrimary: service.isPrimary,
      characteristics: service.characteristics
          .map(MutableCharacteristicChannelConverter.fromMutableCharacteristic)
          .toList(),
    );
  }

  /// Returns this channel mutable service in the domain representation.
  MutableService toMutableService() {
    return MutableService(
      uuid: uuid,
      isPrimary: isPrimary,
      characteristics: characteristics.nonNulls
          .map((e) => e.toMutableCharacteristic())
          .toList(),
    );
  }
}

/// Removes map entries whose values are null.
extension NonNullMapEntries<K, V> on Map<K, V> {
  Map<K, V> get nonNulls {
    final entries = this.entries.where((element) => element.value != null);
    return Map.fromEntries(entries);
  }
}

/// Converts map entries with non-null values to a map.
extension NonNullListMapEntries<K, V> on Iterable<MapEntry<K, V>> {
  Map<K, V> get nonNullsKeys {
    final entries = where((element) => element.key != null);
    return Map.fromEntries(entries);
  }
}
