part of '../porcelain.dart';

base class Descriptor extends Attribute {
  const Descriptor({
    required super.uuid,
    this.characteristic,
  });

  final Characteristic? characteristic;

  /// Reads the value of the descriptor.
  Future<Uint8List> read() {
    final characteristic = this.characteristic;
    final service = characteristic?.service;
    final peripheral = service?.peripheral;
    if (characteristic == null || service == null || peripheral == null) {
      throw StateError(
        'Cannot access descriptor $uuid without a characteristic, service, and peripheral',
      );
    }

    return peripheral.manager.platform.readDescriptor(
      session: peripheral.session,
      serviceUuid: service.uuid.toString(),
      characteristicUuid: characteristic.uuid.toString(),
      descriptorUuid: uuid.toString(),
    );
  }

  /// Writes [value] to the descriptor.
  Future<void> write({required Uint8List value}) {
    final characteristic = this.characteristic;
    final service = characteristic?.service;
    final peripheral = service?.peripheral;
    if (characteristic == null || service == null || peripheral == null) {
      throw StateError(
        'Cannot access descriptor $uuid without a characteristic, service, and peripheral',
      );
    }

    return peripheral.manager.platform.writeDescriptor(
      session: peripheral.session,
      serviceUuid: service.uuid.toString(),
      characteristicUuid: characteristic.uuid.toString(),
      descriptorUuid: uuid.toString(),
      value: value,
    );
  }
}
