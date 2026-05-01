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
  
  var actors: [UUID: PeripheralActor] = [:]
  
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
      let actor = actors[uuid]
    else {
      return
    }
    
    let peripheral = actor.peripheral
    
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
      let actor = actors[uuid]
    else {
      return
    }
    
    let peripheral = actor.peripheral
    
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
      let actor = actors[uuid]
    else {
      return .disconnected
    }
    
    let peripheral = actor.peripheral
    
    let state = peripheral.state.connectionState
    
    return state
  }
  
  func discoverServices(identifier: String, serviceUuids: [String]?) async throws {
    guard
      let uuid = UUID(uuidString: identifier),
      let actor = actors[uuid]
    else {
      return
    }
    
    try await actor.discoverServices(serviceUuids: serviceUuids)
  }
  
  func services(identifier: String) -> [Service] {
    guard
      let uuid = UUID(uuidString: identifier),
      let actor = actors[uuid]
    else {
      return []
    }
    
    return actor.peripheral.services?.map {
      Service(uuid: $0.uuid.uuidString, isPrimary: $0.isPrimary)
    } ?? []
  }
  
  func discoverCharacteristics(identifier: String, serviceUuid: String, characteristicUuids: [String]?) async throws {
    guard
      let uuid = UUID(uuidString: identifier),
      let actor = actors[uuid]
    else {
      return
    }
    
    try await actor.discoverCharacteristics(serviceUuid: serviceUuid, characteristicUuids: characteristicUuids)
  }
  
  func characteristics(identifier: String, serviceUuid: String) -> [Characteristic] {
    guard
      let uuid = UUID(uuidString: identifier),
      let actor = actors[uuid],
      let service = actor.peripheral.services?.first(where: { $0.uuid == CBUUID(string: serviceUuid) })
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
      let actor = actors[uuid]
    else {
      // TODO: Throw
      return Data()
    }
    
    return try await actor.readCharacteristic(serviceUuid: serviceUuid, characteristicUuid: characteristicUuid)
  }
  
  func writeCharacteristic(identifier: String, serviceUuid: String, characteristicUuid: String, value: Data, withoutResponse: Bool) async throws {
    guard
      let uuid = UUID(uuidString: identifier),
      let actor = actors[uuid],
      let service = actor.peripheral.services?.first(where: { $0.uuid == CBUUID(string: serviceUuid) }),
      let characteristic = service.characteristics?.first(where: { $0.uuid == CBUUID(string: characteristicUuid) })
    else {
      return
    }
    
    let peripheral = actor.peripheral
    
    if withoutResponse {
      peripheral.writeValue(
        value,
        for: characteristic,
        type: .withoutResponse
      )
      return
    } else {
      return try await actor.writeCharacteristic(serviceUuid: serviceUuid, characteristicUuid: characteristicUuid, value: value, withoutResponse: false)
    }
  }
  
  func observeCharacteristic(observe: Bool, identifier: String, serviceUuid: String, characteristicUuid: String) async throws {
    guard
      let uuid = UUID(uuidString: identifier),
      let actor = actors[uuid]
    else {
      return
    }
    
    return try await actor.observeCharacteristic(observe: observe, serviceUuid: serviceUuid, characteristicUuid: characteristicUuid)
  }
  
  func readDescriptor(identifier: String, serviceUuid: String, characteristicUuid: String, descriptorUuid: String) async throws -> Data {
    guard
      let uuid = UUID(uuidString: identifier),
      let actor = actors[uuid]
    else {
      // TODO: Throw
      return Data()
    }
    
    return try await actor.readDescriptor(serviceUuid: serviceUuid, characteristicUuid: characteristicUuid, descriptorUuid: descriptorUuid)
  }
  
  func writeDescriptor(identifier: String, serviceUuid: String, characteristicUuid: String, descriptorUuid: String, value: Data) async throws {}
  
  func readRssi(identifier: String) async throws -> Int64 {
    guard
      let uuid = UUID(uuidString: identifier),
      let actor = actors[uuid]
    else {
      throw FlutterError()
    }
    
    return try await actor.rssi()
  }
  
  func requestMtu(identifier: String, mtu: Int64) {}
  
  // MARK: Central Delegate
  
  func onNativeResult(_: Result<Void, PigeonError>) {}
  
  public func centralManagerDidUpdateState(_ central: CBCentralManager) {
    flutterApi.onClientState(
      clientIdentifier: identifier,
      state: central.state.managerState,
      completion: onNativeResult
    )
  }
  
  public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
    guard actors.keys.contains(peripheral.identifier) == false else {
      return
    }
    
    peripheral.delegate = self
    actors[peripheral.identifier] = PeripheralActor(peripheral: peripheral, flutterApi: flutterApi)
    
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
  
  // MARK: Peripheral Delegate
  
  func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
    guard let actor = actors[peripheral.identifier] else {
      return
    }
    
    Task { await actor.didReadRSSI(RSSI, error: error) }
  }
  
  func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
    guard let actor = actors[peripheral.identifier] else {
      return
    }
      
    Task { await actor.didDiscoverServices(error: error) }
  }
  
  func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
    guard let actor = actors[peripheral.identifier] else {
      return
    }
    
    Task { await actor.didDiscoverCharacteristicsFor(service: service, error: error) }
  }
  
  func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
    flutterApi.onCharacteristicValue(
      peripheral: peripheral.toPeripheral(session: session(peripheral)),
      characteristic: characteristic.toCharacteristic(),
      value: FlutterStandardTypedData(bytes: characteristic.value ?? Data()),
      completion: onNativeResult
    )
    
    guard let actor = actors[peripheral.identifier] else {
      return
    }
    
    Task { await actor.didUpdateValueFor(characteristic: characteristic, error: error) }
  }
  
  func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
    guard let actor = actors[peripheral.identifier] else {
      return
    }
    
    Task { await actor.didWriteValueFor(characteristic: characteristic, error: error) }
  }
  
  func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
    guard let actor = actors[peripheral.identifier] else {
      return
    }
    
    Task { await actor.didUpdateNotificationStateFor(characteristic: characteristic, error: error) }
  }
  
  func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
    guard let actor = actors[peripheral.identifier] else {
      return
    }
    
    Task { await actor.didModifyServices(invalidatedServices: invalidatedServices) }
  }
}

