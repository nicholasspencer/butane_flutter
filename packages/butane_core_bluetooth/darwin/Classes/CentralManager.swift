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

class CentralManager: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
  let identifier: String?
  
  let restorationIdentifier: String?
  
  let queue: dispatch_queue_t?
  
  let flutterApi: ButaneFlutterApi
  
  lazy var manager: CBCentralManager = {
    if let restorationIdentifier = restorationIdentifier {
      return .init(delegate: self, queue: queue, options: [CBCentralManagerRestoredStateScanOptionsKey: restorationIdentifier])
    }
    return .init(delegate: self, queue: queue)
  }()
  
  init(identifier: String?, restorationIdentifier: String?, flutterApi: ButaneFlutterApi, queue: dispatch_queue_t?) {
    self.identifier = identifier
    self.restorationIdentifier = restorationIdentifier
    self.queue = queue
    self.flutterApi = flutterApi
  }
  
  func session(_ peripheral: CBPeripheral) -> PeripheralSession {
    return PeripheralSession(
      peripheralIdentifier: peripheral.identifier.uuidString,
      clientIdentifier: identifier
    )
  }
  
  // MARK: Host API

  var state: ClientState {
    return manager.state.managerState
  }
  
  func scan(forServices: [String]?) {
    let uuids: [CBUUID]? = forServices?.map {
      CBUUID(string: $0)
    }
    
    manager.scanForPeripherals(withServices: uuids)
  }
  
  func cancelScan() {
    manager.stopScan()
  }
  
  func peripherals(peripheralIdentifiers: [String]) -> [Peripheral] {
    let uuids: [UUID] = peripheralIdentifiers.map { UUID(uuidString: $0) }.compactMap { $0 }
    
    return manager.retrievePeripherals(withIdentifiers: uuids).map { $0.toPeripheral() }
  }
  
  func connectedPeripherals(serviceUuids: [String]) -> [Peripheral] {
    let uuids: [CBUUID] = serviceUuids.map { CBUUID(string: $0) }
    
    return manager.retrieveConnectedPeripherals(withServices: uuids).map { $0.toPeripheral() }
  }
  
  func connect(identifier: String) {
    guard
      let uuid = UUID(uuidString: identifier),
      let peripheral = peripherals[uuid]
    else {
      return
    }
    
    flutterApi.onConnectionState(
      peripheral: peripheral.toPeripheral(session: session(peripheral)),
      state: .connecting,
      completion: onNativeResult
    )
    
    manager.connect(peripheral)
  }
  
  func cancelConnection(identifier: String) {
    guard
      let uuid = UUID(uuidString: identifier),
      let peripheral = peripherals[uuid]
    else {
      return
    }
    
    flutterApi.onConnectionState(
      peripheral: peripheral.toPeripheral(session: session(peripheral)),
      state: .disconnecting,
      completion: onNativeResult
    )
    
    manager.cancelPeripheralConnection(peripheral)
  }
  
  func connectionState(identifier: String) -> ConnectionState {
    guard
      let uuid = UUID(uuidString: identifier),
      let peripheral = peripherals[uuid]
    else {
      return .disconnected
    }
    
    let state = peripheral.state.connectionState
    
    return state
  }
  
  func discoverServices(identifier: String, serviceUuids: [String]?) async throws {
    guard
      let uuid = UUID(uuidString: identifier),
      let peripheral = peripherals[uuid]
    else {
      return
    }
    
    let uuids = serviceUuids?.map { CBUUID(string: $0) }
    
    serviceDiscoveryContinuations[peripheral] = serviceDiscoveryContinuations[peripheral] ?? []
      
    return try await withCheckedThrowingContinuation { continuation in
      serviceDiscoveryContinuations[peripheral]?.append(continuation)
      peripheral.discoverServices(uuids)
    }
  }
  
  func services(identifier: String) -> [Service] {
    guard
      let uuid = UUID(uuidString: identifier),
      let peripheral = peripherals[uuid]
    else {
      return []
    }
    
    return peripheral.services?.map {
      Service(uuid: $0.uuid.uuidString, isPrimary: $0.isPrimary)
    } ?? []
  }
  
  func discoverCharacteristics(identifier: String, serviceUuid: String, characteristicUuids: [String]?) async throws {
    guard
      let uuid = UUID(uuidString: identifier),
      let peripheral = peripherals[uuid],
      let service = peripheral.services?.first(where: { $0.uuid == CBUUID(string: serviceUuid) })
    else {
      return
    }
      
    let uuids = characteristicUuids?.map { CBUUID(string: $0) }
    
    characteristicDiscoveryContinuations[peripheral] = characteristicDiscoveryContinuations[peripheral] ?? []
      
    return try await withCheckedThrowingContinuation { continuation in
      characteristicDiscoveryContinuations[peripheral]?.append(continuation)
      peripheral.discoverCharacteristics(uuids, for: service)
    }
  }
  
  func characteristics(identifier: String, serviceUuid: String) -> [Characteristic] {
    guard
      let uuid = UUID(uuidString: identifier),
      let peripheral = peripherals[uuid],
      let service = peripheral.services?.first(where: { $0.uuid == CBUUID(string: serviceUuid) })
    else {
      return []
    }
    
    return service.characteristics?.map {
      Characteristic(
        uuid: $0.uuid.uuidString,
        descriptors: $0.descriptors?.map {
          Descriptor(
            uuid: $0.uuid.uuidString,
            value: FlutterStandardTypedData(bytes: ($0.value as? Data? ?? Data())!)
          )
        }
      )
    } ?? []
  }
  
  func readCharacteristic(identifier: String, serviceUuid: String, characteristicUuid: String) async throws -> Data {
    guard
      let uuid = UUID(uuidString: identifier),
      let peripheral = peripherals[uuid],
      let service = peripheral.services?.first(where: { $0.uuid == CBUUID(string: serviceUuid) }),
      let characteristic = service.characteristics?.first(where: { $0.uuid == CBUUID(string: characteristicUuid) })
    else {
      // TODO: Throw
      return Data()
    }
    
    characteristicReadContinuations[characteristic] = characteristicReadContinuations[characteristic] ?? []
    
    return try await withCheckedThrowingContinuation { continuation in
      characteristicReadContinuations[characteristic]?.append(continuation)
      peripheral.readValue(for: characteristic)
    }
  }
  
  func writeCharacteristic(identifier: String, serviceUuid: String, characteristicUuid: String, value: Data, withoutResponse: Bool) async throws {
    guard
      let uuid = UUID(uuidString: identifier),
      let peripheral = peripherals[uuid],
      let service = peripheral.services?.first(where: { $0.uuid == CBUUID(string: serviceUuid) }),
      let characteristic = service.characteristics?.first(where: { $0.uuid == CBUUID(string: characteristicUuid) })
    else {
      return
    }
    
    if withoutResponse {
      peripheral.writeValue(
        value,
        for: characteristic,
        type: .withoutResponse
      )
      return
    }
    
    characteristicWriteContinuations[characteristic] = characteristicWriteContinuations[characteristic] ?? []
    
    return try await withCheckedThrowingContinuation { continuation in
      characteristicWriteContinuations[characteristic]?.append(continuation)
      peripheral.writeValue(
        value,
        for: characteristic,
        type: .withResponse
      )
    }
  }
  
  func watchCharacteristic(identifier: String, serviceUuid: String, characteristicUuid: String) async throws {}
  
  func setNotification(identifier: String, serviceUuid: String, characteristicUuid: String, enabled: Bool) async throws {}
  
  func readDescriptor(identifier: String, serviceUuid: String, characteristicUuid: String, descriptorUuid: String) async throws -> Data {
    guard
      let uuid = UUID(uuidString: identifier),
      let peripheral = peripherals[uuid],
      let service = peripheral.services?.first(where: { $0.uuid == CBUUID(string: serviceUuid) }),
      let characteristic = service.characteristics?.first(where: { $0.uuid == CBUUID(string: characteristicUuid) }),
      let descriptor = characteristic.descriptors?.first(where: { $0.uuid == CBUUID(string: descriptorUuid) })
    else {
      // TODO: Throw
      return Data()
    }
    
    descriptorReadContinuations[descriptor] = descriptorReadContinuations[descriptor] ?? []
    
    return try await withCheckedThrowingContinuation { continuation in
      descriptorReadContinuations[descriptor]?.append(continuation)
      peripheral.readValue(for: descriptor)
    }
  }
  
  func writeDescriptor(identifier: String, serviceUuid: String, characteristicUuid: String, descriptorUuid: String, value: Data) async throws {}
  
  func readRssi(identifier: String) async throws -> Int64 {
    guard
      let uuid = UUID(uuidString: identifier),
      let peripheral = peripherals[uuid]
    else {
      throw FlutterError()
    }
    
    rssiContinuations[peripheral] = rssiContinuations[peripheral] ?? []
    
    return try await withCheckedThrowingContinuation { continuation in
      rssiContinuations[peripheral]?.append(continuation)
      peripheral.readRSSI()
    }
  }
  
  func requestMtu(identifier: String, mtu: Int64) {}
  
  // MARK: Continuation storage
  
  var serviceDiscoveryContinuations: [CBPeripheral: [CheckedContinuation<Void, Error>]] = [:]
  
  var characteristicDiscoveryContinuations: [CBPeripheral: [CheckedContinuation<Void, Error>]] = [:]
  
  var rssiContinuations: [CBPeripheral: [CheckedContinuation<Int64, Error>]] = [:]
  
  var characteristicReadContinuations: [CBCharacteristic: [CheckedContinuation<Data, Error>]] = [:]
  
  var characteristicWriteContinuations: [CBCharacteristic: [CheckedContinuation<Void, Error>]] = [:]
  
  var descriptorReadContinuations: [CBDescriptor: [CheckedContinuation<Data, Error>]] = [:]
  
  var descriptorWriteContinuations: [CBDescriptor: [CheckedContinuation<Void, Error>]] = [:]
  
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
  
  public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
    peripheral.delegate = self
    peripherals[peripheral.identifier] = peripheral
    
    flutterApi.onScanResult(
      scanResult: ScanResult(
        peripheral: peripheral.toPeripheral(session: session(peripheral), rssi: RSSI),
        advertisementData: AdvertisementData(advertisementData: advertisementData)
      ),
      completion: onNativeResult
    )
  }
  
  public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
    flutterApi.onConnectionState(
      peripheral: peripheral.toPeripheral(session: session(peripheral)),
      state: .connected,
      completion: onNativeResult
    )
  }
  
  func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
    flutterApi.onConnectionState(
      peripheral: peripheral.toPeripheral(session: session(peripheral)),
      state: .disconnected,
      completion: onNativeResult
    )
  }
  
  // Peripheral Delegate
  
  func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
    guard let continuations = rssiContinuations[peripheral] else {
      return
    }
    
    rssiContinuations[peripheral] = nil
    
    for continuation in continuations {
      if let error = error {
        continuation.resume(throwing: error)
      } else {
        continuation.resume(returning: RSSI.int64Value)
      }
    }
  }
  
  func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
    guard let continuations = serviceDiscoveryContinuations[peripheral] else {
      return
    }
    
    serviceDiscoveryContinuations[peripheral] = nil
    
    for continuation in continuations {
      if let error = error {
        continuation.resume(throwing: error)
      } else {
        continuation.resume()
      }
    }
  }
  
  func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
    guard let continuations = characteristicDiscoveryContinuations[peripheral] else {
      return
    }
    
    characteristicDiscoveryContinuations[peripheral] = nil
    
    for continuation in continuations {
      if let error = error {
        continuation.resume(throwing: error)
      } else {
        continuation.resume()
      }
    }
  }
  
  func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
    flutterApi.onCharacteristicValue(
      peripheral: peripheral.toPeripheral(session: session(peripheral)),
      characteristic: characteristic.toCharacteristic(),
      value: FlutterStandardTypedData(bytes: characteristic.value ?? Data()),
      completion: onNativeResult
    )
    
    guard let continuations = characteristicReadContinuations[characteristic] else {
      return
    }
    
    characteristicReadContinuations[characteristic] = nil
    
    for continuation in continuations {
      if let error = error {
        continuation.resume(throwing: error)
      } else {
        continuation.resume(returning: characteristic.value ?? Data())
      }
    }
  }
  
  func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
    guard let continuations = characteristicWriteContinuations[characteristic] else {
      return
    }
    
    characteristicWriteContinuations[characteristic] = nil
    
    for continuation in continuations {
      if let error = error {
        continuation.resume(throwing: error)
      } else {
        continuation.resume()
      }
    }
  }
  
  func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
    
  }
}
