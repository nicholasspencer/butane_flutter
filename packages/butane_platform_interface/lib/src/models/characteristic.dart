part of '../interface.dart';

base class Characteristic extends Attribute {
  const Characteristic({
    required super.uuid,
    required this.service,
  });

  final Service? service;

  /// Reads the value of the characteristic.
  Future<Uint8List> read() async {
    final data = await service?.peripheral?.manager.platform.readCharacteristic(
      peripheralIdentifier: service!.peripheral!.identifier.toString(),
      serviceUuid: service!.uuid.toString(),
      characteristicUuid: uuid.toString(),
    );

    return data ?? Uint8List(0);
  }

  /// Writes the value of the characteristic.
  Future<void> write({
    required Uint8List value,
    bool withoutResponse = false,
  }) async {
    return service?.peripheral?.manager.platform.writeCharacteristic(
      peripheralIdentifier: service!.peripheral!.identifier.toString(),
      serviceUuid: service!.uuid.toString(),
      characteristicUuid: uuid.toString(),
      value: value,
      withoutResponse: withoutResponse,
    );
  }

  /// Streams characteristic value updates.
  Stream<Uint8List> watch({
    required bool enabled,
  }) {
    return service?.peripheral?.manager.platform.watchCharacteristic(
          peripheralIdentifier: service!.peripheral!.identifier.toString(),
          serviceUuid: service!.uuid.toString(),
          characteristicUuid: uuid.toString(),
        ) ??
        const Stream.empty();
  }

  @protected
  api.CharacteristicData toData() {
    return api.CharacteristicData(
      uuid: uuid.toString(),
    );
  }
}

extension ApiCharacteristic on api.CharacteristicData {
  Characteristic toCharacteristic({
    required Service service,
  }) {
    return Characteristic(
      uuid: UuidIdentifier(uuid),
      service: service,
    );
  }
}
