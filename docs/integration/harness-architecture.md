# Harness Architecture

## System Overview

The butane_flutter integration harness is a two-device BLE testing system. A **Coordinator CLI** orchestrates two instances of the same Flutter app — one running as a BLE **Central** and one as a BLE **Peripheral** — communicating test commands over WebSocket.

```mermaid
flowchart TB
    subgraph Coordinator["Coordinator CLI (Dart)"]
        SC[Scenario Runner]
        RC[Result Collector]
    end

    subgraph CentralApp["Harness App — Central Role"]
        CR[CentralRole]
        CM[CentralManager\n‹butane›]
        CS[HarnessServer\n‹WebSocket›]
    end

    subgraph PeripheralApp["Harness App — Peripheral Role"]
        PR[PeripheralRole]
        PM[PeripheralManager\n‹butane›]
        PS[HarnessServer\n‹WebSocket›]
    end

    Coordinator <-->|"WS :8710"| CS
    Coordinator <-->|"WS :8711"| PS
    CM <-.->|"BLE over-the-air"| PM

    style Coordinator fill:#1a1a2e,stroke:#e94560,color:#eee
    style CentralApp fill:#16213e,stroke:#0f3460,color:#eee
    style PeripheralApp fill:#16213e,stroke:#0f3460,color:#eee
```

## App Startup Flow

Both Central and Peripheral are the **same Flutter binary**, differentiated at launch via `--dart-define`:

```mermaid
flowchart TD
    A["flutter run -d macos\n--dart-define=ROLE=central\n--dart-define=WS_PORT=8710"] --> B[WidgetsFlutterBinding.ensureInitialized]
    B --> C[HarnessConfig.fromEnvironment]
    C --> D{config.role?}
    D -->|central| E[Create CentralRole]
    D -->|peripheral| F[Create PeripheralRole]
    E --> G[HarnessServer.start\nlocalhost:wsPort]
    F --> G
    G --> H[runApp — HarnessApp]
    H --> I[Display status UI\n+ log stream]
```

## Internal Component Relationships

```mermaid
classDiagram
    class HarnessConfig {
        +HarnessRole role
        +int wsPort
        +fromEnvironment()
    }

    class HarnessServer {
        +int port
        +Stream~Map~ commands
        +Stream~String~ statusStream
        +bool isConnected
        +start()
        +stop()
        +send(Map message)
        +sendEvent(String event, Map data)
        +onCommand(handler)
    }

    class HarnessLog {
        +Stream~String~ entries
        +add(String message)
        +dispose()
    }

    class CentralRole {
        -CentralManager _manager
        -Map~String,Peripheral~ _peripherals
        -Map~String,StreamSubscription~ _notificationSubscriptions
        +dispose()
    }

    class HarnessApp {
        +HarnessConfig config
        +HarnessServer server
        +HarnessLog log
    }

    HarnessApp --> HarnessConfig
    HarnessApp --> HarnessServer
    HarnessApp --> HarnessLog
    CentralRole --> HarnessServer : receives commands
    CentralRole --> HarnessLog : writes logs
    CentralRole --> CentralManager : BLE operations

    class CentralManager {
        <<butane>>
        +scan()
        +state
    }

    class Peripheral {
        <<butane>>
        +connect()
        +discoverServices()
        +services
    }

    CentralRole --> Peripheral : manages discovered
```

## WebSocket Protocol

All communication between the Coordinator and the Harness apps uses JSON over WebSocket.

```mermaid
flowchart LR
    subgraph Messages
        direction TB
        CMD["Command (Coordinator → App)\n{\n  action: 'scan',\n  serviceUuids: [...]\n}"]
        RES["Result (App → Coordinator)\n{\n  type: 'result',\n  action: 'scan',\n  success: true,\n  data: { peripheral: {...} }\n}"]
        EVT["Event (App → Coordinator)\n{\n  type: 'event',\n  event: 'notification',\n  peripheralId: '...',\n  value: 'base64...'\n}"]
    end

    CMD ~~~ RES ~~~ EVT
```

### Message Types

| Direction | Type | Purpose |
|-----------|------|---------|
| Coordinator → App | **Command** | Trigger a BLE operation (`action` field) |
| App → Coordinator | **Result** | Response to a command (`success` + `data` or `error`) |
| App → Coordinator | **Event** | Unsolicited push (e.g. BLE notification received) |

### Connection Rules

- Only **one** coordinator connection per app instance (subsequent connections are rejected)
- Commands are dispatched via `onCommand` handler — one handler at a time
- Results are sent automatically after command execution
