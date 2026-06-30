part of '../porcelain.dart';

/// A mutable descriptor for use with [PeripheralManager].
base class MutableDescriptor {
  const MutableDescriptor({
    required this.uuid,
    this.value,
  });

  final UuidIdentifier uuid;

  final Uint8List? value;

  /// Converts this porcelain type to the platform interface type.
  api.MutableDescriptor toApi() {
    return api.MutableDescriptor(
      uuid: uuid.toString(),
      value: value,
    );
  }
}
