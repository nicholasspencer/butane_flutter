# BLE Test Harness — Implementation Plan

> **REQUIRED:** Follow the executing-plans skill to implement this plan task-by-task.

**Goal:** Build a macOS-first BLE integration test harness for butane_flutter, including Peripheral Manager APIs and a coordinator-driven two-app test system.

**Architecture:** Flutter plugin with Pigeon-based platform channels. Peripheral Manager mirrors the existing Central Manager pattern. A coordinator CLI launches two Flutter app instances (one Central, one Peripheral) and orchestrates test scenarios via WebSocket.

**Tech Stack:** Dart, Flutter, Swift (CoreBluetooth), Pigeon, WebSocket (`dart:io`/`web_socket_channel`)

**Design Doc:** `docs/plans/2026-03-17-ble-test-harness-design.md`

---

## Phase 1: Peripheral Manager Pigeon API

### Task 1: Define Peripheral Manager data models in Pigeon

**Files:**
- Modify: `packages/butane_platform_interface/pigeons/api.dart`

**Step 1: Add new Pigeon data classes for Peripheral Manager**

Add these classes after the existing `CharacteristicProperty` class (before the `@HostApi()` annotation):

```dart
/// Represents an ATT request from a connected central.
class AttRequest {
  AttRequest({
    required this.requestId,
    required this.centralIdentifier,
    required this.characteristicUuid,
    required this.serviceUuid,
    this.offset = 0,
    this.value,
  });

  /// Unique identifier for this request, used to respond.
  final int requestId;

  /// Identifier of the central that sent the request.
  final String centralIdentifier;

  /// UUID of the characteristic being read/written.
  final String characteristicUuid;

  /// UUID of the service containing the characteristic.
  final String serviceUuid;

  /// Byte offset into the characteristic value.
  final int offset;

  /// Value being written (null for read requests).
  final Uint8List? value;
}

/// Result code for responding to ATT requests.
enum AttResult {
  success,
  invalidHandle,
  readNotPermitted,
  writeNotPermitted,
  invalidOffset,
  attributeNotFound,
  unlikelyError,
}

/// A mutable service definition for the peripheral manager to advertise.
class MutableService {
  MutableService({
    required this.uuid,
    this.isPrimary = true,
    this.characteristics = const [],
  });

  final String uuid;
  final bool isPrimary;
  final List<MutableCharacteristic?> characteristics;
}

/// A mutable characteristic definition for a mutable service.
class MutableCharacteristic {
  MutableCharacteristic({
    required this.uuid,
    this.properties,
    this.value,
    this.descriptors = const [],
  });

  final String uuid;
  final CharacteristicProperty? properties;
  final Uint8List? value;
  final List<MutableDescriptor?> descriptors;
}

/// A mutable descriptor definition for a mutable characteristic.
class MutableDescriptor {
  MutableDescriptor({
    required this.uuid,
    this.value,
  });

  final String uuid;
  final Uint8List? value;
}

/// A session identifier for the peripheral manager.
class PeripheralManagerSession {
  PeripheralManagerSession({
    this.clientIdentifier,
  });

  final String? clientIdentifier;
}
```

**Step 2: Add Peripheral Manager methods to ButaneHostApi**

Replace the `/// "Peripheral" APIs.` comment in `ButaneHostApi` with:

```dart
  /// "Peripheral" APIs.

  @async
  ClientState peripheralManagerState({
    PeripheralManagerSession? session,
  });

  @async
  void startAdvertising({
    PeripheralManagerSession? session,
    String? localName,
    List<String>? serviceUuids,
  });

  @async
  void stopAdvertising({
    PeripheralManagerSession? session,
  });

  @async
  void addService({
    PeripheralManagerSession? session,
    required MutableService service,
  });

  @async
  void removeService({
    PeripheralManagerSession? session,
    required String serviceUuid,
  });

  @async
  void removeAllServices({
    PeripheralManagerSession? session,
  });

  @async
  void respondToRequest({
    required int requestId,
    required AttResult result,
    Uint8List? value,
  });

  @async
  bool updateValue({
    PeripheralManagerSession? session,
    required String serviceUuid,
    required String characteristicUuid,
    required Uint8List value,
  });
```

**Step 3: Add Peripheral Manager callbacks to ButaneFlutterApi**

