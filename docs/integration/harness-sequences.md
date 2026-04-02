# Harness Sequence Diagrams

## Full BLE Integration Test Flow

End-to-end sequence showing the coordinator orchestrating a complete BLE test scenario: scan → connect → discover → read → write → subscribe → notify → disconnect.

```mermaid
sequenceDiagram
    participant C as Coordinator CLI
    participant CA as Central App
    participant BLE as BLE Radio
    participant PA as Peripheral App

    Note over C,PA: Phase 1 — Setup

    C->>PA: { action: "add_service", uuid: "180D",<br/>characteristics: [...] }
    PA->>PA: PeripheralManager.addService()
    PA-->>C: { type: "result", success: true }

    C->>PA: { action: "start_advertising",<br/>localName: "ButaneTest",<br/>serviceUuids: ["180D"] }
    PA->>BLE: Start BLE advertising
    PA-->>C: { type: "result", success: true }

    Note over C,PA: Phase 2 — Discovery & Connection

    C->>CA: { action: "scan",<br/>serviceUuids: ["180D"] }
    CA->>BLE: CentralManager.scan()
    BLE-->>CA: Peripheral discovered
    CA-->>C: { type: "result", success: true,<br/>data: { peripheral: { id, name } } }

    C->>CA: { action: "connect",<br/>peripheralId: "abc-123" }
    CA->>BLE: Peripheral.connect()
    BLE-->>PA: Central connected
    BLE-->>CA: Connection established
    CA->>CA: Wait for ConnectionState.connected
    CA-->>C: { type: "result", success: true }

    Note over C,PA: Phase 3 — Service Discovery

    C->>CA: { action: "discover_services" }
    CA->>BLE: Peripheral.discoverServices()
    BLE-->>CA: Services list
    CA-->>C: { type: "result", data: { services: [...] } }

    C->>CA: { action: "discover_characteristics",<br/>serviceUuid: "180D" }
    CA->>BLE: Service.discoverCharacteristics()
    BLE-->>CA: Characteristics list
    CA-->>C: { type: "result", data: { characteristics: [...] } }

    Note over C,PA: Phase 4 — Read / Write

    C->>CA: { action: "read_characteristic",<br/>serviceUuid: "180D",<br/>characteristicUuid: "2A37" }
    CA->>BLE: Characteristic.read()
    BLE-->>PA: Read request
    PA->>BLE: Respond with value
    BLE-->>CA: Value (bytes)
    CA-->>C: { type: "result", data: { value: "base64..." } }

    C->>CA: { action: "write_characteristic",<br/>characteristicUuid: "2A39",<br/>value: "AQ==" }
    CA->>BLE: Characteristic.write()
    BLE-->>PA: Write request
    PA->>BLE: Acknowledge
    BLE-->>CA: Write confirmed
    CA-->>C: { type: "result", data: { written: true } }

    Note over C,PA: Phase 5 — Notifications

    C->>CA: { action: "subscribe",<br/>characteristicUuid: "2A37" }
    CA->>BLE: Characteristic.observe()
    BLE-->>PA: Central subscribed
    CA-->>C: { type: "result", data: { subscribed: true } }

    PA->>BLE: updateValue("2A37", newData)
    BLE-->>CA: Notification (bytes)
    CA-->>C: { type: "event", event: "notification",<br/>characteristicUuid: "2A37",<br/>value: "base64..." }

    Note over C,PA: Phase 6 — Teardown

    C->>CA: { action: "disconnect",<br/>peripheralId: "abc-123" }
    CA->>CA: Cancel notification subscriptions
    CA->>BLE: Peripheral.cancelConnection()
    BLE-->>PA: Central disconnected
    CA-->>C: { type: "result", data: { disconnected: true } }
```

## WebSocket Connection Lifecycle

```mermaid
sequenceDiagram
    participant C as Coordinator
    participant S as HarnessServer

    Note over S: Server starts on localhost:port

    C->>S: WebSocket upgrade request
    S->>S: Accept connection<br/>(single client only)
    S-->>C: Connection established

    Note over C,S: Normal operation

    C->>S: JSON command
    S->>S: Decode → _commandController
    S->>S: _dispatchCommand(handler)
    S-->>C: { type: "result", ... }

    Note over C,S: Unsolicited events

    S-->>C: { type: "event", event: "notification", ... }

    Note over C,S: Second client rejected

    participant C2 as Another Client
    C2->>S: WebSocket upgrade request
    S->>C2: Close(1000, "Already connected")

    Note over C,S: Disconnect

    C->>S: Connection closed
    S->>S: _client = null<br/>Status: "Coordinator disconnected"
```

## Command Dispatch Flow

How a single command flows through the Central role:

```mermaid
sequenceDiagram
    participant WS as WebSocket
    participant HS as HarnessServer
    participant CR as CentralRole
    participant BLE as CentralManager / Peripheral

    WS->>HS: Raw JSON string
    HS->>HS: jsonDecode → Map
    HS->>HS: _commandController.add(message)
    HS->>CR: _commandHandler(command)

    CR->>CR: Switch on action field

    alt action = "scan"
        CR->>BLE: _manager.scan(forServices: [...])
        BLE-->>CR: ScanResult stream → first match
        CR->>CR: Cache peripheral in _peripherals map
        CR-->>HS: { peripheral: { id, name } }
    else action = "connect"
        CR->>CR: _findPeripheral(id)
        CR->>BLE: peripheral.connect()
        BLE-->>CR: stateStream → connected
        CR-->>HS: { connected: true }
    else action = "subscribe"
        CR->>CR: _findCharacteristic(...)
        CR->>BLE: characteristic.observe()
        CR->>CR: Store subscription
        Note over CR: Each notification →<br/>server.sendEvent()
        CR-->>HS: { subscribed: true }
    else unknown action
        CR-->>HS: { success: false, error: "Unknown action" }
    end

    HS->>HS: Wrap in result envelope
    HS->>WS: { type: "result", action, success, data }
```

## Error Handling Flow

```mermaid
sequenceDiagram
    participant C as Coordinator
    participant HS as HarnessServer
    participant CR as CentralRole

    C->>HS: { action: "connect", peripheralId: "unknown" }
    HS->>CR: _handleCommand(...)
    CR->>CR: _findPeripheral("unknown")
    CR--xCR: StateError: "No peripheral with ID"

    Note over HS: Handler threw — catch in _dispatchCommand

    HS-->>C: { type: "result",<br/>action: "connect",<br/>success: false,<br/>error: "StateError: No peripheral..." }
```

## Data Encoding Convention

All byte values (characteristic reads, writes, notifications) are encoded as **base64** strings in the WebSocket JSON protocol:

```mermaid
flowchart LR
    A["Raw bytes\n[0x00, 0x60]"] -->|base64Encode| B["'AGQ='"]
    B -->|WebSocket JSON| C["{ value: 'AGQ=' }"]
    C -->|base64Decode| D["Uint8List\n[0x00, 0x60]"]
```
