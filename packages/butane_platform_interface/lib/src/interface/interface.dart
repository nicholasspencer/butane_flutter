import 'dart:typed_data';

abstract base class ButanePlatformInterface {
  static late ButanePlatformInterface instance;

  /// The platform-specific implementation of [CentralManager].

  /// The current state of the client.
  Future<ClientState> clientState([
    Session? session,
  ]);

  /// A stream of client state changes optionally filtered by the client
  /// identifier.
  Stream<ClientState> clientStateStream([
    Session? session,
  ]);

  /// Starts scanning for peripherals that are advertising services.
  ///
  /// See also:
  ///  * [scanStream] for a stream of scan results.
  Future<void> scan({
    Iterable<String>? forServices,
    Session? session,
  });

  /// A stream of scan results optionally filtered by the client identifier.
  ///
  /// You must call [scan] before this stream will emit any events however you
  /// can listen to this stream before calling [scan] to ensure you don't miss
  /// any events.
  ///
  /// See also:
  ///  * [scan] for starting a scan.
  Stream<ScanResult> scanStream([
    Session? session,
  ]);

  /// Stops scanning for peripherals.
  Future<void> cancelScan({
    Session? session,
  });

  /// A list of known peripherals optionally filtered by their identifiers.
  Future<Iterable<Peripheral>> peripherals({
    Iterable<String> peripheralIdentifiers = const [],
    Session? session,
  });

  /// A list of connected peripherals identified by an offered service.
  Future<Iterable<Peripheral>> connectedPeripherals({
    Iterable<String> serviceUuids = const [],
    Session? session,
  });

  /// Establishes a connection to the peripheral.
  ///
  /// The connection is not guaranteed to be successful. The peripheral may
  /// reject the connection request or the connection may fail for other
  /// reasons.
  ///
  /// The connection attempt is cancelled if the peripheral disconnects.
  ///
  /// Use [Peripheral.]
  Future<void> connect({
    required PeripheralSession session,
  });

  /// Cancels an active or pending connection to the peripheral.
  Future<void> cancelConnection({
    required PeripheralSession session,
  });

  /// The current connection state of the peripheral.
  Future<ConnectionState> connectionState({
    required PeripheralSession session,
  });

  /// A stream of connection state changes for the peripheral.
  Stream<ConnectionState> connectionStateStream({
    required PeripheralSession session,
  });

  /// Discovers services offered by the peripheral.
  Future<void> discoverServices({
    required PeripheralSession session,
    Iterable<String> serviceUuids = const [],
  });

  /// A list of discovered services offered by the peripheral.
  Future<Iterable<Service>> services({
    required PeripheralSession session,
  });

  /// Discovers characteristics offered by the service.
  Future<void> discoverCharacteristics({
    required PeripheralSession session,
    required String serviceUuid,
    Iterable<String> characteristicUuids = const [],
  });

  /// A list of discovered characteristics offered by the service.
  Future<Iterable<Characteristic>> characteristics({
    required PeripheralSession session,
    required String serviceUuid,
  });

  /// Reads the value of the characteristic.
  Future<Uint8List> readCharacteristic({
    required PeripheralSession session,
    required String serviceUuid,
    required String characteristicUuid,
  });

  /// Writes the value of the characteristic.
  Future<void> writeCharacteristic({
    required PeripheralSession session,
    required String serviceUuid,
    required String characteristicUuid,
    required Uint8List value,
    bool withoutResponse = false,
  });

  /// Streams characteristic value updates.
  Stream<Uint8List> watchCharacteristic({
    required PeripheralSession session,
    required String serviceUuid,
    required String characteristicUuid,
  });

  /// Requests a read of the RSSI for the peripheral.
  Future<int> readRssi({
    required PeripheralSession session,
  });

  /// TODO The platform-specific implementation of [PeripheralManager].
}

/// Models

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

final class Session {
  const Session({
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

final class PeripheralSession extends Session {
  const PeripheralSession({
    super.peripheralIdentifier,
    super.clientIdentifier,
    super.adapterIdentifier,
    super.restorationIdentifier,
  });

  @override
  String get peripheralIdentifier => super.peripheralIdentifier!;
}

final class Peripheral {
  const Peripheral({
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

final class AdvertisementData {
  const AdvertisementData({
    this.localName,
    this.manufacturerData,
    this.serviceUuids,
    this.serviceData,
    this.txPowerLevel,
    this.isConnectable,
  });

  final String? localName;

  final Uint8List? manufacturerData;

  final List<String>? serviceUuids;

  final Map<String, Uint8List>? serviceData;

  final int? txPowerLevel;

  final bool? isConnectable;
}

final class ScanResult {
  const ScanResult({
    required this.peripheral,
    required this.advertisementData,
  });

  final Peripheral peripheral;

  final AdvertisementData advertisementData;
}

final class Service {
  const Service({
    required this.uuid,
    this.isPrimary = false,
  });

  final String uuid;

  final bool isPrimary;
}

final class Characteristic {
  const Characteristic({
    required this.uuid,
    this.value,
    this.descriptors,
    this.properties,
  });

  final String uuid;

  final Uint8List? value;

  final List<Descriptor>? descriptors;

  final CharacteristicProperty? properties;
}

final class Descriptor {
  const Descriptor({
    required this.uuid,
    this.value,
  });

  final String uuid;

  final Uint8List? value;
}

final class CharacteristicProperty {
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
