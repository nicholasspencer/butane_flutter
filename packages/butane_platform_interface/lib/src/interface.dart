import 'dart:typed_data';

import 'package:meta/meta.dart';

part 'models/attribute.dart';
part 'models/central.dart';
part 'models/characteristic.dart';
part 'models/descriptor.dart';
part 'models/identifier.dart';
part 'models/mac_address.dart';
part 'models/peer.dart';
part 'models/peripheral.dart';
part 'models/service.dart';
part 'services/central_manager.dart';
part 'services/peer_manager.dart';
part 'services/peripheral_manager.dart';

abstract base class ButanePlatform {
  static late ButanePlatform instance;

  /// The platform-specific implementation of [CentralManager].

  /// Scans for peripherals that are advertising services.
  Stream<Peripheral> scan({
    List<UuidIdentifier>? forServices,
  }) {
    throw UnimplementedError();
  }

  /// Establishes a connection to the peripheral.
  Future<void> connect({
    required Peripheral peripheral,
  }) async {
    throw UnimplementedError();
  }

  /// Cancels an active or pending connection to the peripheral.
  Future<void> cancelConnection({
    required Peripheral peripheral,
  }) async {
    throw UnimplementedError();
  }

  /// A list of connected peripherals identified by an offered service.
  Future<Iterable<Peripheral>> connectedPeripherals({
    List<UuidIdentifier> services = const [],
  }) async {
    throw UnimplementedError();
  }

  /// A list of known peripherals optionally filtered by their identifiers.
  Future<Iterable<Peripheral>> peripherals({
    List<Identifier> identifiers = const [],
  }) async {
    throw UnimplementedError();
  }

  /// Discovers services offered by the peripheral.
  Future<Iterable<Service>> discoverServices({
    required Peripheral peripheral,
    List<UuidIdentifier> serviceUuids = const [],
  }) async {
    throw UnimplementedError();
  }

  /// Discovers characteristics offered by the service.
  Future<Iterable<Characteristic>> discoverCharacteristics({
    required Service service,
    List<UuidIdentifier> characteristicUuids = const [],
  }) async {
    throw UnimplementedError();
  }

  /// The platform-specific implementation of [PeripheralManager].

  /// Advertises the peripheral's services.
  Future<void> startAdvertising({
    required Peripheral peripheral,
  }) async {
    throw UnimplementedError();
  }
}
