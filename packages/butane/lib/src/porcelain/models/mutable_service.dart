part of '../porcelain.dart';

/// A mutable service for use with [PeripheralManager].
base class MutableService {
  const MutableService({
    required this.uuid,
    this.isPrimary = true,
    required this.characteristics,
  });

  final UuidIdentifier uuid;

  final bool isPrimary;

  final List<MutableCharacteristic> characteristics;

  /// Converts this porcelain type to the platform interface type.
  api.MutableService toApi() {
    return api.MutableService(
      uuid: uuid.toString(),
      isPrimary: isPrimary,
      characteristics: characteristics.map((c) => c.toApi()).toList(),
    );
  }
}
