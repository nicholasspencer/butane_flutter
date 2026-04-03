part of '../porcelain.dart';

/// Represents an ATT (Attribute Protocol) request from a connected central.
base class AttRequest {
  const AttRequest({
    required this.requestId,
    required this.centralIdentifier,
    required this.characteristicUuid,
    required this.serviceUuid,
    this.offset = 0,
    this.value,
  });

  /// The identifier of this request, used when responding via
  /// [PeripheralManager.respondToRequest].
  final int requestId;

  /// The identifier of the central that sent this request.
  final String centralIdentifier;

  /// The UUID of the characteristic being read or written.
  final UuidIdentifier characteristicUuid;

  /// The UUID of the service containing the characteristic.
  final UuidIdentifier serviceUuid;

  /// The byte offset into the characteristic value.
  final int offset;

  /// The value being written, or `null` for read requests.
  final Uint8List? value;
}

extension ApiAttRequest on api.AttRequest {
  AttRequest toAttRequest() {
    return AttRequest(
      requestId: requestId,
      centralIdentifier: centralIdentifier,
      characteristicUuid: UuidIdentifier(characteristicUuid),
      serviceUuid: UuidIdentifier(serviceUuid),
      offset: offset,
      value: value,
    );
  }
}
