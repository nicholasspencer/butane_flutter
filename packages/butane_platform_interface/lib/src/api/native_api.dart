import 'dart:async';
import 'dart:typed_data';

import 'package:meta/meta.dart';

import 'api.g.dart' as api;

typedef ScanResult = ({
  String? requestIdentifier,
  api.ScanData scanData,
});

typedef ConnectionStateResult = ({
  api.PeripheralData peripheral,
  api.ConnectionState state,
});

typedef CharacteristicValueResult = ({
  api.PeripheralData peripheral,
  api.CharacteristicData characteristic,
  Uint8List value,
});

base class ButaneFlutterApi extends api.ButaneFlutterApi {
  ButaneFlutterApi() {
    api.ButaneFlutterApi.setup(this);
  }

  Stream<api.ManagerState> get managerStateStream =>
      managerStateController.stream;

  Stream<ScanResult> get scanStream => scanController.stream;

  Stream<ConnectionStateResult> get connectionStateStream =>
      connectionStateController.stream;

  Stream<CharacteristicValueResult> get characteristicValueStream =>
      characteristicValueController.stream;

  @protected
  final managerStateController = StreamController<api.ManagerState>.broadcast();

  @protected
  final scanController = StreamController<ScanResult>.broadcast();

  @protected
  final connectionStateController =
      StreamController<ConnectionStateResult>.broadcast();

  @protected
  final characteristicValueController =
      StreamController<CharacteristicValueResult>.broadcast();

  @protected
  @override
  void onManagerState(api.ManagerState state) {
    managerStateController.sink.add(state);
  }

  @protected
  @override
  void onScanResult(String? requestIdentifier, api.ScanData scanResult) {
    scanController.sink.add(
      (
        requestIdentifier: requestIdentifier,
        scanData: scanResult,
      ),
    );
  }

  @protected
  @override
  void onConnectionState(
    api.PeripheralData peripheral,
    api.ConnectionState state,
  ) {
    connectionStateController.sink.add(
      (
        peripheral: peripheral,
        state: state,
      ),
    );
  }

  @protected
  @override
  void onCharacteristicValue(
    api.PeripheralData peripheral,
    api.CharacteristicData characteristic,
    Uint8List value,
  ) {
    characteristicValueController.sink.add(
      (
        peripheral: peripheral,
        characteristic: characteristic,
        value: value,
      ),
    );
  }

  @override
  void onCharacteristicsDiscovered(
    api.PeripheralData peripheral,
    api.ServiceData service,
  ) {
    // TODO: implement onCharacteristicsDiscovered
  }

  @override
  void onDescriptorValue(
    api.PeripheralData peripheral,
    api.DescriptorData descriptor,
    Uint8List value,
  ) {
    // TODO: implement onDescriptorValue
  }

  @override
  void onDescriptorsDiscovered(
    api.PeripheralData peripheral,
    api.CharacteristicData characteristic,
  ) {
    // TODO: implement onDescriptorsDiscovered
  }

  @override
  void onRssi(api.PeripheralData peripheral, int rssi) {
    // TODO: implement onRssi
  }

  @override
  void onServicesDiscovered(api.PeripheralData peripheral) {
    // TODO: implement onServicesDiscovered
  }
}

extension ScanResultStreamFilter on Stream<ScanResult> {
  Stream<ScanResult> forRequest(String? requestIdentifier) {
    return where((result) => result.requestIdentifier == requestIdentifier);
  }
}

extension ConnectionStateResultStreamFilter on Stream<ConnectionStateResult> {
  Stream<ConnectionStateResult> forPeripheral(String peripheralIdentifier) {
    return where(
      (result) => result.peripheral.identifier == peripheralIdentifier,
    );
  }
}

extension CharacteristicValueResultStreamFilter
    on Stream<CharacteristicValueResult> {
  Stream<CharacteristicValueResult> forCharacteristic({
    required String peripheralIdentifier,
    required String characteristicUuid,
  }) {
    return where(
      (result) =>
          result.peripheral.identifier == peripheralIdentifier &&
          result.characteristic.uuid == characteristicUuid,
    );
  }

  Stream<Uint8List> valueForCharacteristic({
    required String characteristicUuid,
    required String peripheralIdentifier,
  }) {
    return forCharacteristic(
      characteristicUuid: characteristicUuid,
      peripheralIdentifier: peripheralIdentifier,
    ).map((result) => Uint8List.fromList(result.value.nonNulls.toList()));
  }
}
