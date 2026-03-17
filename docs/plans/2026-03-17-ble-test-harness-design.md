# BLE Test Harness — Design Document

> **Approach:** macOS-First Bootstrap (Approach C)

## Problem

butane_flutter has no real BLE tests. CoreBluetooth doesn't work in the iOS Simulator, so testing the actual BLE stack requires two physical devices. No existing framework (Patrol, Maestro, Appium) solves multi-device BLE orchestration.

## Solution

Build a custom two-device test harness using Flutter for both the Central and Peripheral sides, orchestrated by a Dart CLI coordinator. Start on macOS where both apps can run on the same machine (CoreBluetooth API is identical on macOS and iOS), giving us CI without needing physical phones.

## Architecture

```
┌──────────────────────────────────────────────────────────┐
│                   Coordinator CLI                         │
│              (Dart CLI — packages/butane_harness)         │
│                                                           │
│  ┌───────────────┐   WebSocket    ┌───────────────────┐  │
│  │  Instance A    │◄────────────►│   Instance B       │  │
│  │  (Central)     │  Sync/Signal  │  (Peripheral)      │  │
│  │  Flutter App   │               │  Flutter App       │  │
│  │  via butane    │               │  via butane         │  │
│  │  CentralMgr    │               │  PeripheralMgr     │  │
│  └───────────────┘               └───────────────────┘  │
│                                                           │
│  macOS: two processes on same machine                     │
│  iOS:   two phones connected via USB                      │
└──────────────────────────────────────────────────────────┘
```

## Deliverables

### 1. Peripheral Manager APIs in butane (the foundation)

**Pigeon API additions (`api.dart`):**

Host API (Dart→Swift):
- `peripheralManagerState()` → `ClientState`
- `startAdvertising(localName, serviceUuids)` → `void`
- `stopAdvertising()` → `void`
- `addService(uuid, isPrimary, characteristics[])` → `void`
- `removeService(uuid)` → `void`
- `removeAllServices()` → `void`
- `respondToRequest(requestId, result, value)` → `void`
- `updateValue(serviceUuid, characteristicUuid, value)` → `bool`

Flutter API (Swift→Dart):
- `onPeripheralManagerState(state)`
- `onServiceAdded(serviceUuid, error?)`
- `onReadRequest(requestId, centralId, characteristicUuid, offset)`
- `onWriteRequests(requests[{requestId, centralId, characteristicUuid, value, offset}])`
- `onCentralSubscribed(centralId, characteristicUuid)`
- `onCentralUnsubscribed(centralId, characteristicUuid)`
- `onReadyToUpdateSubscribers()`

**Platform Interface additions (`interface.dart`):**
- Mirror the Pigeon API as abstract methods
- Add streams: `peripheralManagerStateStream`, `readRequestStream`, `writeRequestsStream`, `subscriptionStream`

**Swift implementation (`PeripheralManager.swift`):**
- New file mirroring `CentralManager.swift` pattern
- Wraps `CBPeripheralManager` + `CBPeripheralManagerDelegate`
- Same `#if os(iOS)/#elseif os(macOS)` conditional compilation

**Dart porcelain (`peripheral_manager.dart`):**
- Fill in the empty `PeripheralManager` class
- Methods: `startAdvertising`, `stopAdvertising`, `addService`, streams for requests
- Stream-based API for incoming read/write requests

### 2. Test Harness Flutter App

- Lives in `packages/butane_harness/` (or `packages/butane/example/` enhanced)
- Single app, role selected via environment/args: `--role=central|peripheral`
- Embeds a lightweight WebSocket server (for coordinator commands)
- **Peripheral mode:** Advertises configurable services, responds to reads/writes per coordinator instructions
- **Central mode:** Scans, connects, performs operations per coordinator instructions
- Reports results (pass/fail/error + timing) back to coordinator

### 3. Coordinator CLI

- Lives in `packages/butane_harness/` as a Dart CLI entrypoint
- Launches two macOS Flutter app instances (or connects to pre-launched iOS apps)
- Orchestrates test scenarios via WebSocket:
  1. Tell Peripheral: "add service X with characteristics Y, Z" → wait for confirmation
  2. Tell Peripheral: "start advertising" → wait for confirmation
  3. Tell Central: "scan for service X" → wait for discovery
  4. Tell Central: "connect to peripheral" → wait for connection
  5. Tell Central: "read characteristic Y" → verify value
  6. Tell Central: "write to characteristic Z" → verify acknowledgement
  7. Tell Central: "subscribe to notifications on Y" → verify notifications arrive
  8. Tell Central: "disconnect" → verify clean disconnection
- Collects results, prints summary, exits 0/1

## Phasing

| Phase | What | Depends On |
|-------|------|------------|
| 1 | Peripheral Manager Pigeon API + codegen | Nothing |
| 2 | Platform Interface additions | Phase 1 |
| 3 | CoreBluetooth PeripheralManager.swift | Phase 1 |
| 4 | Dart porcelain PeripheralManager | Phase 2, 3 |
| 5 | Test Harness Flutter app (both roles) | Phase 4 |
| 6 | Coordinator CLI + test scenarios | Phase 5 |
| 7 | CI integration (macOS) | Phase 6 |
| 8 | iOS device support (additive) | Phase 7 |

## Key Decisions

- **Flutter for Peripheral harness** — enables future Android/cross-platform testing, drives Peripheral Manager API development
- **macOS first** — same CoreBluetooth API, no phone tethering needed, CI-friendly
- **WebSocket signaling** — simple, works on all platforms, coordinator is the hub
- **Single app, dual role** — less code to maintain, same binary on both sides
- **Coordinator as CLI** — scriptable, CI-friendly, no UI needed