// MARK: Peripheral Actor

actor PeripheralActor: Equatable {
  nonisolated let peripheral: CBPeripheral
  
  let flutterApi: ButaneFlutterApi
  
  init(peripheral: CBPeripheral, flutterApi: ButaneFlutterApi) {
    self.peripheral = peripheral
    self.flutterApi = flutterApi
  }
  
  static func == (lhs: PeripheralActor, rhs: PeripheralActor) -> Bool {
    lhs.peripheral == rhs.peripheral
  }
  
  func hash(into hasher: inout Hasher) {
    hasher.combine(peripheral)
  }
  
  // MARK: Peripheral API
  
  func discoverServices(serviceUuids: [String]?) async throws {
    let uuids = serviceUuids?.map { CBUUID(string: $0) }
    
    return try await withCheckedThrowingContinuation { continuation in
      print("discoverServices")
      serviceDiscoveryContinuations.append(continuation)
      peripheral.discoverServices(uuids)
    }
  }
  
  func discoverCharacteristics(serviceUuid: String, characteristicUuids: [String]?) async throws {
    guard
      let service = peripheral.services?.first(where: { $0.uuid == CBUUID(string: serviceUuid) })
    else {
      print("\(serviceUuid): discoverCharacteristics guard failed")
      return
    }
    
    print("\(service.uuid.uuidString): discoverCharacteristics")
      
    let uuids = characteristicUuids?.map { CBUUID(string: $0) }
    
    characteristicDiscoveryContinuations[service] = characteristicDiscoveryContinuations[service] ?? [];
      
    return try await withCheckedThrowingContinuation { continuation in
      print("\(service.uuid.uuidString): discoverCharacteristics continuation")
      characteristicDiscoveryContinuations[service]?.append(continuation)
      peripheral.discoverCharacteristics(uuids, for: service)
    }
  }
  
  func readCharacteristic(serviceUuid: String, characteristicUuid: String) async throws -> Data {
    guard
      let service = peripheral.services?.first(where: { $0.uuid == CBUUID(string: serviceUuid) }),
      let characteristic = service.characteristics?.first(where: { $0.uuid == CBUUID(string: characteristicUuid) }),
      characteristic.properties.contains(.read)
    else {
      // TODO: Throw
      return Data()
    }
    
    characteristicReadContinuations[characteristic] = characteristicReadContinuations[characteristic] ?? [];
    
    return try await withCheckedThrowingContinuation { continuation in
      characteristicReadContinuations[characteristic]?.append(continuation)
      peripheral.readValue(for: characteristic)
    }
  }
  
  func writeCharacteristic(serviceUuid: String, characteristicUuid: String, value: Data, withoutResponse: Bool) async throws {
    guard
      let service = peripheral.services?.first(where: { $0.uuid == CBUUID(string: serviceUuid) }),
      let characteristic = service.characteristics?.first(where: { $0.uuid == CBUUID(string: characteristicUuid) })
    else {
      return
    }
    
    characteristicWriteContinuations[characteristic] = characteristicWriteContinuations[characteristic] ?? [];
    
    return try await withCheckedThrowingContinuation { continuation in
      characteristicWriteContinuations[characteristic]?.append(continuation)
      peripheral.writeValue(
        value,
        for: characteristic,
        type: .withResponse
      )
    }
  }
  
  func observeCharacteristic(observe: Bool, serviceUuid: String, characteristicUuid: String) async throws {
    guard
      let service = peripheral.services?.first(where: { $0.uuid == CBUUID(string: serviceUuid) }),
      let characteristic = service.characteristics?.first(where: { $0.uuid == CBUUID(string: characteristicUuid) }),
      characteristic.properties.contains(.notify) || characteristic.properties.contains(.indicate)
    else {
      return
    }
    
    observeCharacteristicContinuations[characteristic] = observeCharacteristicContinuations[characteristic] ?? [];
    
    return try await withCheckedThrowingContinuation { continuation in
      observeCharacteristicContinuations[characteristic]?.append(continuation)
      peripheral.setNotifyValue(observe, for: characteristic)
    }
  }
  
  func readDescriptor(serviceUuid: String, characteristicUuid: String, descriptorUuid: String) async throws -> Data {
    guard
      let service = peripheral.services?.first(where: { $0.uuid == CBUUID(string: serviceUuid) }),
      let characteristic = service.characteristics?.first(where: { $0.uuid == CBUUID(string: characteristicUuid) }),
      let descriptor = characteristic.descriptors?.first(where: { $0.uuid == CBUUID(string: descriptorUuid) })
    else {
      // TODO: Throw
      return Data()
    }
    
    descriptorReadContinuations[characteristic] = descriptorReadContinuations[characteristic] ?? [];
    
    return try await withCheckedThrowingContinuation { continuation in
      descriptorReadContinuations[characteristic]?.append(continuation)
      peripheral.readValue(for: descriptor)
    }
  }
  
  func writeDescriptor(serviceUuid: String, characteristicUuid: String, descriptorUuid: String, value: Data) async throws {}
  
  func rssi() async throws -> Int64 {
    return try await withCheckedThrowingContinuation { continuation in
      rssiContinuations.append(continuation)
      peripheral.readRSSI()
    }
  }
  
  // MARK: Continuation storage
  
  var serviceDiscoveryContinuations: [CheckedContinuation<Void, Error>] = []
  
  var characteristicDiscoveryContinuations: [CBService:[CheckedContinuation<Void, Error>]] = [:]
  
  var rssiContinuations: [CheckedContinuation<Int64, Error>] = []
  
  var characteristicReadContinuations: [CBCharacteristic: [CheckedContinuation<Data, Error>]] = [:]
  
  lazy var characteristicWriteContinuations: [CBCharacteristic: [CheckedContinuation<Void, Error>]] = [:]
  
  var observeCharacteristicContinuations: [CBCharacteristic: [CheckedContinuation<Void, Error>]] = [:]
  
  var descriptorReadContinuations: [CBCharacteristic: [CheckedContinuation<Data, Error>]] = [:]
  
  var descriptorWriteContinuations: [CBCharacteristic: [CheckedContinuation<Void, Error>]] = [:]
  
  // MARK: Peripheral Delegate
  
  func didReadRSSI(_ RSSI: NSNumber, error: Error?) {
    for continuation in rssiContinuations {
      if let error = error {
        continuation.resume(throwing: error)
      } else {
        continuation.resume(returning: RSSI.int64Value)
      }
    }
    
    rssiContinuations.removeAll()
  }
  
  func didDiscoverServices(error: Error?) {
    print("didDiscoverServices has \(serviceDiscoveryContinuations.count)")
    
    for continuation in serviceDiscoveryContinuations {
      if let error = error {
        print("didDiscoverServices failed")
        continuation.resume(throwing: error)
      } else {
        print("didDiscoverServices")
        continuation.resume()
      }
    }
    
    print("didDiscoverServices purging \(serviceDiscoveryContinuations.count) continuations")
    
    serviceDiscoveryContinuations.removeAll()
  }
  
  func didDiscoverCharacteristicsFor(service: CBService, error: Error?) {
    guard let continuations = characteristicDiscoveryContinuations[service] else {
      return
    }
    
    print("didDiscoverCharacteristicsFor(\(service.uuid.uuidString)) has \(characteristicDiscoveryContinuations.count) continuations")
    
    for continuation in continuations {
      if let error = error {
        print("\(service.uuid.uuidString): didDiscoverCharacteristics failed")
        continuation.resume(throwing: error)
      } else {
        print("\(service.uuid.uuidString): didDiscoverCharacteristics")
        continuation.resume()
      }
    }
    
    print("didDiscoverCharacteristicsFor(\(service.uuid.uuidString)) purging \(characteristicDiscoveryContinuations.count) continuations")
    
    characteristicDiscoveryContinuations[service]?.removeAll()
  }
  
  func didUpdateValueFor(characteristic: CBCharacteristic, error: Error?) {
    guard let continuations = characteristicReadContinuations[characteristic] else {
      return
    }
    
    for continuation in continuations {
      if let error = error {
        continuation.resume(throwing: error)
      } else {
        continuation.resume(returning: characteristic.value ?? Data())
      }
    }
    
    characteristicReadContinuations[characteristic]?.removeAll()
  }
  
  func didWriteValueFor(characteristic: CBCharacteristic, error: Error?) {
    guard let continuations = characteristicWriteContinuations[characteristic] else {
      return
    }
    
    for continuation in continuations {
      if let error = error {
        continuation.resume(throwing: error)
      } else {
        continuation.resume()
      }
    }
    
    characteristicWriteContinuations[characteristic]?.removeAll()
  }
  
  func didUpdateNotificationStateFor(characteristic: CBCharacteristic, error: Error?) {
    guard let continuations = observeCharacteristicContinuations[characteristic] else {
      return
    }
    
    for continuation in continuations {
      if let error = error {
        continuation.resume(throwing: error)
      } else {
        continuation.resume()
      }
    }
    
    observeCharacteristicContinuations[characteristic]?.removeAll()
  }
  
  func didModifyServices(invalidatedServices: [CBService]) {
    print("invalidated services: \(invalidatedServices)")
  }
}
