part of '../interface.dart';

/// A service that use is used from a "Central" perspective to scan for
/// and interact with peripherals.
base class CentralManager extends PeerManager<Peripheral> {
  CentralManager({
    super.clientIdentifier,
    @visibleForTesting super.platform,
  });

  ScanController? scanController;

  Stream<ScanResult> scan({
    List<UuidIdentifier>? forServices,
  }) {
    scanController?.dispose();

    scanController ??= ScanController(
      manager: this,
      services: forServices,
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
  Peripheral peripheralFromData(api.PeripheralData data) {
    return data.toPeripheral(manager: this);
  }

  @protected
  ScanResult scanResultFromData(api.ScanData data) {
    return data.toScanResult(manager: this);
  }

  @override
  void dispose() {
    scanController?.dispose();
    super.dispose();
  }
}

final class ScanController {
  ScanController({
    required this.manager,
    this.services,
  });

  final CentralManager manager;

  final List<UuidIdentifier>? services;

  @protected
  StreamSubscription<api.ScanData>? subscription;

  @protected
  late final controller = StreamController<ScanResult>.broadcast(
    onListen: onScanListen,
    onCancel: onScanCancel,
  );

  Stream<ScanResult> get stream {
    /// Subscribe to the api scan stream if we aren't already.
    subscription ??=
        manager.platform.scanStream(manager.clientIdentifier).listen(onScan);

    return controller.stream;
  }

  void onScan(api.ScanData data) {
    controller.sink.add(data.toScanResult(manager: manager));
  }

  Future<void> onScanListen() async {
    await manager.platform.scan(
      forServices: services?.toStrings(),
      clientIdentifier: manager.clientIdentifier,
    );
  }

  Future<void> onScanCancel() async {
    if (controller.hasListener) {
      return;
    }
    await cancelScan();
  }

  Future<void> cancelScan() {
    return manager.platform.cancelScan(
      clientIdentifier: manager.clientIdentifier,
    );
  }

  void dispose() async {
    await cancelScan();
    await subscription?.cancel();
    await controller.close();
  }
}
