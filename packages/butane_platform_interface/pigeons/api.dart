import 'package:pigeon/pigeon.dart';

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
class Session {
  Session({
    required this.peripheralIdentifier,
    required this.clientIdentifier,
    required this.adapterIdentifier,
    required this.restorationIdentifier,
  });

  final String? peripheralIdentifier;

  final String? clientIdentifier;

  final String? adapterIdentifier;

  final String? restorationIdentifier;
}

class PeripheralSession implements Session {
  PeripheralSession({
    required this.peripheralIdentifier,
    required this.clientIdentifier,
    required this.adapterIdentifier,
    required this.restorationIdentifier,
  });

  @override
  final String peripheralIdentifier;

  @override
  final String? clientIdentifier;

  @override
  final String? adapterIdentifier;

  @override
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
  ScanResult({
    required this.peripheral,
    required this.advertisementData,
  });

  final Peripheral peripheral;

  final AdvertisementData advertisementData;
}

abstract interface class AttributeData {
  AttributeData({
    required this.uuid,
  });

  final String uuid;
}

class Service implements AttributeData {
  Service({
    required this.uuid,
    this.isPrimary = false,
  });

  @override
  final String uuid;

  final bool isPrimary;
}

class Characteristic implements AttributeData {
  Characteristic({
    required this.uuid,
    this.value,
    this.descriptors,
    this.properties,
  });

  @override
  final String uuid;

  final Uint8List? value;

  final List<Descriptor?>? descriptors;

  final CharacteristicProperty? properties;
}

class Descriptor implements AttributeData {
  Descriptor({
    required this.uuid,
    this.value,
  });

  @override
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

/// The APIs that are used to communicate from the flutter plugin to the
/// host platform.
@HostApi()
abstract class ButaneHostApi {
  /// "Central" APIs.

  @async
  ClientState state({
    Session? session,
  });

  /// Scans for peripherals that are advertising services.
  @async
  void scan({
    Session? session,
    List<String>? forServices = const [],
  });

  @async
  void cancelScan({
    Session? session,
  });

  /// A list of known peripherals optionally filtered by their identifiers.
  @async
  List<Peripheral> peripherals({
    Session? session,
    List<String> peripheralIdentifiers = const [],
  });

  /// A list of connected peripherals identified by an offered service.
  @async
  List<Peripheral> connectedPeripherals({
    Session? session,
    List<String> serviceUuids = const [],
  });

  /// Establishes a connection to the peripheral.
  @async
  void connect({
    required PeripheralSession session,
  });

  /// Cancels an active or pending connection to the peripheral.
  @async
  void cancelConnection({
    required PeripheralSession session,
  });

  @async
  ConnectionState connectionState({
    required PeripheralSession session,
  });

  /// Discovers services offered by the peripheral.
  @async
  void discoverServices({
    required PeripheralSession session,
    List<String>? serviceUuids = const [],
  });

  @async
  List<Service> services({
    required PeripheralSession session,
  });

  /// Discovers characteristics offered by the service.
  @async
  void discoverCharacteristics({
    required PeripheralSession session,
    required String serviceUuid,
    List<String>? characteristicUuids = const [],
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
    required List<int> value,
    bool withoutResponse = false,
  });

  @async
  void watchCharacteristic({
    required PeripheralSession session,
    required String serviceUuid,
    required String characteristicUuid,
  });

  /// Enables notifications or indications for the characteristic.
  @async
  void setNotification({
    required PeripheralSession session,
    required String serviceUuid,
    required String characteristicUuid,
    required bool enabled,
  });

  /// Reads the value of the descriptor.
  @async
  List<int> readDescriptor({
    required PeripheralSession session,
    required String serviceUuid,
    required String descriptorUuid,
  });

  /// Writes the value of the descriptor.
  @async
  void writeDescriptor({
    required PeripheralSession session,
    required String serviceUuid,
    required String descriptorUuid,
    required List<int> value,
  });

  /// Requests a read of the RSSI for the peripheral.
  @async
  int readRssi({
    required PeripheralSession session,
  });

  /// Requests a MTU size change.
  @async
  int requestMtu({
    required PeripheralSession session,
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
    ScanResult scanResult,
  );

  /// "Peripheral" APIs.

  void onConnectionState(
    Peripheral peripheral,
    ConnectionState state,
  );

  void onCharacteristicsDiscovered(
    Peripheral peripheral,
    Service service,
  );

  void onDescriptorsDiscovered(
    Peripheral peripheral,
    Characteristic characteristic,
  );

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
}
