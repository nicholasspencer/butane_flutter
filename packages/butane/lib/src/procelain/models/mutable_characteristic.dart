part of '../porcelain.dart';

/// A mutable characteristic for use with [PeripheralManager].
base class MutableCharacteristic {
  const MutableCharacteristic({
    required this.uuid,
    this.properties,
    this.permissions,
    this.value,
    this.descriptors,
  });

  final UuidIdentifier uuid;

  final CharacteristicProperties? properties;

  final CharacteristicPermissions? permissions;

  final Uint8List? value;

  final List<MutableDescriptor>? descriptors;

  /// Converts this porcelain type to the platform interface type.
  api.MutableCharacteristic toApi() {
    return api.MutableCharacteristic(
      uuid: uuid.toString(),
      properties: properties?.toApi(),
      permissions: permissions?.toApi(),
      value: value,
      descriptors: descriptors?.map((d) => d.toApi()).toList(),
    );
  }
}