Replace the `/// "Peripheral" APIs.` comment in `ButaneFlutterApi` with:

```dart
  /// "Peripheral Manager" APIs.

  void onPeripheralManagerState(
    String? clientIdentifier,
    ClientState state,
  );

  void onServiceAdded(
    String serviceUuid,
    String? error,
  );

  void onReadRequest(
    AttRequest request,
  );

  void onWriteRequests(
    List<AttRequest?> requests,
  );

  void onCentralSubscribed(
    String centralIdentifier,
    String characteristicUuid,
  );

  void onCentralUnsubscribed(
    String centralIdentifier,
    String characteristicUuid,
  );

  void onReadyToUpdateSubscribers();
```

**Step 4: Run Pigeon codegen**

```bash
cd packages/butane_platform_interface
dart run pigeon --input pigeons/api.dart
```

Expected: Generated files updated in `lib/src/channels/api.g.dart` and Swift `Api.gen.swift`.

**Step 5: Commit**

```bash
git add -A
git commit -m "feat(pigeon): add Peripheral Manager API definitions"
```

---

### Task 2: Add Peripheral Manager to Platform Interface

**Files:**
- Modify: `packages/butane_platform_interface/lib/src/interface/interface.dart`
- Modify: `packages/butane_platform_interface/lib/src/channels/api.dart` (the channel implementation)

**Step 1: Add abstract methods to `ButanePlatformInterface`**

Replace the `/// TODO The platform-specific implementation of [PeripheralManager].` comment with:

```dart
  /// Peripheral Manager APIs

  Future<ClientState> peripheralManagerState([
    PeripheralManagerSession? session,
  ]);

  Stream<ClientState> peripheralManagerStateStream([
    PeripheralManagerSession? session,
  ]);

  Future<void> startAdvertising({
    PeripheralManagerSession? session,
    String? localName,
    List<String>? serviceUuids,
  });

  Future<void> stopAdvertising({
    PeripheralManagerSession? session,
  });

  Future<void> addService({
    PeripheralManagerSession? session,
    required MutableService service,
  });

  Future<void> removeService({
    PeripheralManagerSession? session,
    required String serviceUuid,
  });

  Future<void> removeAllServices({
    PeripheralManagerSession? session,
  });

  Future<void> respondToRequest({
    required int requestId,
    required AttResult result,
    Uint8List? value,
  });

  Future<bool> updateValue({
    PeripheralManagerSession? session,
    required String serviceUuid,
    required String characteristicUuid,
    required Uint8List value,
  });

  Stream<AttRequest> readRequestStream([
    PeripheralManagerSession? session,
  ]);

  Stream<List<AttRequest>> writeRequestsStream([
    PeripheralManagerSession? session,
  ]);
```

**Step 2: Add `PeripheralManagerSession` and `AttRequest`/`AttResult` to the interface models**

Add after the existing `CharacteristicProperty` class:

```dart
final class PeripheralManagerSession {
  const PeripheralManagerSession({
    this.clientIdentifier,
  });

  final String? clientIdentifier;
}

final class AttRequest {
  const AttRequest({
    required this.requestId,
    required this.centralIdentifier,
    required this.characteristicUuid,
    required this.serviceUuid,
    this.offset = 0,
    this.value,
  });

  final int requestId;
  final String centralIdentifier;
  final String characteristicUuid;
  final String serviceUuid;
  final int offset;
  final Uint8List? value;
}

enum AttResult {
  success,
  invalidHandle,
  readNotPermitted,
  writeNotPermitted,
  invalidOffset,
  attributeNotFound,
  unlikelyError,
}

final class MutableService {
  const MutableService({
    required this.uuid,
    this.isPrimary = true,
    this.characteristics = const [],
  });

  final String uuid;
  final bool isPrimary;
  final List<MutableCharacteristic> characteristics;
}

final class MutableCharacteristic {
  const MutableCharacteristic({
    required this.uuid,
    this.properties,
    this.value,
    this.descriptors = const [],
  });

  final String uuid;
  final CharacteristicProperty? properties;
  final Uint8List? value;
  final List<MutableDescriptor> descriptors;
}

final class MutableDescriptor {
  const MutableDescriptor({
    required this.uuid,
    this.value,
  });

  final String uuid;
  final Uint8List? value;
}
```

