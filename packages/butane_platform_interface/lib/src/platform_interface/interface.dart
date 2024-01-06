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
  Future<api.ClientState> clientState([String? clientIdentifier]) async {
    return hostApi.state(clientIdentifier: clientIdentifier);
  }

  @override
  Stream<api.ClientState> clientStateStream([String? clientIdentifier]) =>
      flutterApi.clientStateStream
          .where((event) => event.clientIdentifier == clientIdentifier)
          .map((event) => event.state);

  @override
  Stream<api.ScanData> scan({
    Iterable<String>? forServices,
    String? clientIdentifier,
  }) {
    // TODO:
    // We need to handle the future here in case of an error
    // This should also return a handle to the stream so that it can be cancelled
    // and scan should be able to be called multiple times.

    hostApi.scan(
      clientIdentifier: null,
      forServices: forServices?.toList(),
    );

    return flutterApi.scanStream.where(
      (event) =>
          event.peripheral.identifier.clientIdentifier == clientIdentifier,
    );
  }

  @override
  Future<Iterable<api.PeripheralData>> peripherals({
    Iterable<String> peripheralIdentifiers = const [],
    String? clientIdentifier,
  }) async {
    final peripherals = await hostApi.peripherals(
      peripheralIdentifiers: peripheralIdentifiers.toList(),
    );

    return peripherals.nonNulls;
  }

  @override
  Future<Iterable<api.PeripheralData>> connectedPeripherals({
    Iterable<String> serviceUuids = const [],
    String? clientIdentifier,
  }) async {
    final peripherals = await hostApi.connectedPeripherals(
      serviceUuids: serviceUuids.toList(),
    );

    return peripherals.nonNulls;
  }

  @override
  Future<void> connect({
    required api.PeripheralSessionIdentifier sessionIdentifier,
  }) async {
    return hostApi.connect(
      sessionIdentifier: sessionIdentifier,
    );
  }

  @override
  Future<void> cancelConnection({
    required api.PeripheralSessionIdentifier sessionIdentifier,
  }) async {
    return hostApi.cancelConnection(
      sessionIdentifier: sessionIdentifier,
    );
  }

  @override
  Future<void> discoverServices({
    required api.PeripheralSessionIdentifier sessionIdentifier,
    Iterable<String> serviceUuids = const [],
  }) async {
    await hostApi.discoverServices(
      sessionIdentifier: sessionIdentifier,
    );
  }

  @override
  Future<Iterable<api.ServiceData>> services({
    required api.PeripheralSessionIdentifier sessionIdentifier,
  }) async {
    final services = await hostApi.services(
      sessionIdentifier: sessionIdentifier,
    );

    return services.nonNulls;
  }

  @override
  Future<void> discoverCharacteristics({
    required api.PeripheralSessionIdentifier sessionIdentifier,
    required String serviceUuid,
    Iterable<String> characteristicUuids = const [],
  }) async {
    await hostApi.discoverCharacteristics(
      sessionIdentifier: sessionIdentifier,
      serviceUuid: serviceUuid,
      characteristicUuids: characteristicUuids.toList(),
    );
  }

  @override
  Future<Iterable<api.CharacteristicData>> characteristics({
    required api.PeripheralSessionIdentifier sessionIdentifier,
    required String serviceUuid,
  }) async {
    final characteristics = await hostApi.characteristics(
      sessionIdentifier: sessionIdentifier,
      serviceUuid: serviceUuid,
    );

    return characteristics.nonNulls;
  }

  @override
  Future<Uint8List> readCharacteristic({
    required api.PeripheralSessionIdentifier sessionIdentifier,
    required String serviceUuid,
    required String characteristicUuid,
  }) async {
    return hostApi.readCharacteristic(
      sessionIdentifier: sessionIdentifier,
      serviceUuid: serviceUuid,
      characteristicUuid: characteristicUuid,
    );
  }

  @override
  Future<void> writeCharacteristic({
    required api.PeripheralSessionIdentifier sessionIdentifier,
    required String serviceUuid,
    required String characteristicUuid,
    required Uint8List value,
    bool withoutResponse = false,
  }) {
    return hostApi.writeCharacteristic(
      sessionIdentifier: sessionIdentifier,
      serviceUuid: serviceUuid,
      characteristicUuid: characteristicUuid,
      value: value,
      withoutResponse: withoutResponse,
    );
  }

  @override
  Stream<Uint8List> watchCharacteristic({
    required api.PeripheralSessionIdentifier sessionIdentifier,
    required String serviceUuid,
    required String characteristicUuid,
  }) {
    // TODO:
    // We need to handle the future here in case of an error
    // This should also return a handle to the stream so the characteristic can
    // be unwatched and watch should be able to be called multiple times.
    hostApi.watchCharacteristic(
      sessionIdentifier: sessionIdentifier,
      serviceUuid: serviceUuid,
      characteristicUuid: characteristicUuid,
    );

    return flutterApi.characteristicValueStream
        .forCharacteristic(
          characteristicUuid: characteristicUuid,
          peripheralIdentifier: sessionIdentifier.identifier,
        )
        .map((result) => result.value);
  }

  @override
  Future<void> startAdvertising({
    required api.PeripheralData peripheral,
  }) async {
    ///
  }
}

