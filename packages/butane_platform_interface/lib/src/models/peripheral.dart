part of '../interface.dart';

base class Peripheral extends Peer {
  const Peripheral({
    required PeerManager<Peripheral> super.manager,
    required this.name,
    required super.identifier,
  });

  final String name;

  @override
  PeerManager<Peripheral> get manager =>
      super.manager as PeerManager<Peripheral>;

  Future<void> connect() async {
    return manager.platform.connect(
      peripheral: this,
    );
  }

  Future<void> cancelConnection({
    required Peripheral peripheral,
  }) async {
    return manager.platform.cancelConnection(
      peripheral: this,
    );
  }

  Future<Iterable<Service>> discoverServices({
    List<UuidIdentifier> serviceUuids = const [],
  }) {
    return manager.platform.discoverServices(
      peripheral: this,
      serviceUuids: serviceUuids,
    );
  }

  Future<Iterable<Service>> get discoveredServices {
    return manager.platform.discoverServices(
      peripheral: this,
    );
  }
}