**Step 3: Update the channel implementation to forward Peripheral Manager calls**

In `packages/butane_platform_interface/lib/src/channels/api.dart`, add method implementations that forward to the generated Pigeon host API. Follow the same pattern as the existing Central Manager forwarding.

**Step 4: Verify it compiles**

```bash
cd packages/butane_platform_interface
dart analyze
```

**Step 5: Commit**

```bash
git add -A
git commit -m "feat(platform_interface): add Peripheral Manager abstract API"
```

---

## Phase 2: CoreBluetooth Peripheral Manager (Swift)

### Task 3: Create PeripheralManager.swift

**Files:**
- Create: `packages/butane_core_bluetooth/darwin/Classes/PeripheralManager.swift`

**Step 1: Implement the CBPeripheralManager wrapper**

Create a new file following the same structure as `CentralManager.swift`:

```swift
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
  let queue: dispatch_queue_t?
  let flutterApi: ButaneFlutterApi

  // Track ATT requests by ID for responding later
  private var pendingRequests: [Int64: CBATTRequest] = [:]
  private var nextRequestId: Int64 = 0

  // Track added services
  private var services: [CBUUID: CBMutableService] = [:]

  lazy var manager: CBPeripheralManager = {
    return CBPeripheralManager(delegate: self, queue: queue)
  }()

  init(identifier: String?, flutterApi: ButaneFlutterApi, queue: dispatch_queue_t?) {
    self.identifier = identifier
    self.queue = queue
    self.flutterApi = flutterApi
  }

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
    manager.startAdvertising(advertisementData)
  }

  func stopAdvertising() {
    manager.stopAdvertising()
  }

  func addService(_ service: MutableService) {
    let cbService = service.toCBMutableService()
    services[cbService.uuid] = cbService
    manager.add(cbService)
  }

  func removeService(uuid: String) {
    let cbuuid = CBUUID(string: uuid)
    if let service = services[cbuuid] {
      manager.remove(service)
      services.removeValue(forKey: cbuuid)
    }
  }

  func removeAllServices() {
    manager.removeAllServices()
    services.removeAll()
  }

  func respondToRequest(requestId: Int64, result: AttResult, value: FlutterStandardTypedData?) {
    guard let request = pendingRequests.removeValue(forKey: requestId) else { return }
    if let value = value {
      request.value = value.data
    }
    manager.respond(to: request, withResult: result.toCBATTError())
  }

  func updateValue(serviceUuid: String, characteristicUuid: String, value: FlutterStandardTypedData) -> Bool {
    let serviceId = CBUUID(string: serviceUuid)
    let charId = CBUUID(string: characteristicUuid)

    guard let service = services[serviceId],
          let characteristic = service.characteristics?.first(where: { $0.uuid == charId }) as? CBMutableCharacteristic else {
      return false
    }

    return manager.updateValue(value.data, for: characteristic, onSubscribedCentrals: nil)
  }

  // MARK: CBPeripheralManagerDelegate

  func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
    flutterApi.onPeripheralManagerState(
      clientIdentifier: identifier,
      state: peripheral.state.managerState
    ) { _ in }
  }

  func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
    flutterApi.onServiceAdded(
      serviceUuid: service.uuid.uuidString,
      error: error?.localizedDescription
    ) { _ in }
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
      offset: Int64(request.offset)
    )

    flutterApi.onReadRequest(request: attRequest) { _ in }
  }

  func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
    let attRequests: [AttRequest] = requests.enumerated().map { index, request in
      let requestId = nextRequestId
      nextRequestId += 1
      pendingRequests[requestId] = request

      return AttRequest(
        requestId: requestId,
        centralIdentifier: request.central.identifier.uuidString,
        characteristicUuid: request.characteristic.uuid.uuidString,
        serviceUuid: request.characteristic.service?.uuid.uuidString ?? "",
        offset: Int64(request.offset),
        value: request.value != nil ? FlutterStandardTypedData(bytes: request.value!) : nil
      )
    }

    flutterApi.onWriteRequests(requests: attRequests) { _ in }
  }

  func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
    flutterApi.onCentralSubscribed(
      centralIdentifier: central.identifier.uuidString,
      characteristicUuid: characteristic.uuid.uuidString
    ) { _ in }
  }

  func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
    flutterApi.onCentralUnsubscribed(
      centralIdentifier: central.identifier.uuidString,
      characteristicUuid: characteristic.uuid.uuidString
    ) { _ in }
  }

  func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
    flutterApi.onReadyToUpdateSubscribers { _ in }
  }
}

// MARK: Extensions

extension MutableService {
  func toCBMutableService() -> CBMutableService {
    let service = CBMutableService(
      type: CBUUID(string: uuid),
      primary: isPrimary
    )
    service.characteristics = characteristics.compactMap { $0?.toCBMutableCharacteristic() }
    return service
  }
}

extension MutableCharacteristic {
  func toCBMutableCharacteristic() -> CBMutableCharacteristic {
    var cbProperties: CBCharacteristicProperties = []
    if let props = properties {
      if props.read { cbProperties.insert(.read) }
      if props.write { cbProperties.insert(.write) }
      if props.writeWithoutResponse { cbProperties.insert(.writeWithoutResponse) }
      if props.notify { cbProperties.insert(.notify) }
      if props.indicate { cbProperties.insert(.indicate) }
      if props.broadcast { cbProperties.insert(.broadcast) }
    }

    var permissions: CBAttributePermissions = []
    if let props = properties {
      if props.read { permissions.insert(.readable) }
      if props.write || props.writeWithoutResponse { permissions.insert(.writeable) }
    }

    let characteristic = CBMutableCharacteristic(
      type: CBUUID(string: uuid),
      properties: cbProperties,
      value: value != nil ? Data(value!) : nil,
      permissions: permissions
    )
    characteristic.descriptors = descriptors.compactMap { $0?.toCBMutableDescriptor() }
    return characteristic
  }
}

extension MutableDescriptor {
  func toCBMutableDescriptor() -> CBMutableDescriptor {
    // CBMutableDescriptor only supports CBUUID.characteristicUserDescriptionString
    // and CBUUID.characteristicFormatString
    return CBMutableDescriptor(
      type: CBUUID(string: uuid),
      value: value != nil ? Data(value!) : nil
    )
  }
}

extension AttResult {
  func toCBATTError() -> CBATTError.Code {
    switch self {
    case .success: return .success
    case .invalidHandle: return .invalidHandle
    case .readNotPermitted: return .readNotPermitted
    case .writeNotPermitted: return .writeNotPermitted
    case .invalidOffset: return .invalidOffset
    case .attributeNotFound: return .attributeNotFound
    case .unlikelyError: return .unlikelyError
    }
  }
}
```

