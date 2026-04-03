part of '../porcelain.dart';

/// Permissions for a mutable characteristic used with [PeripheralManager].
base class CharacteristicPermissions {
  const CharacteristicPermissions({
    this.readable = false,
    this.writeable = false,
    this.readEncryptionRequired = false,
    this.writeEncryptionRequired = false,
  });

  final bool readable;

  final bool writeable;

  final bool readEncryptionRequired;

  final bool writeEncryptionRequired;

  /// Converts this porcelain type to the platform interface type.
  api.CharacteristicPermission toApi() {
    return api.CharacteristicPermission(
      readable: readable,
      writeable: writeable,
      readEncryptionRequired: readEncryptionRequired,
      writeEncryptionRequired: writeEncryptionRequired,
    );
  }
}
