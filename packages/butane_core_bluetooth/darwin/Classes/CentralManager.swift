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

class CentralManager: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
  let identifier: String?
  
  let queue: dispatch_queue_t?
  
  let flutterApi: ButaneFlutterApi
  
  lazy var manager: CBCentralManager = CBCentralManager(delegate: self, queue: queue);
  
  init(identifier: String?, flutterApi: ButaneFlutterApi, queue: dispatch_queue_t?) {
    self.identifier = identifier;
    self.queue = queue;
    self.flutterApi = flutterApi
  }
  
  func session(_ peripheral: CBPeripheral) -> Session {
    return Session(peripheralIdentifier: peripheral.identifier.uuidString, clientIdentifier: identifier)
  }
  
  // MARK: Host API
  var state: ClientState {
    get {
      return manager.state.managerState;
    }
  }
  
  func scan(forServices: [String]?) {
    let uuids: [CBUUID]? = forServices?.map({
      return CBUUID(string: $0)
    })
    
    manager.scanForPeripherals(withServices: uuids)
  }
  
  func cancelScan() {
    
  }
  
  func peripherals(peripheralIdentifiers: [String]?) async throws -> [Peripheral] {
    return []
  }
  
  func connectedPeripherals(serviceUuids: [String]?) async throws -> [Peripheral] {
    return []
  }
  
  func connect(identifier: String) {
    guard
      let uuid = UUID(uuidString: identifier),
      let peripheral = peripherals[uuid] else {
      return
    }
    
    manager.connect(peripheral)
  }
  
  func cancelConnection(identifier: String) {
    
  }
  
  func connectionState(identifier: String) -> ConnectionState {
    guard
      let uuid = UUID(uuidString: identifier),
      let peripheral = peripherals[uuid] else {
      return .disconnected
    }
    
    return peripheral.state.connectionState
  }
  
  func discoverServices(identifier: String, serviceUuids: [String]?, completion: @escaping (Result<Void, Error>) -> Void) {
    
  }
  
  func services(identifier: String) -> [Service] {
    return []
  }
  
  func discoverCharacteristics(identifier: String, serviceUuid: String, characteristicUuids: [String]?, completion: @escaping (Result<Void, Error>) -> Void) {
    
  }
  
  func characteristics(identifier: String, serviceUuid: String) -> [Characteristic] {
    return []
  }
  
  func readCharacteristic(identifier: String, serviceUuid: String, characteristicUuid: String, completion: @escaping (Result<FlutterStandardTypedData, Error>) -> Void) {
    
  }
  
  func writeCharacteristic(identifier: String, serviceUuid: String, characteristicUuid: String, value: [Int64], withoutResponse: Bool, completion: @escaping (Result<Void, Error>) -> Void) {
    
  }
  
  func watchCharacteristic(identifier: String, serviceUuid: String, characteristicUuid: String, completion: @escaping (Result<Void, Error>) -> Void) {
    
  }
  
  func setNotification(identifier: String, serviceUuid: String, characteristicUuid: String, enabled: Bool, completion: @escaping (Result<Void, Error>) -> Void) {
    
  }
  
  func readDescriptor(identifier: String, serviceUuid: String, descriptorUuid: String, completion: @escaping (Result<[Int64], Error>) -> Void) {
    
  }
  
  func writeDescriptor(identifier: String, serviceUuid: String, descriptorUuid: String, value: [Int64], completion: @escaping (Result<Void, Error>) -> Void) {
    
  }
  
  var rssiContinuations: [CBPeripheral: [CheckedContinuation<Int64, Error>]] = [:]
  
  func readRssi(identifier: String) async throws -> Int64 {
    guard
      let uuid = UUID(uuidString: identifier),
      let peripheral = peripherals[uuid] else {
      throw FlutterError()
    }
    
    return try await withCheckedThrowingContinuation { continuation in
      var continuations = rssiContinuations[peripheral] ?? []
      continuations.append(continuation)
      rssiContinuations[peripheral] = continuations
      peripheral.readRSSI()
    }
    
  }
  
  func requestMtu(identifier: String, mtu: Int64, completion: @escaping (Result<Int64, Error>) -> Void) {
    
  }
  
  // MARK: Central Delegate
  
  var peripherals: [UUID: CBPeripheral] = [:]
  
  func onNativeResult(_: Result<Void, FlutterError>) {}
  
  public func centralManagerDidUpdateState(_ central: CBCentralManager) {
    flutterApi.onClientState(
      clientIdentifier: identifier,
      state: central.state.managerState,
      completion: onNativeResult
    )
  }
  
  public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
    peripheral.delegate = self
    peripherals[peripheral.identifier] = peripheral
    
    flutterApi.onScanResult(
      scanResult: ScanResult(
          peripheral: Peripheral(
            session: session(peripheral),
            name: peripheral.name,
            rssi: RSSI.int64Value,
            state: peripheral.state.connectionState
          ),
        advertisementData: AdvertisementData.init(advertisementData: advertisementData)
      ),
      completion: onNativeResult
    )
  }
  
  public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
    flutterApi.onConnectionState(
      peripheral: peripheral.toPeripheral(),
      state: .connected,
      completion: onNativeResult
    )
  }
  
  // Peripheral Delegate
  
  func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
    guard let continuations = rssiContinuations[peripheral] else {
      return;
    }
    
    rssiContinuations[peripheral] = nil
    
    for continuation in continuations {
      continuation.resume(returning: RSSI.int64Value)
    }
  }
}
