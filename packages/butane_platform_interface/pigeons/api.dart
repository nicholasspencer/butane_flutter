import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    cppHeaderOut: '../butane_windows/windows/Api.gen.h',
    cppSourceOut: '../butane_windows/windows/Api.gen.cpp',
    cppOptions: CppOptions(namespace: 'butane_windows'),
  ),
)
enum ClientState {
  unknown,
  resetting,
  unsupported,
  unauthorized,
  poweredOff,
  poweredOn,
}

enum ConnectionState {
  disconnected,
  connecting,
  reconnecting,
  connected,
  disconnecting,
}

sealed class Session {}

/// A unique identifier for a peripheral coupled with the [adapterIdentifier] and
/// [clientIdentifier] that discovered it.
///
/// The [clientIdentifier] is the identifier of the client that discovered the
/// peripheral. This is useful when multiple clients are connected to the same
/// adapter. If omitted, the default client is used.
///
/// The [adapterIdentifier] is the identifier of the adapter that discovered the
/// peripheral. This is useful when multiple adapters are available on the same
/// device. If omitted, the default adapter is used.
class ClientSession extends Session {
  ClientSession({
    this.peripheralIdentifier,
    this.clientIdentifier,
    this.adapterIdentifier,
    this.restorationIdentifier,
  });

  final String? peripheralIdentifier;

  final String? clientIdentifier;

  final String? adapterIdentifier;

  final String? restorationIdentifier;
}

class PeripheralSession extends Session {
  PeripheralSession({
    required this.peripheralIdentifier,
    this.clientIdentifier,
    this.adapterIdentifier,
    this.restorationIdentifier,
  });

  final String peripheralIdentifier;

  final String? clientIdentifier;

  final String? adapterIdentifier;

  final String? restorationIdentifier;
}

class PeripheralManagerSession extends Session {
  PeripheralManagerSession({
    this.clientIdentifier,
    this.adapterIdentifier,
    this.restorationIdentifier,
  });

  final String? clientIdentifier;

  final String? adapterIdentifier;

  final String? restorationIdentifier;
}

class Peripheral {
  Peripheral({
    required this.session,
    required this.state,
    this.name,
    this.rssi,
  });

  final PeripheralSession session;

  final String? name;

  final int? rssi;

  final ConnectionState state;
}

class AdvertisementData {
  AdvertisementData({
    required this.localName,
    required this.manufacturerData,
    required this.serviceData,
    required this.serviceUuids,
    required this.txPowerLevel,
    required this.isConnectable,
  });

  final String? localName;

  final Uint8List? manufacturerData;

  final List<String?>? serviceUuids;

  final Map<String?, Uint8List?>? serviceData;

  final int? txPowerLevel;

  final bool? isConnectable;
}

class ScanResult {
  ScanResult({required this.peripheral, required this.advertisementData});

  final Peripheral peripheral;

  final AdvertisementData advertisementData;
}

sealed class AttributeData {}

class Service extends AttributeData {
  Service({required this.uuid, this.isPrimary = false});

  final String uuid;

  final bool isPrimary;
}

class Characteristic extends AttributeData {
  Characteristic({
    required this.uuid,
    this.value,
    this.descriptors,
    this.properties,
  });

  final String uuid;

  final Uint8List? value;

  final List<Descriptor?>? descriptors;

  final CharacteristicProperty? properties;
}

class Descriptor extends AttributeData {
  Descriptor({required this.uuid, this.value});

  final String uuid;

  final Uint8List? value;
}

class CharacteristicProperty {
  const CharacteristicProperty({
    this.broadcast = false,
    this.read = false,
    this.writeWithoutResponse = false,
    this.write = false,
    this.notify = false,
    this.indicate = false,
    this.authenticatedSignedWrites = false,
    this.extendedProperties = false,
    this.notifyEncryptionRequired = false,
    this.indicateEncryptionRequired = false,
  });

  final bool broadcast;

  final bool read;

  final bool writeWithoutResponse;

  final bool write;

  final bool notify;

  final bool indicate;

  final bool authenticatedSignedWrites;

  final bool extendedProperties;

  final bool notifyEncryptionRequired;

  final bool indicateEncryptionRequired;
}

class CharacteristicPermission {
  const CharacteristicPermission({
    this.readable = false,
    this.writeable = false,
    this.readEncryptionRequired = false,
    this.writeEncryptionRequired = false,
  });

  final bool readable;

  final bool writeable;

  final bool readEncryptionRequired;

  final bool writeEncryptionRequired;
}

enum AttResult {
  success,
  invalidHandle,
  readNotPermitted,
  writeNotPermitted,
  invalidOffset,
  attributeNotFound,
  unlikelyError,
}

class AttRequest {
  AttRequest({
    required this.requestId,
    required this.centralIdentifier,
    required this.characteristicUuid,
    required this.serviceUuid,
    this.offset = 0,
    this.value,
  });

  final int requestId;

  final String centralIdentifier;

  final String characteristicUuid;

  final String serviceUuid;

  final int offset;

  final Uint8List? value;
}

class MutableDescriptor {
  MutableDescriptor({required this.uuid, this.value});

  final String uuid;

  final Uint8List? value;
}

class MutableCharacteristic {
  MutableCharacteristic({
    required this.uuid,
    this.properties,
    this.permissions,
    this.value,
    this.descriptors,
  });

  final String uuid;

  final CharacteristicProperty? properties;

  final CharacteristicPermission? permissions;

