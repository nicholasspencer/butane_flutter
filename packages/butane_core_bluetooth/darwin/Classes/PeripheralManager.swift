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

class PeripheralManager: NSObject, CBPeripheralManagerDelegate {
  let identifier: String?

  let restorationIdentifier: String?

  let queue: DispatchQueue?

  let flutterApi: ButaneFlutterApi

  /// UUID string -> CBMutableService for lookup on remove/updateValue
  var services: [String: CBMutableService] = [:]

  /// requestId -> CBATTRequest for respondToRequest
  var pendingRequests: [Int64: CBATTRequest] = [:]

  /// Monotonic counter for assigning unique ATT request IDs
  var nextRequestId: Int64 = 1

  /// Continuations awaiting didAdd service callback
  var addServiceContinuations: [CBUUID: CheckedContinuation<Void, Error>] = [:]

  lazy var manager: CBPeripheralManager = {
    if let restorationIdentifier = restorationIdentifier {
      return .init(delegate: self, queue: queue, options: [CBPeripheralManagerOptionRestoreIdentifierKey: restorationIdentifier])
    }
    return .init(delegate: self, queue: queue)
  }()

  init(identifier: String?, restorationIdentifier: String?, flutterApi: ButaneFlutterApi, queue: DispatchQueue?) {
    self.identifier = identifier
    self.restorationIdentifier = restorationIdentifier
    self.queue = queue
    self.flutterApi = flutterApi
  }

  func onNativeResult(_: Result<Void, PigeonError>) {}

  // MARK: Host API

  var state: ClientState {
    return manager.state.managerState
  }

  func startAdvertising(localName: String?, serviceUuids: [String]?) {
    var advertisementData: [String: Any] = [:]

    if let localName = localName {
      advertisementData[CBAdvertisementDataLocalNameKey] = localName
    }

    if let serviceUuids = serviceUuids {
      advertisementData[CBAdvertisementDataServiceUUIDsKey] = serviceUuids.map { CBUUID(string: $0) }
    }

    manager.startAdvertising(advertisementData.isEmpty ? nil : advertisementData)
  }

  func stopAdvertising() {
    manager.stopAdvertising()
  }

  func addService(service: MutableService) async throws {
    let cbService = service.toCBMutableService()
    services[service.uuid] = cbService

    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      addServiceContinuations[cbService.uuid] = continuation
      manager.add(cbService)
    }
  }

  func removeService(serviceUuid: String) throws {
    guard let cbService = services[serviceUuid] else {
      throw PigeonError(
        code: "service-not-found",
        message: "No service found with UUID: \(serviceUuid)",
        details: nil
      )
    }

    manager.remove(cbService)
    services.removeValue(forKey: serviceUuid)
  }

  func removeAllServices() {
    manager.removeAllServices()
    services.removeAll()
  }

  func respondToRequest(requestId: Int64, result: AttResult, value: FlutterStandardTypedData?) throws {
    guard let request = pendingRequests[requestId] else {
      throw PigeonError(
        code: "request-not-found",
        message: "No pending ATT request found with ID: \(requestId)",
        details: nil
      )
    }

    if let value = value {
      request.value = value.data
    }

    manager.respond(to: request, withResult: result.toCBATTError())
    pendingRequests.removeValue(forKey: requestId)
  }

  func updateValue(serviceUuid: String, characteristicUuid: String, value: FlutterStandardTypedData) throws -> Bool {
    guard let cbService = services[serviceUuid] else {
      throw PigeonError(
        code: "service-not-found",
        message: "No service found with UUID: \(serviceUuid)",
        details: nil
      )
    }

    guard let characteristic = cbService.characteristics?.first(where: { $0.uuid == CBUUID(string: characteristicUuid) }) as? CBMutableCharacteristic else {
      throw PigeonError(
        code: "characteristic-not-found",
        message: "No characteristic found with UUID: \(characteristicUuid) in service: \(serviceUuid)",
        details: nil
      )
    }

    return manager.updateValue(value.data, for: characteristic, onSubscribedCentrals: nil)
  }

  // MARK: CBPeripheralManagerDelegate

  func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
    flutterApi.onPeripheralManagerState(
      clientIdentifier: identifier,
      state: peripheral.state.managerState,
      completion: onNativeResult
    )
  }

  func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
    // Resume the addService continuation
    if let continuation = addServiceContinuations.removeValue(forKey: service.uuid) {
      if let error = error {
        continuation.resume(throwing: error)
      } else {
        continuation.resume()
      }
    }

    // Also notify Flutter
    flutterApi.onServiceAdded(
      serviceUuid: service.uuid.uuidString,
      error: error?.localizedDescription,
      completion: onNativeResult
    )
  }

  func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
    let requestId = nextRequestId
    nextRequestId += 1
    pendingRequests[requestId] = request

    let attRequest = AttRequest(
      requestId: requestId,
      centralIdentifier: request.central.identifier.uuidString,
      characteristicUuid: request.characteristic.uuid.uuidString,
      serviceUuid: request.characteristic.service?.uuid.uuidString ?? "",
      offset: Int64(request.offset),
      value: request.value != nil ? FlutterStandardTypedData(bytes: request.value!) : nil
    )

    flutterApi.onReadRequest(request: attRequest, completion: onNativeResult)
  }

  func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
    var attRequests: [AttRequest] = []

    for request in requests {
      let requestId = nextRequestId
      nextRequestId += 1
      pendingRequests[requestId] = request

      attRequests.append(AttRequest(
        requestId: requestId,
        centralIdentifier: request.central.identifier.uuidString,
        characteristicUuid: request.characteristic.uuid.uuidString,
        serviceUuid: request.characteristic.service?.uuid.uuidString ?? "",
        offset: Int64(request.offset),
        value: request.value != nil ? FlutterStandardTypedData(bytes: request.value!) : nil
      ))
    }

    flutterApi.onWriteRequests(requests: attRequests, completion: onNativeResult)
  }

  func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
    flutterApi.onReadyToUpdateSubscribers(clientIdentifier: identifier, completion: onNativeResult)
  }
}

