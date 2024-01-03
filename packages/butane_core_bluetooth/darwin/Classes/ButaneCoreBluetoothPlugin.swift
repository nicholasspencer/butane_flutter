#if os(iOS)
import Flutter
import UIKit
#elseif os(macOS)
import FlutterMacOS
import AppKit
#else
#error("Unsupported platform.")
#endif
import CoreBluetooth

 extension FlutterError: Error {}

extension Result where Success == Void {
  static var success: Result {
    return .success(())
  }
}

public class ButaneCoreBluetoothPlugin: NSObject, FlutterPlugin, ButaneHostApi, CBCentralManagerDelegate, CBPeripheralDelegate {
  var flutterApi: ButaneFlutterApi
  
  var centralManager: CBCentralManager!
  
  public static func register(with registrar: FlutterPluginRegistrar) {
    let flutterApi = ButaneFlutterApi(binaryMessenger: registrar.messenger)
    let instance = ButaneCoreBluetoothPlugin(flutterApi: flutterApi)
    ButaneHostApiSetup.setUp(binaryMessenger: registrar.messenger, api: instance)
  }
  
  init(flutterApi: ButaneFlutterApi) {
    self.flutterApi = flutterApi
    
    super.init()
    
    centralManager = CBCentralManager(delegate: self, queue: nil)
  }
  
  // MARK: Flutter API
  
  func onNativeResult(_: Result<Void, FlutterError>) {}
  
  func scan(requestIdentifier: String?, forServices: [String]?, completion: @escaping (Result<Void, Error>) -> Void) {
    let uuids: [CBUUID]? = forServices?.map({
      return CBUUID(string: $0)
    })
    
    centralManager.scanForPeripherals(withServices: uuids)
    
    completion(.success)
  }
  
  func cancelScan(requestIdentifier: String?) throws {
   
  }
  
  func peripherals(peripheralIdentifiers: [String]?, completion: @escaping (Result<[PeripheralData], Error>) -> Void) {
  
  }
  
  func connect(peripheralIdentifier: String, completion: @escaping (Result<Void, Error>) -> Void) {
    guard 
      let identifier = UUID(uuidString: peripheralIdentifier),
      let peripheral = peripherals[identifier] else {
        completion(.failure(FlutterError()))
        return
    }
    
    centralManager.connect(peripheral)
  }
  
  func cancelConnection(peripheralIdentifier: String, completion: @escaping (Result<Void, Error>) -> Void) {
  
  }
  
  func connectedPeripherals(serviceUuids: [String]?, completion: @escaping (Result<[PeripheralData], Error>) -> Void) {
  
  }
  
  func discoverServices(peripheralIdentifier: String, serviceUuids: [String]?, completion: @escaping (Result<Void, Error>) -> Void) {
  
  }
  
  func services(peripheralIdentifier: String, completion: @escaping (Result<[ServiceData], Error>) -> Void) {
  
  }
  
  func discoverCharacteristics(peripheralIdentifier: String, serviceUuid: String, characteristicUuids: [String]?, completion: @escaping (Result<Void, Error>) -> Void) {
  
  }
  
  func characteristics(peripheralIdentifier: String, serviceUuid: String, completion: @escaping (Result<[CharacteristicData], Error>) -> Void) {
  
  }
  
  func readCharacteristic(peripheralIdentifier: String, serviceUuid: String, characteristicUuid: String, completion: @escaping (Result<FlutterStandardTypedData, Error>) -> Void) {
  
  }
  
  func writeCharacteristic(peripheralIdentifier: String, serviceUuid: String, characteristicUuid: String, value: [Int64], withoutResponse: Bool, completion: @escaping (Result<Void, Error>) -> Void) {
  
  }
  
  func watchCharacteristic(peripheralIdentifier: String, serviceUuid: String, characteristicUuid: String, completion: @escaping (Result<Void, Error>) -> Void) {
  
  }
  
  func setNotification(peripheralIdentifier: String, serviceUuid: String, characteristicUuid: String, enabled: Bool, completion: @escaping (Result<Void, Error>) -> Void) {
  
  }
  
  func readDescriptor(peripheralIdentifier: String, serviceUuid: String, descriptorUuid: String, completion: @escaping (Result<[Int64], Error>) -> Void) {
  
  }
  
  func writeDescriptor(peripheralIdentifier: String, serviceUuid: String, descriptorUuid: String, value: [Int64], completion: @escaping (Result<Void, Error>) -> Void) {
  
  }
  
  func readRssi(peripheralIdentifier: String, completion: @escaping (Result<Int64, Error>) -> Void) {
  
  }
  
  func requestMtu(peripheralIdentifier: String, mtu: Int64, completion: @escaping (Result<Int64, Error>) -> Void) {
  
  }
  
  // MARK: Central Delegate
  
  var peripherals: [UUID: CBPeripheral] = [:]
  
  public func centralManagerDidUpdateState(_ central: CBCentralManager) {
    flutterApi.onManagerState(
      state: central.state.managerState,
      completion: onNativeResult
    )
  }
  
  public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
    peripheral.delegate = self
    peripherals[peripheral.identifier] = peripheral
    
    flutterApi.onScanResult(
      requestIdentifier: nil,
      scanResult: ScanData(peripheral: PeripheralData(
        identifier: peripheral.identifier.uuidString,
        name: peripheral.name),
        advertisementData: AdvertisementData.init(advertisementData: advertisementData)
      ),
      completion: onNativeResult
    )
  }
  
  public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
    flutterApi.onConnectionState(
      peripheral: peripheral.toPeripheralData(),
      state: .connected,
      completion: onNativeResult
    )
  }
}

extension CBManagerState {
  var managerState: ManagerState {
    switch(self) {
    case .resetting:
      return .resetting
    case .unsupported:
      return .unsupported
    case .unauthorized:
      return .unauthorized
    case .poweredOff:
      return .poweredOff
    case .poweredOn:
      return .poweredOn
    default:
      return .unknown
    }
  }
}

extension CBPeripheral {
  func toPeripheralData() -> PeripheralData {
    return PeripheralData(
      identifier: identifier.uuidString,
      name: name
    )
  }
}

extension AdvertisementData {
  init(advertisementData: [String: Any]) {
    localName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
    
    if let txPowerLevel = advertisementData[CBAdvertisementDataTxPowerLevelKey] as? NSNumber {
      self.txPowerLevel = txPowerLevel.int64Value
    }
    
    if let rawManufacturerData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data {
      manufacturerData = FlutterStandardTypedData(bytes: rawManufacturerData)
    }
    
    if let services = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] {
      serviceUuids = services.map({ $0.uuidString })
    }
  }
}
