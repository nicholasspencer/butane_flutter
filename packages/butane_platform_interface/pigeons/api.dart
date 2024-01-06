import 'package:pigeon/pigeon.dart';

enum ClientState {
  unknown,
  resetting,
  unsupported,
  unauthorized,
  poweredOff,
  poweredOn,
}

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
class PeripheralSessionIdentifier {
  PeripheralSessionIdentifier({
    required this.identifier,
    required this.clientIdentifier,
    required this.adapterIdentifier,
  });

  final String identifier;

  final String? clientIdentifier;

  final String? adapterIdentifier;
}

class PeripheralData {
  PeripheralData({
    required this.identifier,
    this.name,
    this.rssi,
  });

  final PeripheralSessionIdentifier identifier;

  final String? name;

  final double? rssi;
}

class AdvertisementData {
  AdvertisementData({
    required this.localName,
    required this.txPowerLevel,
    required this.manufacturerData,
    required this.serviceData,
    required this.serviceUuids,
  });

  final String? localName;

  final int? txPowerLevel;

  final Uint8List? manufacturerData;

  final Map<String?, Uint8List?>? serviceData;

  final List<String?>? serviceUuids;
}

class ScanData {
  ScanData({
    required this.peripheral,
    required this.advertisementData,
  });

  final PeripheralData peripheral;

  final AdvertisementData advertisementData;
}

enum ConnectionState {
  disconnected,
  connecting,
  reconnecting,
  connected,
  disconnecting,
}

abstract interface class AttributeData {
  AttributeData({
    required this.uuid,
  });

  final String uuid;
}

class ServiceData implements AttributeData {
  ServiceData({
    required this.uuid,
    this.isPrimary,
  });

  @override
  final String uuid;

  final bool? isPrimary;
}

class CharacteristicData implements AttributeData {
  CharacteristicData({
    required this.uuid,
    this.value,
    this.descriptors,
    this.properties,
  });

  @override
  final String uuid;

  /// List of bytes
  final List<int?>? value;

  final List<DescriptorData?>? descriptors;

  final CharacteristicProperty? properties;
}

class DescriptorData implements AttributeData {
  DescriptorData({
    required this.uuid,
    this.value,
  });

  @override
  final String uuid;

  /// List of bytes
  final List<int?>? value;
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

/// The APIs that are used to communicate from the flutter plugin to the
/// host platform.
@HostApi()
abstract class ButaneHostApi {
  /// "Central" APIs.

  @async
  ClientState state({
    String? clientIdentifier,
  });

  /// Scans for peripherals that are advertising services.
  @async
  void scan({
    String? clientIdentifier,
    List<String>? forServices = const [],
  });

  @async
  void cancelScan({
    String? clientIdentifier,
  });

  /// A list of known peripherals optionally filtered by their identifiers.
  @async
  List<PeripheralData> peripherals({
    String? clientIdentifier,
    List<String>? peripheralIdentifiers = const [],
  });

  /// A list of connected peripherals identified by an offered service.
  @async
  List<PeripheralData> connectedPeripherals({
    String? clientIdentifier,
    List<String>? serviceUuids = const [],
  });

  /// Establishes a connection to the peripheral.
  @async
  void connect({
    required PeripheralSessionIdentifier sessionIdentifier,
  });

  /// Cancels an active or pending connection to the peripheral.
  @async
  void cancelConnection({
    required PeripheralSessionIdentifier sessionIdentifier,
  });

  /// Discovers services offered by the peripheral.
  @async
  void discoverServices({
    required PeripheralSessionIdentifier sessionIdentifier,
    List<String>? serviceUuids = const [],
  });

  @async
  List<ServiceData> services({
    required PeripheralSessionIdentifier sessionIdentifier,
  });

  /// Discovers characteristics offered by the service.
  @async
  void discoverCharacteristics({
    required PeripheralSessionIdentifier sessionIdentifier,
    required String serviceUuid,
    List<String>? characteristicUuids = const [],
  });

  @async
  List<CharacteristicData> characteristics({
    required PeripheralSessionIdentifier sessionIdentifier,
    required String serviceUuid,
  });

  /// Reads the value of the characteristic.
  @async
  Uint8List readCharacteristic({
    required PeripheralSessionIdentifier sessionIdentifier,
    required String serviceUuid,
    required String characteristicUuid,
  });

  /// Writes the value of the characteristic.
  @async
  void writeCharacteristic({
    required PeripheralSessionIdentifier sessionIdentifier,
    required String serviceUuid,
    required String characteristicUuid,
    required List<int> value,
    bool withoutResponse = false,
  });

  @async
  void watchCharacteristic({
    required PeripheralSessionIdentifier sessionIdentifier,
    required String serviceUuid,
    required String characteristicUuid,
  });

  /// Enables notifications or indications for the characteristic.
  @async
  void setNotification({
    required PeripheralSessionIdentifier sessionIdentifier,
    required String serviceUuid,
    required String characteristicUuid,
    required bool enabled,
  });

  /// Reads the value of the descriptor.
  @async
  List<int> readDescriptor({
    required PeripheralSessionIdentifier sessionIdentifier,
    required String serviceUuid,
    required String descriptorUuid,
  });

  /// Writes the value of the descriptor.
  @async
  void writeDescriptor({
    required PeripheralSessionIdentifier sessionIdentifier,
    required String serviceUuid,
    required String descriptorUuid,
    required List<int> value,
  });

  /// Requests a read of the RSSI for the peripheral.
  @async
  int readRssi({
    required PeripheralSessionIdentifier sessionIdentifier,
  });

  /// Requests a MTU size change.
  @async
  int requestMtu({
    required PeripheralSessionIdentifier sessionIdentifier,
    required int mtu,
  });

  /// "Peripheral" APIs.
}

/// The APIs that are used from the host platform to communicate with the
/// flutter plugin.
@FlutterApi()
abstract class ButaneFlutterApi {
  /// "Central Client" APIs.

  void onClientState(
    String? clientIdentifier,
    ClientState state,
  );

  void onScanResult(
    ScanData scanResult,
  );

  /// "Peripheral" APIs.

  void onConnectionState(
    PeripheralData peripheral,
    ConnectionState state,
  );

  void onServicesDiscovered(
    PeripheralData peripheral,
  );

  void onCharacteristicsDiscovered(
    PeripheralData peripheral,
    ServiceData service,
  );

  void onDescriptorsDiscovered(
    PeripheralData peripheral,
    CharacteristicData characteristic,
  );

  void onCharacteristicValue(
    PeripheralData peripheral,
    CharacteristicData characteristic,
    Uint8List value,
  );

  void onDescriptorValue(
    PeripheralData peripheral,
    DescriptorData descriptor,
    Uint8List value,
  );

  void onRssi(
    PeripheralData peripheral,
    int rssi,
  );
}
