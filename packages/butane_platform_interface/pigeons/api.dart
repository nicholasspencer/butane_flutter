import 'package:pigeon/pigeon.dart';

enum ManagerState {
  unknown,
  resetting,
  unsupported,
  unauthorized,
  poweredOff,
  poweredOn,
}

class PeripheralData {
  PeripheralData({
    required this.identifier,
    this.name,
    this.rssi,
  });

  final String identifier;

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

sealed class CharacteristicProperty {
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

  /// Scans for peripherals that are advertising services.
  @async
  void scan({
    required String? requestIdentifier,
    List<String>? forServices = const [],
  });

  void cancelScan({
    required String? requestIdentifier,
  });

  /// A list of known peripherals optionally filtered by their identifiers.
  @async
  List<PeripheralData> peripherals({
    List<String>? peripheralIdentifiers = const [],
  });

  /// Establishes a connection to the peripheral.
  @async
  void connect({
    required String peripheralIdentifier,
  });

  /// Cancels an active or pending connection to the peripheral.
  @async
  void cancelConnection({
    required String peripheralIdentifier,
  });

  /// A list of connected peripherals identified by an offered service.
  @async
  List<PeripheralData> connectedPeripherals({
    List<String>? serviceUuids = const [],
  });

  /// Discovers services offered by the peripheral.
  @async
  void discoverServices({
    required String peripheralIdentifier,
    List<String>? serviceUuids = const [],
  });

  @async
  List<ServiceData> services({
    required String peripheralIdentifier,
  });

  /// Discovers characteristics offered by the service.
  @async
  void discoverCharacteristics({
    required String peripheralIdentifier,
    required String serviceUuid,
    List<String>? characteristicUuids = const [],
  });

  @async
  List<CharacteristicData> characteristics({
    required String peripheralIdentifier,
    required String serviceUuid,
  });

  /// Reads the value of the characteristic.
  @async
  Uint8List readCharacteristic({
    required String peripheralIdentifier,
    required String serviceUuid,
    required String characteristicUuid,
  });

  /// Writes the value of the characteristic.
  @async
  void writeCharacteristic({
    required String peripheralIdentifier,
    required String serviceUuid,
    required String characteristicUuid,
    required List<int> value,
    bool withoutResponse = false,
  });

  @async
  void watchCharacteristic({
    required String peripheralIdentifier,
    required String serviceUuid,
    required String characteristicUuid,
  });

  /// Enables notifications or indications for the characteristic.
  @async
  void setNotification({
    required String peripheralIdentifier,
    required String serviceUuid,
    required String characteristicUuid,
    required bool enabled,
  });

  /// Reads the value of the descriptor.
  @async
  List<int> readDescriptor({
    required String peripheralIdentifier,
    required String serviceUuid,
    required String descriptorUuid,
  });

  /// Writes the value of the descriptor.
  @async
  void writeDescriptor({
    required String peripheralIdentifier,
    required String serviceUuid,
    required String descriptorUuid,
    required List<int> value,
  });

  /// Requests a read of the RSSI for the peripheral.
  @async
  int readRssi({
    required String peripheralIdentifier,
  });

  /// Requests a MTU size change.
  @async
  int requestMtu({
    required String peripheralIdentifier,
    required int mtu,
  });

  /// "Peripheral" APIs.
}

/// The APIs that are used from the host platform to communicate with the
/// flutter plugin.
@FlutterApi()
abstract class ButaneFlutterApi {
  /// "CentralManager" APIs.

  void onManagerState(
    ManagerState state,
  );

  void onScanResult(
    String? requestIdentifier,
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