  final Uint8List? value;

  final List<MutableDescriptor?>? descriptors;
}

class MutableService {
  MutableService({
    required this.uuid,
    this.isPrimary = true,
    required this.characteristics,
  });

  final String uuid;

  final bool isPrimary;

  final List<MutableCharacteristic?> characteristics;
}

/// The APIs that are used to communicate from the flutter plugin to the
/// host platform.
@HostApi()
abstract class ButaneHostApi {
  /// "Central" APIs.

  @async
  ClientState state({ClientSession? session});

  /// Scans for peripherals that are advertising services.
  @async
  void scan({ClientSession? session, List<String>? forServices});

  @async
  void cancelScan({ClientSession? session});

  /// A list of known peripherals optionally filtered by their identifiers.
  @async
  List<Peripheral> peripherals({
    ClientSession? session,
    List<String> peripheralIdentifiers = const [],
  });

  /// A list of connected peripherals identified by an offered service.
  @async
  List<Peripheral> connectedPeripherals({
    ClientSession? session,
    List<String> serviceUuids = const [],
  });

  /// Establishes a connection to the peripheral.
  @async
  void connect({required PeripheralSession session});

  /// Cancels an active or pending connection to the peripheral.
  @async
  void cancelConnection({required PeripheralSession session});

  @async
  ConnectionState connectionState({required PeripheralSession session});

  /// Discovers services offered by the peripheral.
  @async
  void discoverServices({
    required PeripheralSession session,
    List<String>? serviceUuids,
  });

  @async
  List<Service> services({required PeripheralSession session});

  /// Discovers characteristics offered by the service.
  @async
  void discoverCharacteristics({
    required PeripheralSession session,
    required String serviceUuid,
    List<String>? characteristicUuids,
  });

  @async
  List<Characteristic> characteristics({
    required PeripheralSession session,
    required String serviceUuid,
  });

  /// Reads the value of the characteristic.
  @async
  Uint8List readCharacteristic({
    required PeripheralSession session,
    required String serviceUuid,
    required String characteristicUuid,
  });

  /// Writes the value of the characteristic.
  @async
  void writeCharacteristic({
    required PeripheralSession session,
    required String serviceUuid,
    required String characteristicUuid,
    required Uint8List value,
    bool withoutResponse = false,
  });

  @async
  void observeCharacteristic({
    bool observe = true,
    required PeripheralSession session,
    required String serviceUuid,
    required String characteristicUuid,
  });

  /// Reads the value of the descriptor.
  @async
  Uint8List readDescriptor({
    required PeripheralSession session,
    required String serviceUuid,
    required String characteristicUuid,
    required String descriptorUuid,
  });

  /// Writes the value of the descriptor.
  @async
  void writeDescriptor({
    required PeripheralSession session,
    required String serviceUuid,
    required String characteristicUuid,
    required String descriptorUuid,
    required Uint8List value,
  });

  /// Requests a read of the RSSI for the peripheral.
  @async
  int readRssi({required PeripheralSession session});

  /// Requests a target ATT MTU and returns the negotiated/effective ATT MTU.
  ///
  /// A platform without a client-side request ignores the target and reports
  /// its effective value.
  @async
  int requestMtu({required PeripheralSession session, required int mtu});

  /// "Peripheral" APIs.

  @async
  ClientState peripheralManagerState({
    required PeripheralManagerSession session,
  });

  @async
  void startAdvertising({
    required PeripheralManagerSession session,
    String? localName,
    List<String>? serviceUuids,
  });

  @async
  void stopAdvertising({required PeripheralManagerSession session});

  @async
  void addService({
    required PeripheralManagerSession session,
    required MutableService service,
  });

  @async
  void removeService({
    required PeripheralManagerSession session,
    required String serviceUuid,
  });

  @async
  void removeAllServices({required PeripheralManagerSession session});

  @async
  void respondToRequest({
    required PeripheralManagerSession session,
    required int requestId,
    required AttResult result,
    Uint8List? value,
  });

  @async
  bool updateValue({
    required PeripheralManagerSession session,
    required String serviceUuid,
    required String characteristicUuid,
    required Uint8List value,
  });
}

/// The APIs that are used from the host platform to communicate with the
/// flutter plugin.
@FlutterApi()
abstract class ButaneFlutterApi {
  /// "Central Client" APIs.

  void onClientState(String? clientIdentifier, ClientState state);

  void onScanResult(ScanResult scanResult);

  /// "Peripheral" APIs.

  void onConnectionState(Peripheral peripheral, ConnectionState state);

  void onCharacteristicValue(
    Peripheral peripheral,
    Characteristic characteristic,
    Uint8List value,
  );

  void onDescriptorValue(
    Peripheral peripheral,
    Descriptor descriptor,
    Uint8List value,
  );

  /// "Peripheral Manager" APIs.

  void onPeripheralManagerState(String? clientIdentifier, ClientState state);

  void onServiceAdded(String serviceUuid, String? error);

  void onReadRequest(AttRequest request);

  void onWriteRequests(List<AttRequest> requests);

  void onCentralSubscribed(
    String? clientIdentifier,
    String centralIdentifier,
    String serviceUuid,
    String characteristicUuid,
  );

  void onCentralUnsubscribed(
    String? clientIdentifier,
    String centralIdentifier,
    String serviceUuid,
    String characteristicUuid,
  );

  void onReadyToUpdateSubscribers(String? clientIdentifier);
}
