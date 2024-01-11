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
    
    completion(.success(central.state))
  }
  
  func scan(clientIdentifier: String?, forServices: [String]?, completion: @escaping (Result<Void, Error>) -> Void) {
    let central = centralManager(clientIdentifier)
    
    central.scan(forServices: forServices)
    
    completion(.success)
  }
  
  func cancelScan(clientIdentifier: String?, completion: @escaping (Result<Void, Error>) -> Void) {
    
  }
  
  func peripherals(clientIdentifier: String?, peripheralIdentifiers: [String]?, completion: @escaping (Result<[Peripheral], Error>) -> Void) {
    
  }
  
  func connectedPeripherals(clientIdentifier: String?, serviceUuids: [String]?, completion: @escaping (Result<[Peripheral], Error>) -> Void) {
    
  }
  
  func connect(session: Session, completion: @escaping (Result<Void, Error>) -> Void) {
    centralManager(session.clientIdentifier).connect(identifier: session.peripheralIdentifier)
    
    completion(.success)
  }
  
  func cancelConnection(session: Session, completion: @escaping (Result<Void, Error>) -> Void) {
    centralManager(session.clientIdentifier).cancelConnection(identifier: session.peripheralIdentifier)
    
    completion(.success)
  }
  
  func connectionState(session: Session, completion: @escaping (Result<ConnectionState, Error>) -> Void) {
    let state = centralManager(session.clientIdentifier).connectionState(identifier: session.peripheralIdentifier)
    
    completion(.success(state))
  }
  
  func discoverServices(session: Session, serviceUuids: [String]?, completion: @escaping (Result<Void, Error>) -> Void) {
    
  }
  
  func services(session: Session, completion: @escaping (Result<[Service], Error>) -> Void) {
    
  }
  
  func discoverCharacteristics(session: Session, serviceUuid: String, characteristicUuids: [String]?, completion: @escaping (Result<Void, Error>) -> Void) {
    
  }
  
  func characteristics(session: Session, serviceUuid: String, completion: @escaping (Result<[Characteristic], Error>) -> Void) {
    
  }
  
  func readCharacteristic(session: Session, serviceUuid: String, characteristicUuid: String, completion: @escaping (Result<FlutterStandardTypedData, Error>) -> Void) {
    
  }
  
  func writeCharacteristic(session: Session, serviceUuid: String, characteristicUuid: String, value: [Int64], withoutResponse: Bool, completion: @escaping (Result<Void, Error>) -> Void) {
    
  }
  
  func watchCharacteristic(session: Session, serviceUuid: String, characteristicUuid: String, completion: @escaping (Result<Void, Error>) -> Void) {
    
  }
  
  func setNotification(session: Session, serviceUuid: String, characteristicUuid: String, enabled: Bool, completion: @escaping (Result<Void, Error>) -> Void) {
    
  }
  
  func readDescriptor(session: Session, serviceUuid: String, descriptorUuid: String, completion: @escaping (Result<[Int64], Error>) -> Void) {
    
  }
  
  func writeDescriptor(session: Session, serviceUuid: String, descriptorUuid: String, value: [Int64], completion: @escaping (Result<Void, Error>) -> Void) {
    
  }
  
  func readRssi(session: Session, completion: @escaping (Result<Int64, Error>) -> Void) {
    Task { readRssi(session: session, completion: completion) }
  }
  
  func readRssi(session: Session, completion: @escaping (Result<Int64, Error>) -> Void) async {
    let central = centralManager(session.clientIdentifier)
    
    if let rssi = try? await central.readRssi(identifier: session.peripheralIdentifier) {
      completion(.success(rssi))
    } else {
      completion(.failure(FlutterError()))
    }
  }
  
  func requestMtu(session: Session, mtu: Int64, completion: @escaping (Result<Int64, Error>) -> Void) {
    
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
  func toPeripheral() -> Peripheral {
    return Peripheral(
      session: Session(peripheralIdentifier: identifier.uuidString),
      name: name,
      state: state.connectionState
    )
  }
  
  func toPeripheral(session: Session?) -> Peripheral {
    return Peripheral(
      session: session ?? Session(peripheralIdentifier: identifier.uuidString),
      name: name,
      state: state.connectionState
    )
  }
  
  func toPeripheral( session: Session?, rssi: NSNumber) -> Peripheral {
    return Peripheral(
      session: session ?? Session(peripheralIdentifier: identifier.uuidString),
      name: name,
      rssi: rssi.int64Value,
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