abstract base class ButanePlatformInterface {
  static late ButanePlatformInterface instance;

  Future<api.ClientState> clientState([String? clientIdentifier]);

  Stream<api.ClientState> clientStateStream([String? clientIdentifier]);

  /// The platform-specific implementation of [CentralManager].

  /// Scans for peripherals that are advertising services.
  Stream<api.ScanData> scan({
    Iterable<String>? forServices,
    String? clientIdentifier,
  });

  /// A list of known peripherals optionally filtered by their identifiers.
  Future<Iterable<api.PeripheralData>> peripherals({
    Iterable<String> peripheralIdentifiers = const [],
    String? clientIdentifier,
  });

  /// A list of connected peripherals identified by an offered service.
  Future<Iterable<api.PeripheralData>> connectedPeripherals({
    Iterable<String> serviceUuids = const [],
    String? clientIdentifier,
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
    required api.PeripheralSessionIdentifier sessionIdentifier,
  });

  /// Cancels an active or pending connection to the peripheral.
  Future<void> cancelConnection({
    required api.PeripheralSessionIdentifier sessionIdentifier,
  });

  /// Discovers services offered by the peripheral.
  Future<void> discoverServices({
    required api.PeripheralSessionIdentifier sessionIdentifier,
    Iterable<String> serviceUuids = const [],
  });

  /// A list of discovered services offered by the peripheral.
  Future<Iterable<api.ServiceData>> services({
    required api.PeripheralSessionIdentifier sessionIdentifier,
  });

  /// Discovers characteristics offered by the service.
  Future<void> discoverCharacteristics({
    required api.PeripheralSessionIdentifier sessionIdentifier,
    required String serviceUuid,
    Iterable<String> characteristicUuids = const [],
  });

  /// A list of discovered characteristics offered by the service.
  Future<Iterable<api.CharacteristicData>> characteristics({
    required api.PeripheralSessionIdentifier sessionIdentifier,
    required String serviceUuid,
  });

  /// Reads the value of the characteristic.
  Future<Uint8List> readCharacteristic({
    required api.PeripheralSessionIdentifier sessionIdentifier,
    required String serviceUuid,
    required String characteristicUuid,
  });

  /// Writes the value of the characteristic.
  Future<void> writeCharacteristic({
    required api.PeripheralSessionIdentifier sessionIdentifier,
    required String serviceUuid,
    required String characteristicUuid,
    required Uint8List value,
    bool withoutResponse = false,
  });

  /// Streams characteristic value updates.
  Stream<Uint8List> watchCharacteristic({
    required api.PeripheralSessionIdentifier sessionIdentifier,
    required String serviceUuid,
    required String characteristicUuid,
  });

  /// The platform-specific implementation of [PeripheralManager].

  /// Advertises the peripheral's services.
  Future<void> startAdvertising({
    required api.PeripheralData peripheral,
  });
}
