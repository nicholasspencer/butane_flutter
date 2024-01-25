part of '../porcelain.dart';

abstract base class Attribute {
  const Attribute({required this.uuid});

  final UuidIdentifier uuid;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Attribute &&
          runtimeType == other.runtimeType &&
          uuid == other.uuid;

  @override
  int get hashCode => uuid.hashCode;
}