**Step 2: Wire PeripheralManager into ButaneCoreBluetoothPlugin**

In `ButaneCoreBluetoothPlugin.swift`, add:

```swift
// Add property
var peripheralManagers: [String?: PeripheralManager] = [:]

// Add accessor method
func peripheralManager(_ session: PeripheralManagerSession?) -> PeripheralManager {
  if let manager = peripheralManagers[session?.clientIdentifier] {
    return manager
  }
  let manager = PeripheralManager(
    identifier: session?.clientIdentifier,
    flutterApi: flutterApi,
    queue: nil
  )
  peripheralManagers[session?.clientIdentifier] = manager
  return manager
}
```

Then implement all the Peripheral Manager protocol methods, forwarding to the `peripheralManager(_:)` accessor. Follow the same pattern as the Central Manager methods.

**Step 3: Verify it compiles on macOS**

```bash
cd packages/butane_core_bluetooth/example
flutter build macos
```

**Step 4: Commit**

```bash
git add -A
git commit -m "feat(core_bluetooth): implement CBPeripheralManager wrapper"
```

---

## Phase 3: Dart Porcelain Layer

### Task 4: Implement PeripheralManager porcelain

**Files:**
- Modify: `packages/butane/lib/src/porcelain/services/peripheral_manager.dart`
- Modify: `packages/butane/lib/src/porcelain/porcelain.dart` (may need new model parts)

**Step 1: Fill in PeripheralManager class**

