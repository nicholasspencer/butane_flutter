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
  
  func identifier(_ peripheral: CBPeripheral) -> PeripheralSessionIdentifier {
    return PeripheralSessionIdentifier(identifier: peripheral.identifier.uuidString, clientIdentifier: identifier)
  }
  
  // MARK: Host API
  func state(completion: @escaping (Result<ClientState, Error>) -> Void) {
    let state = manager.state.managerState;
    completion(.success(state))
  }
  
  func scan(forServices: [String]?, completion: @escaping (Result<Void, Error>) -> Void) {
    let uuids: [CBUUID]? = forServices?.map({
      return CBUUID(string: $0)
    })
    
    manager.scanForPeripherals(withServices: uuids)
    
    completion(.success)
  }
  
  func cancelScan(completion: @escaping (Result<Void, Error>) -> Void) {
    
  }
  
  func peripherals(peripheralIdentifiers: [String]?, completion: @escaping (Result<[PeripheralData], Error>) -> Void) {
    
  }
  
  func connectedPeripherals(serviceUuids: [String]?, completion: @escaping (Result<[PeripheralData], Error>) -> Void) {
    
  }
  
  func connect(identifier: String, completion: @escaping (Result<Void, Error>) -> Void) {
    
  }
  
  func cancelConnection(identifier: String, completion: @escaping (Result<Void, Error>) -> Void) {
    
  }
  
  func discoverServices(identifier: String, serviceUuids: [String]?, completion: @escaping (Result<Void, Error>) -> Void) {
    
  }
  
  func services(identifier: String, completion: @escaping (Result<[ServiceData], Error>) -> Void) {
    
  }
  
  func discoverCharacteristics(identifier: String, serviceUuid: String, characteristicUuids: [String]?, completion: @escaping (Result<Void, Error>) -> Void) {
    
  }
  
  func characteristics(identifier: String, serviceUuid: String, completion: @escaping (Result<[CharacteristicData], Error>) -> Void) {
    
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
  
  func readRssi(identifier: String, completion: @escaping (Result<Int64, Error>) -> Void) {
    
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
      scanResult: ScanData(
          peripheral: PeripheralData(
            identifier: identifier(peripheral),
            name: peripheral.name
          ),
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
