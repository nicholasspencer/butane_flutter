part of '../interface.dart';

base class Service extends Attribute {
  const Service({
    required super.uuid,
    required this.peripheral,
    this.isPrimary = false,
  });

  final Peripheral? peripheral;

  final bool isPrimary;

  Future<void> discoverCharacteristics({
    List<UuidIdentifier> characteristicUuids = const [],
  }) async {
    return peripheral?.manager.platform.discoverCharacteristics(
          service: this,
          characteristicUuids: characteristicUuids,
        ) ??
        Future.value();
  }

  Future<Iterable<Characteristic>> get characteristics {
    return peripheral?.manager.platform.discoverCharacteristics(
          service: this,
        ) ??
        Future.value([]);
  }
}
