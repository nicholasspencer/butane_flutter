part of '../porcelain.dart';

/// A service that use is used from a "Peripheral" perspective to advertise
/// and interact with centrals.
base class PeripheralManager extends PeerManager<Central> {
  PeripheralManager({
    super.clientIdentifier,
    super.restorationIdentifier,
    @visibleForTesting super.platform,
  });

  @protected
  PlatformStreamController<AttRequest, api.AttRequest>? readRequestsController;

  @protected
  PlatformStreamController<List<AttRequest>, List<api.AttRequest>>?
      writeRequestsController;

  /// The session used for peripheral manager operations.
  @override
  @protected
  api.PeripheralManagerSession get session => api.PeripheralManagerSession(
        clientIdentifier: clientIdentifier,
        restorationIdentifier: restorationIdentifier,
      );

  /// Starts advertising the local device as a peripheral.
  ///
  /// [localName] is the local name to advertise.
  /// [serviceUuids] is a list of service UUIDs to advertise.
  Future<void> startAdvertising({
    String? localName,
    List<UuidIdentifier>? serviceUuids,
  }) async {
    await platform.startAdvertising(
      session: session,
      localName: localName,
      serviceUuids: serviceUuids?.toStrings(),
    );
  }

  /// Stops advertising the local device.
  Future<void> stopAdvertising() async {
    await platform.stopAdvertising(session: session);
  }

  /// Adds a service to the local GATT database.
  Future<void> addService(MutableService service) async {
    await platform.addService(
      session: session,
      service: service.toApi(),
    );
  }

  /// Removes a service from the local GATT database.
  Future<void> removeService(UuidIdentifier serviceUuid) async {
    await platform.removeService(
      session: session,
      serviceUuid: serviceUuid.toString(),
    );
  }

  /// Removes all services from the local GATT database.
  Future<void> removeAllServices() async {
    await platform.removeAllServices(session: session);
  }

  /// Responds to a read or write request from a connected central.
  Future<void> respondToRequest({
    required int requestId,
    required AttResult result,
    Uint8List? value,
  }) async {
    await platform.respondToRequest(
      session: session,
      requestId: requestId,
      result: result.toApi(),
      value: value,
    );
  }

  /// Updates the value of a characteristic and notifies subscribed centrals.
  ///
  /// Returns `true` if the update was successfully queued for delivery.
  Future<bool> updateValue({
    required UuidIdentifier serviceUuid,
    required UuidIdentifier characteristicUuid,
    required Uint8List value,
  }) async {
    return platform.updateValue(
      session: session,
      serviceUuid: serviceUuid.toString(),
      characteristicUuid: characteristicUuid.toString(),
      value: value,
    );
  }

  /// A stream of read requests from connected centrals.
  Stream<AttRequest> get readRequests {
    readRequestsController?.dispose();

    readRequestsController =
        PlatformStreamController<AttRequest, api.AttRequest>(
      debugLabel: 'PeripheralManager($clientIdentifier).readRequests',
      platform: platform,
      map: (value) => value.toAttRequest(),
      createStream: (platform) {
        return platform.readRequestStream(session);
      },
    );

    return readRequestsController!.stream;
  }

  /// A stream of write requests from connected centrals.
  Stream<List<AttRequest>> get writeRequests {
    writeRequestsController?.dispose();

    writeRequestsController =
        PlatformStreamController<List<AttRequest>, List<api.AttRequest>>(
      debugLabel: 'PeripheralManager($clientIdentifier).writeRequests',
      platform: platform,
      map: (value) => value.map((r) => r.toAttRequest()).toList(),
      createStream: (platform) {
        return platform.writeRequestsStream(session);
      },
    );

    return writeRequestsController!.stream;
  }

  @override
  void dispose() {
    readRequestsController?.dispose();
    writeRequestsController?.dispose();
    super.dispose();
  }
}
