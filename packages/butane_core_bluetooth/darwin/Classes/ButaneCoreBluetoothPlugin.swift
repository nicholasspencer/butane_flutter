#if os(iOS)
import Flutter
import UIKit
#elseif os(macOS)
import AppKit
import FlutterMacOS
#else
#error("Unsupported platform.")
#endif
import CoreBluetooth

extension FlutterError: Error {}

public class ButaneCoreBluetoothPlugin: NSObject, FlutterPlugin, ButaneHostApi {
  var flutterApi: ButaneFlutterApi
  
  var centralManagers: [String?: CentralManager] = [:]
  
  public static func register(with registrar: FlutterPluginRegistrar) {
    let flutterApi = ButaneFlutterApi(binaryMessenger: registrar.messenger)
    let instance = ButaneCoreBluetoothPlugin(flutterApi: flutterApi)
    ButaneHostApiSetup.setUp(binaryMessenger: registrar.messenger, api: instance)
  }
  
  init(flutterApi: ButaneFlutterApi) {
    self.flutterApi = flutterApi
  }
  
  func centralManager(_ session: Session?) -> CentralManager {
    if let manager = centralManagers[session?.clientIdentifier] {
      return manager
    }
    
    let manager = CentralManager(
      identifier: session?.clientIdentifier,
      restorationIdentifier: session?.restorationIdentifier,
      flutterApi: flutterApi,
      queue: nil
    )
    
    centralManagers[session?.clientIdentifier] = manager
    
    return manager
  }
  
  // MARK: Flutter API
  
  func state(session: Session?, completion: @escaping (Result<ClientState, Error>) -> Void) {
    let central = centralManager(session)
    
    completion(.success(central.state))
  }
  
  func scan(session: Session?, forServices: [String]?, completion: @escaping (Result<Void, Error>) -> Void) {
    let central = centralManager(session)
    
    central.scan(forServices: forServices)
    
    completion(.success)
  }
  
  func cancelScan(session: Session?, completion: @escaping (Result<Void, Error>) -> Void) {
    let central = centralManager(session)
      
    central.cancelScan()
      
    completion(.success)
  }
  
  func peripherals(session: Session?, peripheralIdentifiers: [String], completion: @escaping (Result<[Peripheral], Error>) -> Void) {
    let central = centralManager(session)
    
    let peripherals = central.peripherals(peripheralIdentifiers: peripheralIdentifiers)
    
    completion(.success(peripherals))
  }
  
  func connectedPeripherals(session: Session?, serviceUuids: [String], completion: @escaping (Result<[Peripheral], Error>) -> Void) {
    let central = centralManager(session)
    
    let peripherals = central.connectedPeripherals(serviceUuids: serviceUuids)
    
    completion(.success(peripherals))
  }
  
  func connect(session: PeripheralSession, completion: @escaping (Result<Void, Error>) -> Void) {
    centralManager(session.session).connect(identifier: session.peripheralIdentifier)
    
    completion(.success)
  }
  
  func cancelConnection(session: PeripheralSession, completion: @escaping (Result<Void, Error>) -> Void) {
    centralManager(session.session).cancelConnection(identifier: session.peripheralIdentifier)
    
    completion(.success)
  }
  
  func connectionState(session: PeripheralSession, completion: @escaping (Result<ConnectionState, Error>) -> Void) {
    let state = centralManager(session.session).connectionState(identifier: session.peripheralIdentifier)
    
    completion(.success(state))
  }
  
  func discoverServices(session: PeripheralSession, serviceUuids: [String]?, completion: @escaping (Result<Void, Error>) -> Void) {
    Task { discoverServices(session: session, serviceUuids: serviceUuids, completion: completion) }
  }
  
  func discoverServices(session: PeripheralSession, serviceUuids: [String]?, completion: @escaping (Result<Void, Error>) -> Void) async {
    let central = centralManager(session.session)
    
    do {
      try await central.discoverServices(identifier: session.peripheralIdentifier, serviceUuids: serviceUuids)
      completion(.success)
    } catch {
      completion(.failure(FlutterError()))
    }
  }
  