```dart
part of '../porcelain.dart';

/// A service used from a "Peripheral" perspective to advertise
/// and interact with centrals.
base class PeripheralManager extends PeerManager<Central> {
  PeripheralManager({
    super.clientIdentifier,
    @visibleForTesting super.platform,
  });

  @protected
  api.PeripheralManagerSession get peripheralManagerSession =>
      api.PeripheralManagerSession(clientIdentifier: clientIdentifier);

  /// Current state of the peripheral manager.
  Future<PeerManagerState> get peripheralManagerState async {
    final state = await platform.peripheralManagerState(peripheralManagerSession);
    return PeerManagerState.fromApi(state);
  }

  /// Stream of peripheral manager state changes.
  Stream<PeerManagerState> get peripheralManagerStateStream {
    return platform
        .peripheralManagerStateStream(peripheralManagerSession)
        .map(PeerManagerState.fromApi);
  }

  /// Start advertising with the given local name and service UUIDs.
  Future<void> startAdvertising({
    String? localName,
    List<UuidIdentifier>? serviceUuids,
  }) {
    return platform.startAdvertising(
      session: peripheralManagerSession,
      localName: localName,
      serviceUuids: serviceUuids?.toStrings().toList(),
    );
  }

  /// Stop advertising.
  Future<void> stopAdvertising() {
    return platform.stopAdvertising(session: peripheralManagerSession);
  }

  /// Add a service to the peripheral manager's GATT database.
  Future<void> addService(api.MutableService service) {
    return platform.addService(
      session: peripheralManagerSession,
      service: service,
    );
  }

  /// Remove a service by UUID.
  Future<void> removeService(String serviceUuid) {
    return platform.removeService(
      session: peripheralManagerSession,
      serviceUuid: serviceUuid,
    );
  }

  /// Remove all services.
  Future<void> removeAllServices() {
    return platform.removeAllServices(session: peripheralManagerSession);
  }

  /// Respond to an incoming read or write request.
  Future<void> respondToRequest({
    required int requestId,
    required api.AttResult result,
    Uint8List? value,
  }) {
    return platform.respondToRequest(
      requestId: requestId,
      result: result,
      value: value,
    );
  }

  /// Update the value of a characteristic and notify subscribed centrals.
  /// Returns true if the update was queued, false if the queue is full.
  Future<bool> updateValue({
    required String serviceUuid,
    required String characteristicUuid,
    required Uint8List value,
  }) {
    return platform.updateValue(
      session: peripheralManagerSession,
      serviceUuid: serviceUuid,
      characteristicUuid: characteristicUuid,
      value: value,
    );
  }

  /// Stream of incoming read requests.
  Stream<api.AttRequest> get readRequests {
    return platform.readRequestStream(peripheralManagerSession);
  }

  /// Stream of incoming write request batches.
  Stream<List<api.AttRequest>> get writeRequests {
    return platform.writeRequestsStream(peripheralManagerSession);
  }

  @override
  void dispose() {
    stopAdvertising();
    removeAllServices();
    super.dispose();
  }
}
```

**Step 2: Verify it compiles**

```bash
cd packages/butane
dart analyze
```

**Step 3: Commit**

```bash
git add -A
git commit -m "feat(butane): implement PeripheralManager porcelain layer"
```

---

## Phase 4: Test Harness Flutter App

### Task 5: Create the harness app scaffold

**Files:**
- Create: `packages/butane_harness/` (new Flutter app package)

**Step 1: Create Flutter app**

```bash
cd packages
flutter create --org com.butane --platforms macos,ios butane_harness
```

**Step 2: Add dependencies to `pubspec.yaml`**

```yaml
dependencies:
  flutter:
    sdk: flutter
  butane:
    path: ../butane
  web_socket_channel: ^3.0.0
  args: ^2.4.0
```

**Step 3: Add BLE entitlements for macOS**

In `macos/Runner/DebugProfile.entitlements` and `Release.entitlements`:

```xml
<key>com.apple.security.device.bluetooth</key>
<true/>
```

In `macos/Runner/Info.plist`:

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>BLE test harness needs Bluetooth for integration testing</string>
```

Same for `ios/Runner/Info.plist`:

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>BLE test harness needs Bluetooth for integration testing</string>
<key>NSBluetoothPeripheralUsageDescription</key>
<string>BLE test harness needs to act as a BLE peripheral</string>
```

**Step 4: Implement the harness app**

Create `lib/main.dart` with:
- Parse `--role=central|peripheral` from args (or env var `BUTANE_ROLE`)
- Parse `--port=XXXX` for WebSocket server port
- Launch a WebSocket server on the given port
- Display role + connection status on screen (minimal UI)
- Listen for coordinator commands:
  - **Peripheral commands:** `add_service`, `start_advertising`, `stop_advertising`, `respond_to_request`
  - **Central commands:** `scan`, `connect`, `disconnect`, `discover_services`, `read_characteristic`, `write_characteristic`, `subscribe`
