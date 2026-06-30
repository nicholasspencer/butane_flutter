part of '../porcelain.dart';

base class Service extends Attribute {
  const Service({
    required super.uuid,
    required this.peripheral,
    this.isPrimary = false,
  });

  final Peripheral? peripheral;

  final bool isPrimary;

  Future<void> discoverCharacteristics({
    List<UuidIdentifier>? characteristicUuids,
  }) async {
    assert(
      peripheral != null,
      'Cannot discover characteristics without a peripheral',
    );

    await peripheral?.manager.platform.discoverCharacteristics(
      session: peripheral!.session,
      serviceUuid: uuid.toString(),
      characteristicUuids: characteristicUuids?.toStrings(),
    );
  }

  Future<Iterable<Characteristic>> get characteristics async {
    assert(
      peripheral != null,
      'Cannot get characteristics without a peripheral',
    );

    final characteristics = await peripheral?.manager.platform.characteristics(
      session: peripheral!.session,
      serviceUuid: uuid.toString(),
    );

    return characteristics?.map(characteristicFromData) ?? [];
  }

  @protected
  api.Service toData() {
    return api.Service(
      uuid: uuid.toString(),
      isPrimary: isPrimary,
    );
  }

  @protected
  Characteristic characteristicFromData(api.Characteristic data) {
    return data.toCharacteristic(service: this);
  }
}

extension ApiService on api.Service {
  Service toService({
    required Peripheral peripheral,
  }) {
    return Service(
      uuid: UuidIdentifier(uuid),
      peripheral: peripheral,
      isPrimary: isPrimary,
    );
  }
}
