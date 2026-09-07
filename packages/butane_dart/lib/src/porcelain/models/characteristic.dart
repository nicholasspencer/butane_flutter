part of '../porcelain.dart';

base class Characteristic extends Attribute {
  Characteristic({
    required super.uuid,
    required this.service,
    this.properties,
  }) : _descriptorData = null;

  Characteristic._fromData({
    required super.uuid,
    required this.service,
    required List<api.Descriptor>? descriptorData,
    this.properties,
  }) : _descriptorData = descriptorData;

  final Service? service;

  /// The operations supported by this characteristic, if reported.
  final CharacteristicProperties? properties;

  final List<api.Descriptor>? _descriptorData;

  /// Descriptors discovered for this characteristic.
  late final List<Descriptor> descriptors = (_descriptorData ?? const [])
      .map(
        (data) => Descriptor(
          uuid: UuidIdentifier(data.uuid),
          characteristic: this,
        ),
      )
      .toList(growable: false);

  @protected
  PlatformStreamController<Uint8List, Uint8List>? valueStreamController;

  /// Reads the value of the characteristic.
  Future<Uint8List> read() async {
    final data = await service?.peripheral?.manager.platform.readCharacteristic(
      session: service!.peripheral!.session,
      serviceUuid: service!.uuid.toString(),
      characteristicUuid: uuid.toString(),
    );

    return data ?? Uint8List(0);
  }

  /// Writes the value of the characteristic.
  Future<void> write({
    required Uint8List value,
    bool withoutResponse = false,
  }) async {
    return service?.peripheral?.manager.platform.writeCharacteristic(
      session: service!.peripheral!.session,
      serviceUuid: service!.uuid.toString(),
      characteristicUuid: uuid.toString(),
      value: value,
      withoutResponse: withoutResponse,
    );
  }

  /// Streams characteristic value updates.
  ///
  /// Cancelling the stream will cancel your subscription to updates. Once
  /// all subscriptions are cancelled, the platform will stop observing the
  /// characteristic.
  Stream<Uint8List> observe() {
    valueStreamController ??= PlatformStreamController<Uint8List, Uint8List>(
      debugLabel: 'Characteristic($uuid).watch',
      platform: service?.peripheral?.manager.platform,
      map: (value) {
        return value;
      },
      createStream: (platform) {
        return platform.characteristicValueStream(
          session: service!.peripheral!.session,
          serviceUuid: service!.uuid.toString(),
          characteristicUuid: uuid.toString(),
        );
      },
      onListen: (platform) {
        return platform.observeCharacteristic(
          observe: true,
          session: service!.peripheral!.session,
          serviceUuid: service!.uuid.toString(),
          characteristicUuid: uuid.toString(),
        );
      },
      sinkValue: (platform) async {
        final value = await platform.readCharacteristic(
          session: service!.peripheral!.session,
          serviceUuid: service!.uuid.toString(),
          characteristicUuid: uuid.toString(),
        );

        return value;
      },
      onCancel: (platform) async {
        return await platform.observeCharacteristic(
          observe: false,
          session: service!.peripheral!.session,
          serviceUuid: service!.uuid.toString(),
          characteristicUuid: uuid.toString(),
        );
      },
    );

    return valueStreamController!.stream;
  }

  @protected
  api.Characteristic toData() {
    return api.Characteristic(
      uuid: uuid.toString(),
    );
  }
}

extension ApiCharacteristic on api.Characteristic {
  Characteristic toCharacteristic({
    required Service service,
  }) {
    return Characteristic._fromData(
      uuid: UuidIdentifier(uuid),
      service: service,
      descriptorData: descriptors,
      properties: properties == null
          ? null
          : CharacteristicProperties.fromApi(properties!),
    );
  }
}
