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
    assert(
      peripheral != null,
      'Cannot discover characteristics without a peripheral',
    );

    return peripheral?.manager.platform.discoverCharacteristics(
          peripheralIdentifier: peripheral!.identifier.toString(),
          serviceUuid: uuid.toString(),
          characteristicUuids: characteristicUuids.toStrings(),
        ) ??
        Future.value();
  }

  Future<Iterable<Characteristic>> get characteristics async {
    assert(
      peripheral != null,
      'Cannot get characteristics without a peripheral',
    );
    final characteristics = await peripheral?.manager.platform.characteristics(
          peripheralIdentifier: peripheral!.identifier.toString(),
          serviceUuid: uuid.toString(),
        ) ??
        [];

    return characteristics.map(characteristicFromData);
  }

  @protected
  api.ServiceData toData() {
    return api.ServiceData(
      uuid: uuid.toString(),
      isPrimary: isPrimary,
    );
  }

  @protected
  Characteristic characteristicFromData(api.CharacteristicData data) {
    return data.toCharacteristic(service: this);
  }
}

extension ApiService on api.ServiceData {
  Service toService({
    required Peripheral peripheral,
  }) {
    return Service(
      uuid: UuidIdentifier(uuid),
      peripheral: peripheral,
      isPrimary: isPrimary ?? false,
    );
  }
}
