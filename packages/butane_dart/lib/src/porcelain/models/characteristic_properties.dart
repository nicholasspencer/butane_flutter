part of '../porcelain.dart';

/// Properties of a characteristic, describing what operations are supported.
base class CharacteristicProperties {
  const CharacteristicProperties({
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

  /// Creates characteristic properties from the platform interface type.
  factory CharacteristicProperties.fromApi(
    api.CharacteristicProperty property,
  ) {
    return CharacteristicProperties(
      broadcast: property.broadcast,
      read: property.read,
      writeWithoutResponse: property.writeWithoutResponse,
      write: property.write,
      notify: property.notify,
      indicate: property.indicate,
      authenticatedSignedWrites: property.authenticatedSignedWrites,
      extendedProperties: property.extendedProperties,
      notifyEncryptionRequired: property.notifyEncryptionRequired,
      indicateEncryptionRequired: property.indicateEncryptionRequired,
    );
  }

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

  /// Converts this porcelain type to the platform interface type.
  api.CharacteristicProperty toApi() {
    return api.CharacteristicProperty(
      broadcast: broadcast,
      read: read,
      writeWithoutResponse: writeWithoutResponse,
      write: write,
      notify: notify,
      indicate: indicate,
      authenticatedSignedWrites: authenticatedSignedWrites,
      extendedProperties: extendedProperties,
      notifyEncryptionRequired: notifyEncryptionRequired,
      indicateEncryptionRequired: indicateEncryptionRequired,
    );
  }
}
