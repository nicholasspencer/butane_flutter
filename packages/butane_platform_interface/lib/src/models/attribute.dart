part of '../interface.dart';

abstract base class Attribute {
  const Attribute({required this.uuid});

  final UuidIdentifier uuid;
}
