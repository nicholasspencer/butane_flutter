part of '../interface.dart';

base class Peripheral extends Peer {
  const Peripheral({
    required PeerManager<Peripheral> super.manager,
    required this.name,
    required super.identifier,
    this.initialRssi,
  });

  final String? name;

  final double? initialRssi;

  @override
  PeerManager<Peripheral> get manager =>
      super.manager as PeerManager<Peripheral>;

  Future<void> connect() async {
    return manager.platform.connect(
      peripheralIdentifier: identifier.toString(),
    );
  }

  Future<void> cancelConnection() async {
    return manager.platform.cancelConnection(
      peripheralIdentifier: identifier.toString(),
    );
  }

  Future<void> discoverServices({
    List<UuidIdentifier> serviceUuids = const [],
  }) {
    return manager.platform.discoverServices(
      peripheralIdentifier: identifier.toString(),
      serviceUuids: serviceUuids.toStrings(),
    );
  }

  Future<Iterable<Service>> get services async {
    final services = await manager.platform.services(
      peripheralIdentifier: identifier.toString(),
    );

    return services.map(serviceFromData);
  }

  @protected
  api.PeripheralData toData() {
    return api.PeripheralData(
      identifier: identifier.toString(),
      name: name,
      rssi: initialRssi,
    );
  }

  @protected
  Service serviceFromData(api.ServiceData data) {
    return data.toService(peripheral: this);
  }
}

base class AdvertisementData {
  const AdvertisementData({
    this.localName,
    this.txPowerLevel,
    this.manufacturerData,
    this.serviceData,
    this.serviceUuids,
  });

  final String? localName;

  final int? txPowerLevel;

  final Uint8List? manufacturerData;

  final Map<String, Uint8List>? serviceData;

  final List<String>? serviceUuids;

  @protected
  api.AdvertisementData toData() {
    return api.AdvertisementData(
      localName: localName,
      txPowerLevel: txPowerLevel,
      manufacturerData: manufacturerData,
      serviceData: serviceData,
      serviceUuids: serviceUuids,
    );
  }
}

base class ScanResult {
  const ScanResult({
    required this.peripheral,
    required this.advertisementData,
  });

  final Peripheral peripheral;

  final AdvertisementData advertisementData;
}

extension ApiPeripheralData on api.PeripheralData {
  Peripheral toPeripheral({required PeerManager<Peripheral> manager}) {
    return Peripheral(
      identifier: Identifier.parse(identifier),
      name: name,
      initialRssi: rssi,
      manager: manager,
    );
  }
}

extension ApiAdvertisementData on api.AdvertisementData {
  AdvertisementData toAdvertisementData() {
    return AdvertisementData(
      manufacturerData: manufacturerData,
      serviceData: serviceData as Map<String, Uint8List>?,
      serviceUuids: serviceUuids?.nonNulls.toList(),
      txPowerLevel: txPowerLevel,
      localName: localName,
    );
  }
}

extension ApiScanData on api.ScanData {
  ScanResult toScanResult({required PeerManager<Peripheral> manager}) {
    return ScanResult(
      peripheral: peripheral.toPeripheral(manager: manager),
      advertisementData: advertisementData.toAdvertisementData(),
    );
  }
}
