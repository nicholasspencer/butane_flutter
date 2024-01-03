part of '../interface.dart';

/// A default implementation of [ButanePlatformInterface] which uses generated
/// method channels to call platform-specific code.
base class ButanePlatform extends ButanePlatformInterface {
  static void registerWith() {
    ButanePlatformInterface.instance = ButanePlatform();
  }

  late final api.ButaneHostApi hostApi = api.ButaneHostApi();

  late final ButaneFlutterApi flutterApi = ButaneFlutterApi();

  @override
  Stream<api.ManagerState> get managerStateStream =>
      flutterApi.managerStateStream;

  @override
  Stream<api.ScanData> scan({Iterable<String>? forServices}) {
    // TODO:
    // We need to handle the future here in case of an error
    // This should also return a handle to the stream so that it can be cancelled
    // and scan should be able to be called multiple times.

    final requestIdentifier = const Uuid().v4();

    hostApi.scan(
      requestIdentifier: requestIdentifier,
      forServices: forServices?.toList(),
    );

    return flutterApi.scanStream.map((result) {
      return result.scanData;
    });
  }

  @override
  Future<void> connect({required String peripheralIdentifier}) async {
    return hostApi.connect(
      peripheralIdentifier: peripheralIdentifier,
    );
  }

  @override
  Future<void> cancelConnection({required String peripheralIdentifier}) async {
    return hostApi.cancelConnection(
      peripheralIdentifier: peripheralIdentifier,
    );
  }

  @override
  Future<Iterable<api.PeripheralData>> connectedPeripherals({
    Iterable<String> serviceUuids = const [],
  }) async {
    final peripherals = await hostApi.connectedPeripherals(
      serviceUuids: serviceUuids.toList(),
    );

    return peripherals.nonNulls;
  }

  @override
  Future<Iterable<api.PeripheralData>> peripherals({
    Iterable<String> peripheralIdentifiers = const [],
  }) async {
    final peripherals = await hostApi.peripherals(
      peripheralIdentifiers: peripheralIdentifiers.toList(),
    );

    return peripherals.nonNulls;
  }

  @override
  Future<void> discoverServices({
    required String peripheralIdentifier,
    Iterable<String> serviceUuids = const [],
  }) async {
    await hostApi.discoverServices(
      peripheralIdentifier: peripheralIdentifier,
    );
  }

  @override
  Future<Iterable<api.ServiceData>> services({
    required String peripheralIdentifier,
  }) async {
    final services = await hostApi.services(
      peripheralIdentifier: peripheralIdentifier,
    );

    return services.nonNulls;
  }

  @override
  Future<void> discoverCharacteristics({
    required String peripheralIdentifier,
    required String serviceUuid,
    Iterable<String> characteristicUuids = const [],
  }) async {
    await hostApi.discoverCharacteristics(
      peripheralIdentifier: peripheralIdentifier,
      serviceUuid: serviceUuid,
      characteristicUuids: characteristicUuids.toList(),
    );
  }

  @override
  Future<Iterable<api.CharacteristicData>> characteristics({
    required String peripheralIdentifier,
    required String serviceUuid,
  }) async {
    final characteristics = await hostApi.characteristics(
      peripheralIdentifier: peripheralIdentifier,
      serviceUuid: serviceUuid,
    );

    return characteristics.nonNulls;
  }

  @override
  Future<Uint8List> readCharacteristic({
    required String peripheralIdentifier,
    required String serviceUuid,
    required String characteristicUuid,
  }) async {
    return hostApi.readCharacteristic(
      peripheralIdentifier: peripheralIdentifier,
      serviceUuid: serviceUuid,
      characteristicUuid: characteristicUuid,
    );
  }

  @override
  Future<void> startAdvertising({
    required api.PeripheralData peripheral,
  }) async {
    ///
  }

  @override
  Future<void> writeCharacteristic({
    required String peripheralIdentifier,
    required String serviceUuid,
    required String characteristicUuid,
    required Uint8List value,
    bool withoutResponse = false,
  }) {
    return hostApi.writeCharacteristic(
      peripheralIdentifier: peripheralIdentifier,
      serviceUuid: serviceUuid,
      characteristicUuid: characteristicUuid,
      value: value,
      withoutResponse: withoutResponse,
    );
  }

  @override
  Stream<Uint8List> watchCharacteristic({
    required String peripheralIdentifier,
    required String serviceUuid,
    required String characteristicUuid,
  }) {
    // TODO:
    // We need to handle the future here in case of an error
    // This should also return a handle to the stream so the characteristic can
    // be unwatched and watch should be able to be called multiple times.
    hostApi.watchCharacteristic(
      peripheralIdentifier: peripheralIdentifier,
      serviceUuid: serviceUuid,
      characteristicUuid: characteristicUuid,
    );

    return flutterApi.characteristicValueStream
        .forCharacteristic(
          characteristicUuid: characteristicUuid,
          peripheralIdentifier: peripheralIdentifier,
        )
        .map((result) => result.value);
  }
}

