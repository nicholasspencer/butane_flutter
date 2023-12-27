part of '../interface.dart';

base class Characteristic extends Attribute {
  const Characteristic({
    required super.uuid,
    required this.service,
  });

  final Service? service;
}
