# Harness Command Reference

## Central Role Commands

All commands available when the harness app is running in `central` mode.

```mermaid
flowchart TD
    subgraph Commands["Central Role — Available Actions"]
        CS[check_state] --> CSR["Returns: { state: 'poweredOn' }"]
        SC[scan] --> SCR["Returns: { peripheral: { id, name } }"]
        CO[connect] --> COR["Returns: { connected: true }"]
        DC[disconnect] --> DCR["Returns: { disconnected: true }"]
        DS[discover_services] --> DSR["Returns: { services: [{uuid, isPrimary}] }"]
        DCH[discover_characteristics] --> DCHR["Returns: { characteristics: [{uuid}] }"]
        RC[read_characteristic] --> RCR["Returns: { value: 'base64...' }"]
        WC[write_characteristic] --> WCR["Returns: { written: true }"]
        SU[subscribe] --> SUR["Returns: { subscribed: true }\n+ ongoing notification events"]
    end

    style Commands fill:#16213e,stroke:#0f3460,color:#eee
```

### Command Parameters

| Action | Required Params | Optional Params |
|--------|----------------|-----------------|
| `check_state` | — | — |
| `scan` | — | `serviceUuids: string[]` |
| `connect` | `peripheralId: string` | — |
| `disconnect` | `peripheralId: string` | — |
| `discover_services` | `peripheralId: string` | `serviceUuids: string[]` |
| `discover_characteristics` | `peripheralId: string`, `serviceUuid: string` | `characteristicUuids: string[]` |
| `read_characteristic` | `peripheralId`, `serviceUuid`, `characteristicUuid` | — |
| `write_characteristic` | `peripheralId`, `serviceUuid`, `characteristicUuid`, `value` (base64) | `withoutResponse: bool` |
| `subscribe` | `peripheralId`, `serviceUuid`, `characteristicUuid` | — |

## Central Command State Machine

Commands must follow a specific order — you can't read a characteristic before discovering it.

```mermaid
stateDiagram-v2
    [*] --> Idle
    Idle --> Scanning: scan
    Scanning --> PeripheralFound: peripheral discovered
    PeripheralFound --> Connecting: connect
    Connecting --> Connected: connection established
    Connected --> ServicesDiscovered: discover_services
    ServicesDiscovered --> CharsDiscovered: discover_characteristics
    CharsDiscovered --> CharsDiscovered: read / write / subscribe
    CharsDiscovered --> Disconnecting: disconnect
    Connected --> Disconnecting: disconnect
    Disconnecting --> Idle: disconnected

    note right of Scanning
        Scan returns on first
        matching peripheral,
        then stops automatically.
    end note

    note right of CharsDiscovered
        Multiple read/write/subscribe
        operations can be performed
        before disconnecting.
    end note
```

## Peripheral Lookup Chain

The Central role maintains a cache of discovered peripherals and navigates the GATT hierarchy for each operation:

```mermaid
flowchart TD
    A["Command arrives\nperipheralId + serviceUuid + characteristicUuid"]
    A --> B["_findPeripheral(peripheralId)"]
    B -->|"found"| C["_findService(peripheral, serviceUuid)"]
    B -->|"not found"| E1["StateError:\nRun scan first"]
    C -->|"found"| D["_findCharacteristic(..., charUuid)"]
    C -->|"not found"| E2["StateError:\nRun discover_services first"]
    D -->|"found"| F["Execute operation\nread / write / observe"]
    D -->|"not found"| E3["StateError:\nRun discover_characteristics first"]

    style E1 fill:#8b0000,stroke:#ff4444,color:#eee
    style E2 fill:#8b0000,stroke:#ff4444,color:#eee
    style E3 fill:#8b0000,stroke:#ff4444,color:#eee
```

## Notification Subscription Management

```mermaid
flowchart TD
    SUB["subscribe command"] --> KEY["Build key:\nperipheralId:serviceUuid:charUuid"]
    KEY --> CHECK{"Existing\nsubscription?"}
    CHECK -->|"yes"| CANCEL["Cancel old subscription"]
    CHECK -->|"no"| CREATE
    CANCEL --> CREATE["characteristic.observe().listen()"]
    CREATE --> STORE["Store in _notificationSubscriptions"]
    CREATE --> FORWARD["Each notification →\nserver.sendEvent()"]

    DC["disconnect command"] --> CLEANUP["_cancelNotificationsForPeripheral()"]
    CLEANUP --> REMOVE["Cancel all subs matching\nperipheralId:*"]

    style FORWARD fill:#0d7377,stroke:#14ffec,color:#eee
```
