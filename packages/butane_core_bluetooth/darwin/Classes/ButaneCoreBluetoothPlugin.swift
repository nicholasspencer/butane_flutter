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
  
  var peripheralManagers: [String?: PeripheralManager] = [:]
  
  public static func register(with registrar: FlutterPluginRegistrar) {
    #if os(iOS)
    let messenger = registrar.messenger()
    #elseif os(macOS)
    let messenger = registrar.messenger
    #endif
    let flutterApi = ButaneFlutterApi(binaryMessenger: messenger)
    let instance = ButaneCoreBluetoothPlugin(flutterApi: flutterApi)
    ButaneHostApiSetup.setUp(binaryMessenger: messenger, api: instance)
  }
  
  init(flutterApi: ButaneFlutterApi) {
    self.flutterApi = flutterApi
  }
  
  func centralManager(_ session: ClientSession?) -> CentralManager {
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
  
  func peripheralManager(_ session: PeripheralManagerSession?) -> PeripheralManager {
    if let manager = peripheralManagers[session?.clientIdentifier] {
      return manager
    }
    
    let manager = PeripheralManager(
      identifier: session?.clientIdentifier,
      restorationIdentifier: session?.restorationIdentifier,
      flutterApi: flutterApi,
      queue: nil
    )
    
    peripheralManagers[session?.clientIdentifier] = manager
    
    return manager
  }
  
  // MARK: Flutter API
  
  func state(session: ClientSession?, completion: @escaping (Result<ClientState, Error>) -> Void) {
    let central = centralManager(session)
    
    completion(.success(central.state))
  }
  
  func scan(session: ClientSession?, forServices: [String]?, completion: @escaping (Result<Void, Error>) -> Void) {
    let central = centralManager(session)
    
    central.scan(forServices: forServices)
    
    completion(.success)
  }
  
  func cancelScan(session: ClientSession?, completion: @escaping (Result<Void, Error>) -> Void) {
    let central = centralManager(session)
      
    central.cancelScan()
      
    completion(.success)
  }
  
  func peripherals(session: ClientSession?, peripheralIdentifiers: [String], completion: @escaping (Result<[Peripheral], Error>) -> Void) {
    let central = centralManager(session)
    
    let peripherals = central.peripherals(peripheralIdentifiers: peripheralIdentifiers)
    
    completion(.success(peripherals))
  }
  
  func connectedPeripherals(session: ClientSession?, serviceUuids: [String], completion: @escaping (Result<[Peripheral], Error>) -> Void) {
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
    print("outer discoverServices")
    Task {
      await discoverServices(session: session, serviceUuids: serviceUuids, completion: completion)
    }
  }
  
  func services(session: PeripheralSession, completion: @escaping (Result<[Service], Error>) -> Void) {
    let central = centralManager(session.session)
    
    let services = central.services(identifier: session.peripheralIdentifier)
    
    completion(.success(services))
  }
  
  func discoverCharacteristics(session: PeripheralSession, serviceUuid: String, characteristicUuids: [String]?, completion: @escaping (Result<Void, Error>) -> Void) {
    print("outer discoverCharacteristics")
    Task {
      await discoverCharacteristics(session: session, serviceUuid: serviceUuid, characteristicUuids: characteristicUuids, completion: completion)
    }
  }
  
  func characteristics(session: PeripheralSession, serviceUuid: String, completion: @escaping (Result<[Characteristic], Error>) -> Void) {
    let central = centralManager(session.session)
      
    let characteristics = central.characteristics(identifier: session.peripheralIdentifier, serviceUuid: serviceUuid)
      
    completion(.success(characteristics))
  }
  
  func readCharacteristic(session: PeripheralSession, serviceUuid: String, characteristicUuid: String, completion: @escaping (Result<FlutterStandardTypedData, Error>) -> Void) {
    Task { await readCharacteristic(session: session, serviceUuid: serviceUuid, characteristicUuid: characteristicUuid, completion: completion) }
  }
  
  func writeCharacteristic(session: PeripheralSession, serviceUuid: String, characteristicUuid: String, value: FlutterStandardTypedData, withoutResponse: Bool, completion: @escaping (Result<Void, Error>) -> Void) {
    Task { await writeCharacteristic(session: session, serviceUuid: serviceUuid, characteristicUuid: characteristicUuid, value: value, withoutResponse: withoutResponse, completion: completion) }
  }
  
  func observeCharacteristic(observe: Bool, session: PeripheralSession, serviceUuid: String, characteristicUuid: String, completion: @escaping (Result<Void, Error>) -> Void) {
    Task { await observeCharacteristic(observe: observe, session: session, serviceUuid: serviceUuid, characteristicUuid: characteristicUuid, completion: completion) }
  }
  
  func readDescriptor(session: PeripheralSession, serviceUuid: String, characteristicUuid: String, descriptorUuid: String, completion: @escaping (Result<FlutterStandardTypedData, Error>) -> Void) {}
  
  func writeDescriptor(session: PeripheralSession, serviceUuid: String, characteristicUuid: String, descriptorUuid: String, value: FlutterStandardTypedData, completion: @escaping (Result<Void, Error>) -> Void) {}
  
  func readRssi(session: PeripheralSession, completion: @escaping (Result<Int64, Error>) -> Void) {
    Task { await readRssi(session: session, completion: completion) }
  }
  
  func requestMtu(session: PeripheralSession, mtu: Int64, completion: @escaping (Result<Int64, Error>) -> Void) {}
  
  // MARK: Peripheral Manager API
  
  func peripheralManagerState(session: PeripheralManagerSession, completion: @escaping (Result<ClientState, Error>) -> Void) {
    let pm = peripheralManager(session)
    completion(.success(pm.state))
  }
  
  func startAdvertising(session: PeripheralManagerSession, localName: String?, serviceUuids: [String]?, completion: @escaping (Result<Void, Error>) -> Void) {
    let pm = peripheralManager(session)
    pm.startAdvertising(localName: localName, serviceUuids: serviceUuids)
    completion(.success)
  }
  
  func stopAdvertising(session: PeripheralManagerSession, completion: @escaping (Result<Void, Error>) -> Void) {
    let pm = peripheralManager(session)
    pm.stopAdvertising()
    completion(.success)
  }
  
  func addService(session: PeripheralManagerSession, service: MutableService, completion: @escaping (Result<Void, Error>) -> Void) {
    let pm = peripheralManager(session)
    Task {
      do {
        try await pm.addService(service: service)
        completion(.success)
      } catch {
        completion(.failure(error))
      }
    }
  }
  
  func removeService(session: PeripheralManagerSession, serviceUuid: String, completion: @escaping (Result<Void, Error>) -> Void) {
    let pm = peripheralManager(session)
    do {
      try pm.removeService(serviceUuid: serviceUuid)
      completion(.success)
    } catch {
      completion(.failure(error))
    }
  }
  
  func removeAllServices(session: PeripheralManagerSession, completion: @escaping (Result<Void, Error>) -> Void) {
    let pm = peripheralManager(session)
    pm.removeAllServices()
    completion(.success)
  }
  
  func respondToRequest(session: PeripheralManagerSession, requestId: Int64, result: AttResult, value: FlutterStandardTypedData?, completion: @escaping (Result<Void, Error>) -> Void) {
    let pm = peripheralManager(session)
    do {
      try pm.respondToRequest(requestId: requestId, result: result, value: value)
      completion(.success)
    } catch {
      completion(.failure(error))
    }
  }
  
  func updateValue(session: PeripheralManagerSession, serviceUuid: String, characteristicUuid: String, value: FlutterStandardTypedData, completion: @escaping (Result<Bool, Error>) -> Void) {
    let pm = peripheralManager(session)
    do {
      let result = try pm.updateValue(serviceUuid: serviceUuid, characteristicUuid: characteristicUuid, value: value)
      completion(.success(result))
    } catch {
      completion(.failure(error))
    }
  }
  
  // MARK: Async wrappers
  
  func discoverServices(session: PeripheralSession, serviceUuids: [String]?, completion: @escaping (Result<Void, Error>) -> Void) async {
    let central = centralManager(session.session)
    
    print("outer async discoverServices")
    
    do {
      try await central.discoverServices(identifier: session.peripheralIdentifier, serviceUuids: serviceUuids)
      completion(.success)
    } catch {
      completion(.failure(FlutterError()))
    }
  }
  
  func discoverCharacteristics(session: PeripheralSession, serviceUuid: String, characteristicUuids: [String]?, completion: @escaping (Result<Void, Error>) -> Void) async {
    let central = centralManager(session.session)
    
    print("outer async discoverCharacteristics")
      
    do {
      try await central.discoverCharacteristics(identifier: session.peripheralIdentifier, serviceUuid: serviceUuid, characteristicUuids: characteristicUuids)
      completion(.success)
    } catch {
      completion(.failure(FlutterError()))
    }
  }
  
  func readCharacteristic(session: PeripheralSession, serviceUuid: String, characteristicUuid: String, completion: @escaping (Result<FlutterStandardTypedData, Error>) -> Void) async {
    let central = centralManager(session.session)
    
    do {
      let value = try await central.readCharacteristic(identifier: session.peripheralIdentifier, serviceUuid: serviceUuid, characteristicUuid: characteristicUuid)
      completion(.success(FlutterStandardTypedData(bytes: value)))
    } catch {
      completion(.failure(FlutterError()))
    }
  }
  
  func writeCharacteristic(session: PeripheralSession, serviceUuid: String, characteristicUuid: String, value: FlutterStandardTypedData, withoutResponse: Bool, completion: @escaping (Result<Void, Error>) -> Void) async {
    let central = centralManager(session.session)
    
    do {
      try await central.writeCharacteristic(identifier: session.peripheralIdentifier, serviceUuid: serviceUuid, characteristicUuid: characteristicUuid, value: value.data, withoutResponse: withoutResponse)
      completion(.success)
    } catch {
      completion(.failure(FlutterError()))
    }
  }
  
  func observeCharacteristic(observe: Bool, session: PeripheralSession, serviceUuid: String, characteristicUuid: String, completion: @escaping (Result<Void, Error>) -> Void) async {
    let central = centralManager(session.session)
    
    do {
      try await central.observeCharacteristic(observe: observe, identifier: session.peripheralIdentifier, serviceUuid: serviceUuid, characteristicUuid: characteristicUuid)
      completion(.success)
    } catch {
      completion(.failure(FlutterError()))
    }
  }
  
  func readDescriptor(session: PeripheralSession, serviceUuid: String, characteristicUuid: String, descriptorUuid: String, completion: @escaping (Result<FlutterStandardTypedData, Error>) -> Void) async {
    let central = centralManager(session.session)
    
    do {
      let value = try await central.readDescriptor(identifier: session.peripheralIdentifier, serviceUuid: serviceUuid, characteristicUuid: characteristicUuid, descriptorUuid: descriptorUuid)
      completion(.success(FlutterStandardTypedData(bytes: value)))
    } catch {
      completion(.failure(FlutterError()))
    }
  }
  
  func writeDescriptor(session: PeripheralSession, serviceUuid: String, characteristicUuid: String, descriptorUuid: String, value: [Int64], completion: @escaping (Result<Void, Error>) -> Void) async {
//    let central = centralManager(session.session)
  }
  
  func readRssi(session: PeripheralSession, completion: @escaping (Result<Int64, Error>) -> Void) async {
    let central = centralManager(session.session)
    
    if let rssi = try? await central.readRssi(identifier: session.peripheralIdentifier) {
      completion(.success(rssi))
    } else {
      completion(.failure(FlutterError()))
    }
  }
}

extension Result where Success == Void {
  static var success: Result {
    return .success(())
  }
}

extension [Int64] {
  var data: Data {
    return Data(buffer: withUnsafeBufferPointer { $0 })
  }
}

extension PeripheralSession {
  var session: ClientSession {
    ClientSession(
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

extension CBCharacteristic {
  func toCharacteristic() -> Characteristic {
    return Characteristic(
      uuid: uuid.uuidString,
      value: value != nil ? FlutterStandardTypedData(bytes: value!) : nil
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
