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

public class ButaneCoreBluetoothPlugin: NSObject, FlutterPlugin, ButaneHostApi {
  var flutterApi: ButaneFlutterApi
  
  var centralManagers: [String?:CentralManager] = [:]
  
  public static func register(with registrar: FlutterPluginRegistrar) {
    let flutterApi = ButaneFlutterApi(binaryMessenger: registrar.messenger)
    let instance = ButaneCoreBluetoothPlugin(flutterApi: flutterApi)
    ButaneHostApiSetup.setUp(binaryMessenger: registrar.messenger, api: instance)
  }
  
  init(flutterApi: ButaneFlutterApi) {
    self.flutterApi = flutterApi
  }
  
  func centralManager(_ id: String?) -> CentralManager {
    if let manager = centralManagers[id] {
      return manager;
    }
    
    let manager = CentralManager(identifier: id, flutterApi: flutterApi, queue: nil)
    
    centralManagers[id] = manager;
    
    return manager;
  }
  
  // MARK: Flutter API
  
  func state(clientIdentifier: String?, completion: @escaping (Result<ClientState, Error>) -> Void) {
    let central = centralManager(clientIdentifier)
    
    central.state(completion: completion)
  }
  
  func scan(clientIdentifier: String?, forServices: [String]?, completion: @escaping (Result<Void, Error>) -> Void) {
    let central = centralManager(clientIdentifier)
    
    central.scan(forServices: forServices, completion: completion)
  }
  
  func cancelScan(clientIdentifier: String?, completion: @escaping (Result<Void, Error>) -> Void) {
    
  }
  
  func peripherals(clientIdentifier: String?, peripheralIdentifiers: [String]?, completion: @escaping (Result<[PeripheralData], Error>) -> Void) {
    
  }
  
  func connectedPeripherals(clientIdentifier: String?, serviceUuids: [String]?, completion: @escaping (Result<[PeripheralData], Error>) -> Void) {
    
  }
  
  func connect(sessionIdentifier: PeripheralSessionIdentifier, completion: @escaping (Result<Void, Error>) -> Void) {
    centralManager(sessionIdentifier.clientIdentifier).connect(identifier: sessionIdentifier.identifier, completion: completion)
  }
  
  func cancelConnection(sessionIdentifier: PeripheralSessionIdentifier, completion: @escaping (Result<Void, Error>) -> Void) {
    
  }
  
  func connectionState(sessionIdentifier: PeripheralSessionIdentifier, completion: @escaping (Result<ConnectionState, Error>) -> Void) {
    centralManager(sessionIdentifier.clientIdentifier).connectionState(identifier: sessionIdentifier.identifier, completion: completion)
  }
  
  func discoverServices(sessionIdentifier: PeripheralSessionIdentifier, serviceUuids: [String]?, completion: @escaping (Result<Void, Error>) -> Void) {
    
  }
  
  func services(sessionIdentifier: PeripheralSessionIdentifier, completion: @escaping (Result<[ServiceData], Error>) -> Void) {
    
  }
  
  func discoverCharacteristics(sessionIdentifier: PeripheralSessionIdentifier, serviceUuid: String, characteristicUuids: [String]?, completion: @escaping (Result<Void, Error>) -> Void) {
    
  }
  
  func characteristics(sessionIdentifier: PeripheralSessionIdentifier, serviceUuid: String, completion: @escaping (Result<[CharacteristicData], Error>) -> Void) {
    
  }
  
  func readCharacteristic(sessionIdentifier: PeripheralSessionIdentifier, serviceUuid: String, characteristicUuid: String, completion: @escaping (Result<FlutterStandardTypedData, Error>) -> Void) {
    
  }
  
  func writeCharacteristic(sessionIdentifier: PeripheralSessionIdentifier, serviceUuid: String, characteristicUuid: String, value: [Int64], withoutResponse: Bool, completion: @escaping (Result<Void, Error>) -> Void) {
    
  }
  
  func watchCharacteristic(sessionIdentifier: PeripheralSessionIdentifier, serviceUuid: String, characteristicUuid: String, completion: @escaping (Result<Void, Error>) -> Void) {
    
  }
  
  func setNotification(sessionIdentifier: PeripheralSessionIdentifier, serviceUuid: String, characteristicUuid: String, enabled: Bool, completion: @escaping (Result<Void, Error>) -> Void) {
    
  }
  
  func readDescriptor(sessionIdentifier: PeripheralSessionIdentifier, serviceUuid: String, descriptorUuid: String, completion: @escaping (Result<[Int64], Error>) -> Void) {
    
  }
  
  func writeDescriptor(sessionIdentifier: PeripheralSessionIdentifier, serviceUuid: String, descriptorUuid: String, value: [Int64], completion: @escaping (Result<Void, Error>) -> Void) {
    
  }
  
  func readRssi(sessionIdentifier: PeripheralSessionIdentifier, completion: @escaping (Result<Int64, Error>) -> Void) {
    
  }
  
  func requestMtu(sessionIdentifier: PeripheralSessionIdentifier, mtu: Int64, completion: @escaping (Result<Int64, Error>) -> Void) {
    
  }
}

extension Result where Success == Void {
  static var success: Result {
    return .success(())
  }
}

extension CBManagerState {
  var managerState: ClientState {
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
      identifier: PeripheralSessionIdentifier(identifier: identifier.uuidString),
      name: name,
      state: state.connectionState
    )
  }
}

extension CBPeripheralState {
  var connectionState: ConnectionState {
    switch(self) {
    case .disconnected:
        .disconnected
    case .connecting:
        .connecting
    case .connected:
        .connected
    case .disconnecting:
        .disconnecting
    @unknown default:
        .disconnected
    }
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
    
    if let isConnectable = advertisementData[CBAdvertisementDataIsConnectable] as? Bool {
      self.isConnectable = isConnectable
    } else {
      self.isConnectable = false
    }
  }
}
