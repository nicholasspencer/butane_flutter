import 'dart:async';
import 'dart:typed_data';

import 'package:meta/meta.dart';

import '../interface/interface.dart';
import 'api.g.dart' as api;

typedef ClientStateResult = ({
  Session? session,
  api.ClientState state,
});

typedef ConnectionStateResult = ({
  api.Peripheral peripheral,
  api.ConnectionState state,
});

typedef CharacteristicValueResult = ({
  api.Peripheral peripheral,
  api.Characteristic characteristic,
  Uint8List value,
});

typedef RssiResult = ({
  api.Peripheral peripheral,
  int rssi,
});

/// A default implementation of [ButanePlatformInterface] which uses generated
/// method channels to call platform-specific code.
base class ButanePlatform extends ButanePlatformInterface {
  static void registerWith() {
    ButanePlatformInterface.instance = ButanePlatform();
  }

  @protected
  late final api.ButaneHostApi hostApi = api.ButaneHostApi();

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
    Iterable<String> serviceUuids = const [],
  }) async {
    await hostApi.discoverServices(
      session: session.toSession(),
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
    Iterable<String> characteristicUuids = const [],
  }) async {
    await hostApi.discoverCharacteristics(
      session: session.toSession(),
      serviceUuid: serviceUuid,
      characteristicUuids: characteristicUuids.toList(),
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

  @override
  Stream<Uint8List> watchCharacteristic({
    required PeripheralSession session,
    required String serviceUuid,
    required String characteristicUuid,
  }) {
    hostApi.watchCharacteristic(
      session: session.toSession(),
      serviceUuid: serviceUuid,
      characteristicUuid: characteristicUuid,
    );

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
}

base class ButaneFlutterApi extends api.ButaneFlutterApi {
  ButaneFlutterApi() {
    api.ButaneFlutterApi.setup(this);
  }

  // Client State

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

  // Characteristic Discovery

  @override
  void onCharacteristicsDiscovered(
    api.Peripheral peripheral,
    api.Service service,
  ) {
    // TODO: implement onCharacteristicsDiscovered
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

  // Descriptor Discovery

  @override
  void onDescriptorsDiscovered(
    api.Peripheral peripheral,
    api.Characteristic characteristic,
  ) {
    // TODO: implement onDescriptorsDiscovered
  }
}

// extension ScanResultStreamFilter on Stream<ScanResult> {
//   Stream<ScanResult> forRequest(String? requestIdentifier) {
//     return where((result) => result.requestIdentifier == requestIdentifier);
//   }
// }

extension ConnectionStateResultStreamFilter on Stream<ConnectionStateResult> {
  Stream<ConnectionStateResult> forPeripheral(String peripheralIdentifier) {
    return where(
      (result) =>
          result.peripheral.session.peripheralIdentifier ==
          peripheralIdentifier,
    );
  }
}

extension CharacteristicValueResultStreamFilter
    on Stream<CharacteristicValueResult> {
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

  Stream<Uint8List> valueForCharacteristic({
    required String characteristicUuid,
    required String peripheralIdentifier,
  }) {
    return forCharacteristic(
      characteristicUuid: characteristicUuid,
      peripheralIdentifier: peripheralIdentifier,
    ).map((result) => Uint8List.fromList(result.value.nonNulls.toList()));
  }
}

/// Records

extension SessionConverter on Session {
  static Session fromSession(api.Session session) {
    return Session(
      peripheralIdentifier: session.peripheralIdentifier,
      clientIdentifier: session.clientIdentifier,
      adapterIdentifier: session.adapterIdentifier,
      restorationIdentifier: session.restorationIdentifier,
    );
  }

  api.Session toSession() {
    return api.Session(
      peripheralIdentifier: peripheralIdentifier,
      clientIdentifier: clientIdentifier,
      adapterIdentifier: adapterIdentifier,
      restorationIdentifier: restorationIdentifier,
    );
  }
}

extension SessionChannelConverter on api.Session {
  static api.Session fromSession(Session session) {
    return api.Session(
      peripheralIdentifier: session.peripheralIdentifier,
      clientIdentifier: session.clientIdentifier,
      adapterIdentifier: session.adapterIdentifier,
      restorationIdentifier: session.restorationIdentifier,
    );
  }

  Session toSession() {
    return Session(
      peripheralIdentifier: peripheralIdentifier,
      clientIdentifier: clientIdentifier,
      adapterIdentifier: adapterIdentifier,
      restorationIdentifier: restorationIdentifier,
    );
  }
}

extension PeripheralSessionConverter on PeripheralSession {
  static PeripheralSession fromSession(api.PeripheralSession session) {
    return PeripheralSession(
      peripheralIdentifier: session.peripheralIdentifier,
      clientIdentifier: session.clientIdentifier,
      adapterIdentifier: session.adapterIdentifier,
      restorationIdentifier: session.restorationIdentifier,
    );
  }

  api.PeripheralSession toSession() {
    return api.PeripheralSession(
      peripheralIdentifier: peripheralIdentifier,
      clientIdentifier: clientIdentifier,
      adapterIdentifier: adapterIdentifier,
      restorationIdentifier: restorationIdentifier,
    );
  }
}

extension PeripheralChannelSessionConverter on api.PeripheralSession {
  static api.PeripheralSession fromSession(PeripheralSession session) {
    return api.PeripheralSession(
      peripheralIdentifier: session.peripheralIdentifier,
      clientIdentifier: session.clientIdentifier,
      adapterIdentifier: session.adapterIdentifier,
      restorationIdentifier: session.restorationIdentifier,
    );
  }

  PeripheralSession toSession() {
    return PeripheralSession(
      peripheralIdentifier: peripheralIdentifier,
      clientIdentifier: clientIdentifier,
      adapterIdentifier: adapterIdentifier,
      restorationIdentifier: restorationIdentifier,
    );
  }
}

extension ClientStateConverter on ClientState {
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

extension ClientStateChannelConverter on api.ClientState {
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

extension ConnectionStateConverter on ConnectionState {
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

extension ConnectionStateChannelConverter on api.ConnectionState {
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

extension PeripheralConverter on Peripheral {
  static Peripheral fromPeripheral(api.Peripheral peripheral) {
    return Peripheral(
      session: PeripheralSessionConverter.fromSession(peripheral.session),
      name: peripheral.name,
      rssi: peripheral.rssi,
      state: ConnectionStateConverter.fromConnectionState(peripheral.state),
    );
  }

  api.Peripheral toPeripheral() {
    return api.Peripheral(
      session: session.toSession(),
      name: name,
      rssi: rssi,
      state: state.toConnectionState(),
    );
  }
}

extension PeripheralChannelConverter on api.Peripheral {
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

  Peripheral toPeripheral() {
    return Peripheral(
      session: session.toSession(),
      name: name,
      rssi: rssi,
      state: state.toConnectionState(),
    );
  }
}

extension AdvertisementDataConverter on AdvertisementData {
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

extension AdvertisementDataChannelConverter on api.AdvertisementData {
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

extension ScanResultConverter on ScanResult {
  static ScanResult fromScanResult(api.ScanResult scanResult) {
    return ScanResult(
      peripheral: PeripheralConverter.fromPeripheral(scanResult.peripheral),
      advertisementData: AdvertisementDataConverter.fromAdvertisementData(
        scanResult.advertisementData,
      ),
    );
  }

  api.ScanResult toScanResult() {
    return api.ScanResult(
      peripheral: peripheral.toPeripheral(),
      advertisementData: advertisementData.toAdvertisementData(),
    );
  }
}

extension ScanResultChannelConverter on api.ScanResult {
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

  ScanResult toScanResult() {
    return ScanResult(
      peripheral: peripheral.toPeripheral(),
      advertisementData: advertisementData.toAdvertisementData(),
    );
  }
}

extension ServiceConverter on Service {
  static Service fromService(api.Service service) {
    return Service(
      uuid: service.uuid,
      isPrimary: service.isPrimary,
    );
  }

  api.Service toService() {
    return api.Service(
      uuid: uuid,
      isPrimary: isPrimary,
    );
  }
}

extension ServiceChannelConverter on api.Service {
  static api.Service fromService(Service service) {
    return api.Service(
      uuid: service.uuid,
      isPrimary: service.isPrimary,
    );
  }

  Service toService() {
    return Service(
      uuid: uuid,
      isPrimary: isPrimary,
    );
  }
}

extension CharacteristicConverter on Characteristic {
  static Characteristic fromCharacteristic(api.Characteristic characteristic) {
    return Characteristic(
      uuid: characteristic.uuid,
      value: characteristic.value,
      descriptors: characteristic.descriptors?.nonNulls
          .map(DescriptorConverter.fromDescriptor)
          .toList(),
      properties: CharacteristicPropertyConverter.fromCharacteristicProperty(
        characteristic.properties!,
      ),
    );
  }

  api.Characteristic toCharacteristic() {
    return api.Characteristic(
      uuid: uuid,
      value: value,
      descriptors: descriptors?.nonNulls.map((e) => e.toDescriptor()).toList(),
      properties: properties?.toCharacteristicProperty(),
    );
  }
}

extension CharacteristicChannelConverter on api.Characteristic {
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

  Characteristic toCharacteristic() {
    return Characteristic(
      uuid: uuid,
      value: value,
      descriptors: descriptors?.nonNulls.map((e) => e.toDescriptor()).toList(),
      properties: properties?.toCharacteristicProperty(),
    );
  }
}

extension DescriptorConverter on Descriptor {
  static Descriptor fromDescriptor(api.Descriptor descriptor) {
    return Descriptor(
      uuid: descriptor.uuid,
      value: descriptor.value,
    );
  }

  api.Descriptor toDescriptor() {
    return api.Descriptor(
      uuid: uuid,
      value: value,
    );
  }
}

extension DescriptorChannelConverter on api.Descriptor {
  static api.Descriptor fromDescriptor(Descriptor descriptor) {
    return api.Descriptor(
      uuid: descriptor.uuid,
      value: descriptor.value,
    );
  }

  Descriptor toDescriptor() {
    return Descriptor(
      uuid: uuid,
      value: value,
    );
  }
}

extension CharacteristicPropertyConverter on CharacteristicProperty {
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

extension CharacteristicPropertyChannelConverter on api.CharacteristicProperty {
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

extension NonNullMapEntries<K, V> on Map<K, V> {
  Map<K, V> get nonNulls {
    final entries = this.entries.where((element) => element.value != null);
    return Map.fromEntries(entries);
  }
}

extension NonNullListMapEntries<K, V> on Iterable<MapEntry<K, V>> {
  Map<K, V> get nonNullsKeys {
    final entries = where((element) => element.key != null);
    return Map.fromEntries(entries);
  }
}
