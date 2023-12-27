import 'package:pigeon/pigeon.dart';

class PeripheralData {
  PeripheralData({
    this.identifier,
    this.name,
  });

  final String? identifier;

  final String? name;
}

class AttributeData {
  AttributeData({
    required this.uuid,
  });

  final String uuid;
}

class ServiceData extends AttributeData {
  ServiceData({
    required super.uuid,
    this.isPrimary,
  });

  final bool? isPrimary;
}

class CharacteristicData extends AttributeData {
  CharacteristicData({
    required super.uuid,
    this.value,
    this.descriptors,
    this.properties,
  });

  /// List of bytes
  final List<int?>? value;

  final List<DescriptorData?>? descriptors;

  final CharacteristicProperty? properties;
}

class DescriptorData extends AttributeData {
  DescriptorData({
    required super.uuid,
    this.value,
  });

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

@HostApi()
abstract class ButaneApi {
  /// "Central" APIs.

  /// Scans for peripherals that are advertising services.
  @async
  void scan({
    List<String> forServices = const [],
  });

  /// A list of known peripherals optionally filtered by their identifiers.
  @async
  List<PeripheralData> peripherals({
    List<String> identifiers = const [],
  });

  /// Establishes a connection to the peripheral.
  @async
  void connect({
    required PeripheralData peripheral,
  });

  /// Cancels an active or pending connection to the peripheral.
  @async
  void cancelConnection({
    required PeripheralData peripheral,
  });

  /// A list of connected peripherals identified by an offered service.
  @async
  List<PeripheralData> connectedPeripherals({
    List<String> services = const [],
  });

  /// Discovers services offered by the peripheral.
  @async
  List<ServiceData> discoverServices({
    required PeripheralData peripheral,
    List<String> serviceUuids = const [],
  });

  /// Discovers characteristics offered by the service.
  @async
  List<CharacteristicData> discoverCharacteristics({
    required ServiceData service,
    List<String> characteristicUuids = const [],
  });

  /// Reads the value of the characteristic.
  @async
  List<int> readCharacteristic({
    required CharacteristicData characteristic,
  });

  /// Writes the value of the characteristic.
  @async
  void writeCharacteristic({
    required CharacteristicData characteristic,
    required List<int> value,
    bool withoutResponse = false,
  });

  /// Enables notifications or indications for the characteristic.
  @async
  void setNotification({
    required CharacteristicData characteristic,
    required bool enabled,
  });

  /// Reads the value of the descriptor.
  @async
  List<int> readDescriptor({
    required DescriptorData descriptor,
  });

  /// Writes the value of the descriptor.
  @async
  void writeDescriptor({
    required DescriptorData descriptor,
    required List<int> value,
  });

  /// Requests a read of the RSSI for the peripheral.
  @async
  int readRssi({
    required PeripheralData peripheral,
  });

  /// Requests a MTU size change.
  @async
  int requestMtu({
    required PeripheralData peripheral,
    required int mtu,
  });

  /// "Peripheral" APIs.
}
