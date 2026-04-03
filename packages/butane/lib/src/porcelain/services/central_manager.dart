part of '../porcelain.dart';

/// A service that use is used from a "Central" perspective to scan for
/// and interact with peripherals.
base class CentralManager extends PeerManager<Peripheral> {
  CentralManager({
    super.clientIdentifier,
    super.restorationIdentifier,
    @visibleForTesting super.platform,
  });

  @protected
  PlatformStreamController<ScanResult, api.ScanResult>? scanController;

  Stream<ScanResult> scan({
    List<UuidIdentifier>? forServices,
  }) {
    scanController?.dispose();

    scanController = PlatformStreamController<ScanResult, api.ScanResult>(
      debugLabel:
          'CentralManager($clientIdentifier, ${forServices?.map((e) => e.toString())}).scan',
      platform: platform,
      map: (value) => value.toScanResult(manager: this),
      createStream: (platform) {
        return platform.scanStream(session);
      },
      onListen: (platform) async {
        await platform.scan(
          session: session,
          forServices: forServices?.toStrings(),
        );
      },
      onCancel: (platform) async {
        await platform.cancelScan(
          session: session,
        );
      },
    );

    return scanController!.stream;
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
  Peripheral peripheralFromData(api.Peripheral data) {
    return data.toPeripheral(manager: this);
  }

  @protected
  ScanResult scanResultFromData(api.ScanResult data) {
    return data.toScanResult(manager: this);
  }

  @override
  void dispose() {
    scanController?.dispose();
    super.dispose();
  }
}