- Execute commands using butane's CentralManager or PeripheralManager
- Report results back via WebSocket as JSON: `{"command": "...", "status": "ok|error", "data": {...}}`

**Step 5: Verify it builds for macOS**

```bash
cd packages/butane_harness
flutter build macos
```

**Step 6: Commit**

```bash
git add -A
git commit -m "feat(harness): create BLE test harness Flutter app"
```

---

### Task 6: Implement Central role in harness

**Files:**
- Modify: `packages/butane_harness/lib/`

**Step 1: Create `lib/src/central_role.dart`**

Implements all Central-side BLE operations triggered by WebSocket commands:
- `scan` → Start scanning, return discovered peripherals
- `connect` → Connect to a peripheral by identifier
- `discover_services` → Discover services on connected peripheral
- `read_characteristic` → Read a characteristic value
- `write_characteristic` → Write a value to a characteristic
- `subscribe` → Enable notifications on a characteristic, forward received values
- `disconnect` → Disconnect from peripheral

Each command returns a JSON result via WebSocket.

**Step 2: Commit**

```bash
git add -A
git commit -m "feat(harness): implement central role"
```

---

### Task 7: Implement Peripheral role in harness

**Files:**
- Modify: `packages/butane_harness/lib/`

**Step 1: Create `lib/src/peripheral_role.dart`**

Implements all Peripheral-side BLE operations triggered by WebSocket commands:
- `add_service` → Add a GATT service with characteristics (configurable properties: read/write/notify)
- `start_advertising` → Start advertising with local name and service UUIDs
- `stop_advertising` → Stop advertising
- `set_characteristic_value` → Pre-set the value to return on read requests
- Auto-responds to read requests with configured values
- Auto-responds to write requests with success (stores written values)
- Forwards subscription/unsubscription events to coordinator

**Step 2: Commit**

```bash
git add -A
git commit -m "feat(harness): implement peripheral role"
```

---

## Phase 5: Coordinator CLI

### Task 8: Create the coordinator CLI

**Files:**
- Create: `packages/butane_harness/bin/coordinator.dart`

**Step 1: Implement the coordinator**

A Dart CLI that:

1. **Parses args:** `--central-port`, `--peripheral-port`, `--scenario` (default: `full`)
2. **Connects** to both harness app instances via WebSocket
3. **Runs test scenarios** as sequential command/response exchanges:

```dart
// Example: full BLE flow scenario
Future<void> runFullScenario() async {
  // 1. Peripheral: add test service
  await peripheral.send({
    'command': 'add_service',
    'uuid': '0000180D-0000-1000-8000-00805F9B34FB', // Heart Rate
    'characteristics': [
      {
        'uuid': '00002A37-0000-1000-8000-00805F9B34FB', // HR Measurement
        'properties': {'notify': true, 'read': true},
        'value': [0x00, 0x60], // initial value: 96 bpm
      },
      {
        'uuid': '00002A39-0000-1000-8000-00805F9B34FB', // HR Control Point
        'properties': {'write': true},
      },
    ],
  });

  // 2. Peripheral: start advertising
  await peripheral.send({
    'command': 'start_advertising',
    'localName': 'ButaneTest',
    'serviceUuids': ['0000180D-0000-1000-8000-00805F9B34FB'],
  });

  // 3. Central: scan
  final scanResult = await central.send({
    'command': 'scan',
    'serviceUuids': ['0000180D-0000-1000-8000-00805F9B34FB'],
    'timeout': 10,
  });

  // 4. Central: connect
  await central.send({
    'command': 'connect',
    'peripheralId': scanResult['peripheralId'],
  });

  // 5. Central: discover services
  await central.send({'command': 'discover_services'});

  // 6. Central: read characteristic
  final readResult = await central.send({
    'command': 'read_characteristic',
    'serviceUuid': '0000180D-...',
    'characteristicUuid': '00002A37-...',
  });
  assert(readResult['value'] == [0x00, 0x60]);

  // 7. Central: write characteristic
  await central.send({
    'command': 'write_characteristic',
    'serviceUuid': '0000180D-...',
    'characteristicUuid': '00002A39-...',
    'value': [0x01],
  });

  // 8. Central: subscribe to notifications
  await central.send({
    'command': 'subscribe',
    'serviceUuid': '0000180D-...',
    'characteristicUuid': '00002A37-...',
  });

  // 9. Peripheral: send notification
  await peripheral.send({
    'command': 'update_value',
    'serviceUuid': '0000180D-...',
    'characteristicUuid': '00002A37-...',
    'value': [0x00, 0x65], // 101 bpm
  });

  // 10. Central: verify notification received
  // (received via subscription stream)

  // 11. Central: disconnect
  await central.send({'command': 'disconnect'});
}
```