abstract base class ButanePlatformInterface {
  static late ButanePlatformInterface instance;

  Stream<api.ManagerState> get managerStateStream;

  /// The platform-specific implementation of [CentralManager].

  /// Scans for peripherals that are advertising services.
  Stream<api.ScanData> scan({
    Iterable<String>? forServices,
  });

  /// Establishes a connection to the peripheral.
  ///
  /// The connection is not guaranteed to be successful. The peripheral may
  /// reject the connection request or the connection may fail for other
  /// reasons.
  ///
  /// The connection attempt is cancelled if the peripheral disconnects.
  ///
  /// Use [Peripheral.]
  Future<void> connect({
    required String peripheralIdentifier,
  });

  /// Cancels an active or pending connection to the peripheral.
  Future<void> cancelConnection({
    required String peripheralIdentifier,
  });

  /// A list of connected peripherals identified by an offered service.
  Future<Iterable<api.PeripheralData>> connectedPeripherals({
    Iterable<String> serviceUuids = const [],
  });

  /// A list of known peripherals optionally filtered by their identifiers.
  Future<Iterable<api.PeripheralData>> peripherals({
    Iterable<String> peripheralIdentifiers = const [],
  });

  /// Discovers services offered by the peripheral.
  Future<void> discoverServices({
    required String peripheralIdentifier,
    Iterable<String> serviceUuids = const [],
  });

  /// A list of discovered services offered by the peripheral.
  Future<Iterable<api.ServiceData>> services({
    required String peripheralIdentifier,
  });

  /// Discovers characteristics offered by the service.
  Future<void> discoverCharacteristics({
    required String peripheralIdentifier,
    required String serviceUuid,
    Iterable<String> characteristicUuids = const [],
  });

  /// A list of discovered characteristics offered by the service.
  Future<Iterable<api.CharacteristicData>> characteristics({
    required String peripheralIdentifier,
    required String serviceUuid,
  });

  /// Reads the value of the characteristic.
  Future<Uint8List> readCharacteristic({
    required String peripheralIdentifier,
    required String serviceUuid,
    required String characteristicUuid,
  });

  /// Writes the value of the characteristic.
  Future<void> writeCharacteristic({
    required String peripheralIdentifier,
    required String serviceUuid,
    required String characteristicUuid,
    required Uint8List value,
    bool withoutResponse = false,
  });

  /// Streams characteristic value updates.
  Stream<Uint8List> watchCharacteristic({
    required String peripheralIdentifier,
    required String serviceUuid,
    required String characteristicUuid,
  });

  /// The platform-specific implementation of [PeripheralManager].

  /// Advertises the peripheral's services.
  Future<void> startAdvertising({
    required api.PeripheralData peripheral,
  });
}
