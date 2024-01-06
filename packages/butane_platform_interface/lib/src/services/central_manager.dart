part of '../interface.dart';

/// A service that use is used from a "Central" perspective to scan for
/// and interact with peripherals.
base class CentralManager extends PeerManager<Peripheral> {
  CentralManager({
    super.clientIdentifier,
    @visibleForTesting super.peers,
    @visibleForTesting super.platform,
  });

  Stream<ScanResult> scan({
    List<UuidIdentifier>? forServices,
  }) {
    return platform
        .scan(forServices: forServices?.toStrings())
        .map(scanResultFromData);
  }

  Future<Iterable<Peripheral>> connectedPeripherals({
    List<UuidIdentifier> services = const [],
  }) async {
    final connectedPeripherals = await platform.connectedPeripherals(
      serviceUuids: services.toStrings(),
    );

    return connectedPeripherals.map(peripheralFromData);
  }

  Future<Iterable<Peripheral>> peripherals({
    List<Identifier> identifiers = const [],
  }) async {
    final peripherals = await platform.peripherals(
      peripheralIdentifiers: identifiers.toStrings(),
    );
    return peripherals.map(peripheralFromData);
  }

  @protected
  Peripheral peripheralFromData(api.PeripheralData data) {
    return data.toPeripheral(manager: this);
  }

  @protected
  ScanResult scanResultFromData(api.ScanData data) {
    return data.toScanResult(manager: this);
  }
}