4. **Reports results** with timing and pass/fail per step
5. **Exits** with code 0 (all pass) or 1 (any fail)

**Step 2: Add a launch script**

Create `tool/run_harness.sh`:

```bash
#!/bin/bash
set -e

CENTRAL_PORT=${CENTRAL_PORT:-8710}
PERIPHERAL_PORT=${PERIPHERAL_PORT:-8711}

echo "=== BLE Test Harness ==="
echo "Launching peripheral (port $PERIPHERAL_PORT)..."
cd packages/butane_harness
flutter run -d macos --dart-define=BUTANE_ROLE=peripheral --dart-define=BUTANE_PORT=$PERIPHERAL_PORT &
PERIPHERAL_PID=$!

echo "Launching central (port $CENTRAL_PORT)..."
flutter run -d macos --dart-define=BUTANE_ROLE=central --dart-define=BUTANE_PORT=$CENTRAL_PORT &
CENTRAL_PID=$!

echo "Waiting for apps to start..."
sleep 10

echo "Running coordinator..."
dart run packages/butane_harness/bin/coordinator.dart \
  --central-port=$CENTRAL_PORT \
  --peripheral-port=$PERIPHERAL_PORT \
  --scenario=full

EXIT_CODE=$?

kill $PERIPHERAL_PID $CENTRAL_PID 2>/dev/null || true
exit $EXIT_CODE
```

**Step 3: Commit**

```bash
git add -A
git commit -m "feat(harness): add coordinator CLI and launch script"
```

---

## Phase 6: Integration & CI

### Task 9: End-to-end verification on macOS

**Step 1: Run the full harness manually**

```bash
cd ~/development/com.nicospencer/butane_flutter
./tool/run_harness.sh
```

**Step 2: Fix any issues discovered**

Debug using coordinator output + macOS Console.app for CoreBluetooth logs.

**Step 3: Commit any fixes**

```bash
git add -A
git commit -m "fix(harness): resolve integration issues from first run"
```

---

### Task 10: Add Nordic CoreBluetooth Mock for simulator unit tests

This is a separate workstream for fast CI without hardware. Create an issue for it:

```bash
bd create "Integrate Nordic CoreBluetooth Mock for simulator unit tests" \
  --description="Add IOS-BLE-Mock (Nordic) to butane_core_bluetooth for CBCentralManager/CBPeripheral mocking in simulator. Enables unit tests without physical devices." \
  -t feature -p 2
```

---

### Task 11: iOS device support (future)

This is additive on top of the macOS harness. Create an issue:

```bash
bd create "Add iOS device support to BLE test harness" \
  --description="Extend coordinator to deploy and launch harness app on two physical iOS devices via xcodebuild. Requires USB-connected iPhones." \
  -t feature -p 3 --deps discovered-from:task-9
```

---

## Summary

| Task | What | Est. Complexity |
|------|------|----------------|
| 1 | Pigeon API definitions + codegen | Medium |
| 2 | Platform Interface abstract methods | Medium |
| 3 | CBPeripheralManager Swift wrapper | High |
| 4 | Dart PeripheralManager porcelain | Medium |
| 5 | Harness app scaffold | Low |
| 6 | Central role implementation | Medium |
| 7 | Peripheral role implementation | Medium |
| 8 | Coordinator CLI + launch script | Medium |
| 9 | End-to-end verification | Variable |
| 10 | Nordic Mock (future issue) | Backlog |
| 11 | iOS device support (future issue) | Backlog |

**Critical path:** Tasks 1 → 2 → 3 → 4 → 5 → 6+7 (parallel) → 8 → 9