// MARK: - Conversion Helpers

extension MutableService {
  func toCBMutableService() -> CBMutableService {
    let cbService = CBMutableService(
      type: CBUUID(string: uuid),
      primary: isPrimary
    )

    cbService.characteristics = characteristics.compactMap { $0?.toCBMutableCharacteristic() }

    return cbService
  }
}

extension MutableCharacteristic {
  func toCBMutableCharacteristic() -> CBMutableCharacteristic {
    let cbProperties = properties?.toCBCharacteristicProperties() ?? []
    let cbPermissions = permissions?.toCBAttributePermissions() ?? []

    let cbCharacteristic = CBMutableCharacteristic(
      type: CBUUID(string: uuid),
      properties: cbProperties,
      value: value?.data,
      permissions: cbPermissions
    )

    cbCharacteristic.descriptors = descriptors?.compactMap { $0?.toCBMutableDescriptor() }

    return cbCharacteristic
  }
}

extension MutableDescriptor {
  func toCBMutableDescriptor() -> CBMutableDescriptor {
    return CBMutableDescriptor(
      type: CBUUID(string: uuid),
      value: value?.data
    )
  }
}

extension CharacteristicProperty {
  func toCBCharacteristicProperties() -> CBCharacteristicProperties {
    var props: CBCharacteristicProperties = []

    if broadcast { props.insert(.broadcast) }
    if read { props.insert(.read) }
    if writeWithoutResponse { props.insert(.writeWithoutResponse) }
    if write { props.insert(.write) }
    if notify { props.insert(.notify) }
    if indicate { props.insert(.indicate) }
    if authenticatedSignedWrites { props.insert(.authenticatedSignedWrites) }
    if extendedProperties { props.insert(.extendedProperties) }
    if notifyEncryptionRequired { props.insert(.notifyEncryptionRequired) }
    if indicateEncryptionRequired { props.insert(.indicateEncryptionRequired) }

    return props
  }
}

extension CharacteristicPermission {
  func toCBAttributePermissions() -> CBAttributePermissions {
    var perms: CBAttributePermissions = []

    if readable { perms.insert(.readable) }
    if writeable { perms.insert(.writeable) }
    if readEncryptionRequired { perms.insert(.readEncryptionRequired) }
    if writeEncryptionRequired { perms.insert(.writeEncryptionRequired) }

    return perms
  }
}

extension AttResult {
  func toCBATTError() -> CBATTError.Code {
    switch self {
    case .success:
      return .success
    case .invalidHandle:
      return .invalidHandle
    case .readNotPermitted:
      return .readNotPermitted
    case .writeNotPermitted:
      return .writeNotPermitted
    case .invalidOffset:
      return .invalidOffset
    case .attributeNotFound:
      return .attributeNotFound
    case .unlikelyError:
      return .unlikelyError
    }
  }
}
