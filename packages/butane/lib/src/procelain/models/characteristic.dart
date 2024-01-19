part of '../porcelain.dart';

base class Characteristic extends Attribute {
  const Characteristic({
    required super.uuid,
    required this.service,
  });

  final Service? service;

  /// Reads the value of the characteristic.
  Future<Uint8List> read() async {
    final data = await service?.peripheral?.manager.platform.readCharacteristic(
      session: service!.peripheral!.session,
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
      session: service!.peripheral!.session,
      serviceUuid: service!.uuid.toString(),
      characteristicUuid: uuid.toString(),
      value: value,
      withoutResponse: withoutResponse,
    );
  }

  /// Streams characteristic value updates.
  Stream<Uint8List?> watch() {
    return service?.peripheral?.manager.platform.watchCharacteristic(
          session: service!.peripheral!.session,
          serviceUuid: service!.uuid.toString(),
          characteristicUuid: uuid.toString(),
        ) ??
        const Stream.empty();
  }

  @protected
  api.Characteristic toData() {
    return api.Characteristic(
      uuid: uuid.toString(),
    );
  }
}

extension ApiCharacteristic on api.Characteristic {
  Characteristic toCharacteristic({
    required Service service,
  }) {
    return Characteristic(
      uuid: UuidIdentifier(uuid),
      service: service,
    );
  }
}