  func services(session: PeripheralSession, completion: @escaping (Result<[Service], Error>) -> Void) {
    let central = centralManager(session.session)
    
    let services = central.services(identifier: session.peripheralIdentifier)
    
    completion(.success(services))
  }
  
  func discoverCharacteristics(session: PeripheralSession, serviceUuid: String, characteristicUuids: [String]?, completion: @escaping (Result<Void, Error>) -> Void) {}
  
  func characteristics(session: PeripheralSession, serviceUuid: String, completion: @escaping (Result<[Characteristic], Error>) -> Void) {}
  
  func readCharacteristic(session: PeripheralSession, serviceUuid: String, characteristicUuid: String, completion: @escaping (Result<FlutterStandardTypedData, Error>) -> Void) {}
  
  func writeCharacteristic(session: PeripheralSession, serviceUuid: String, characteristicUuid: String, value: [Int64], withoutResponse: Bool, completion: @escaping (Result<Void, Error>) -> Void) {}
  
  func watchCharacteristic(session: PeripheralSession, serviceUuid: String, characteristicUuid: String, completion: @escaping (Result<Void, Error>) -> Void) {}
  
  func setNotification(session: PeripheralSession, serviceUuid: String, characteristicUuid: String, enabled: Bool, completion: @escaping (Result<Void, Error>) -> Void) {}
  
  func readDescriptor(session: PeripheralSession, serviceUuid: String, descriptorUuid: String, completion: @escaping (Result<[Int64], Error>) -> Void) {}
  
  func writeDescriptor(session: PeripheralSession, serviceUuid: String, descriptorUuid: String, value: [Int64], completion: @escaping (Result<Void, Error>) -> Void) {}
  
  func readRssi(session: PeripheralSession, completion: @escaping (Result<Int64, Error>) -> Void) {
    Task { readRssi(session: session, completion: completion) }
  }
  
  func readRssi(session: PeripheralSession, completion: @escaping (Result<Int64, Error>) -> Void) async {
    let central = centralManager(session.session)
    
    if let rssi = try? await central.readRssi(identifier: session.peripheralIdentifier) {
      completion(.success(rssi))
    } else {
      completion(.failure(FlutterError()))
    }
  }
  
  func requestMtu(session: PeripheralSession, mtu: Int64, completion: @escaping (Result<Int64, Error>) -> Void) {}
}

extension Result where Success == Void {
  static var success: Result {
    return .success(())
  }
}

extension PeripheralSession {
  var session: Session {
    Session(
      peripheralIdentifier: peripheralIdentifier,
      clientIdentifier: clientIdentifier,
      adapterIdentifier: adapterIdentifier,
      restorationIdentifier: restorationIdentifier
    )
  }
}

extension CBManagerState {
  var managerState: ClientState {
    switch self {
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
      session: PeripheralSession(peripheralIdentifier: identifier.uuidString),
      name: name,
      state: state.connectionState
    )
  }
  
  func toPeripheral(session: PeripheralSession?) -> Peripheral {
    return Peripheral(
      session: session ?? PeripheralSession(peripheralIdentifier: identifier.uuidString),
      name: name,
      state: state.connectionState
    )
  }
  
  func toPeripheral(session: PeripheralSession?, rssi: NSNumber) -> Peripheral {
    return Peripheral(
      session: session ?? PeripheralSession(peripheralIdentifier: identifier.uuidString),
      name: name,
      rssi: rssi.int64Value,
      state: state.connectionState
    )
  }
}

extension CBPeripheralState {
  var connectionState: ConnectionState {
    switch self {
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
      serviceUuids = services.map { $0.uuidString }
    }
    
    if let isConnectable = advertisementData[CBAdvertisementDataIsConnectable] as? Bool {
      self.isConnectable = isConnectable
    } else {
      self.isConnectable = false
    }
  }
}
