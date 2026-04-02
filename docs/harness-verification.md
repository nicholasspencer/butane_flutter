# BLE Test Harness Verification Report

**Date:** 2026-04-02  
**macOS:** 26.3.1 (Tahoe, arm64)  
**Hardware:** Mac Studio (M-series, BCM_4388C2 Bluetooth)  
**Flutter:** 3.x (stable)

## Summary

The BLE test harness was integrated and partially verified on macOS.
Multiple integration issues were discovered and fixed. The harness
successfully completes through BLE advertising, but **BLE scanning
(central discovering peripheral) fails** due to a CoreBluetooth
platform limitation.

## Step Results

| Step | Result | Notes |
|------|--------|-------|
| Build harness app | ✅ PASS | Release build succeeds |
| Launch both instances | ✅ PASS | Two instances via `open -n` with env vars |
| WebSocket servers start | ✅ PASS | Both ports reachable |
| Coordinator connects | ✅ PASS | WS connections established |
| Check BLE state (central) | ✅ PASS | poweredOn after ~12s init |
| Check BLE state (peripheral) | ✅ PASS | poweredOn via peripheralManagerState |
| Set read response | ✅ PASS | Preconfigured value stored |
| Add service | ✅ PASS | GATT service with 2 characteristics |
| Start advertising | ✅ PASS | Peripheral advertising |
| Scan for peripheral | ❌ BLOCKED | CoreBluetooth loopback limitation |
| Connect | ⬜ SKIPPED | Depends on scan |
| Discover services | ⬜ SKIPPED | — |
| Discover characteristics | ⬜ SKIPPED | — |
| Read characteristic | ⬜ SKIPPED | — |
| Write characteristic | ⬜ SKIPPED | — |
| Subscribe + notification | ⬜ SKIPPED | — |
| Disconnect | ⬜ SKIPPED | — |

## Blocker: CoreBluetooth Loopback

macOS CoreBluetooth does **not** support BLE self-discovery (loopback)
on a single machine. When `CBCentralManager` scans and `CBPeripheralManager`
advertises on the same Bluetooth hardware, the central does not discover
the peripheral. This is a well-known Apple platform limitation.

**Impact:** The full end-to-end harness cannot complete on a single Mac.

**Resolution options:**
1. Use two physical Macs (or Mac + iOS device) — one as central, one as peripheral
2. Use a USB BLE dongle as a second adapter
3. Test on iOS Simulator (which uses simulated BLE)
4. Split the harness into per-role tests that can be run on separate devices

## Integration Fixes Made

1. **Plugin registration** — Added `butane_core_bluetooth` as direct dependency
   so Flutter generates proper plugin registrant (`8e92584`)

2. **App sandbox disabled** — Sandboxed apps require TCC Bluetooth approval
   which blocks automated testing. Disabled sandbox and added
   NSBluetoothAlwaysUsageDescription (`1136a69`)

3. **Runtime config** — Added `Platform.environment` fallback for ROLE and
   WS_PORT so a single build can launch as either role (`c789b96`)

4. **WebSocket protocol** — Fixed HarnessServer to include request ID in
   responses and extract params from command messages (`b53a1d3`)

5. **BLE state double-init** — Removed CentralManager from HarnessApp UI
   to avoid initializing both central and peripheral stacks (`c9ada97`)

6. **Peripheral state check** — PeripheralRole now uses
   `peripheralManagerState` instead of `clientState` which was routing
   through CentralManager (`51b0280`)

7. **Coordinator CLI** — Created `bin/coordinator.dart` entrypoint, fixed
   action name mismatches (camelCase → snake_case), added peripheral ID
   tracking, BLE state polling, and removed invalid characteristic value
   in add_service (`6e69181`)

8. **Launch script** — Rewrote `run_harness.sh` to build `butane_harness`
   (not example apps), use `open -n` for proper macOS app process
   registration, and use non-conflicting ports (`54dd20e`)

## Known Limitations

- CoreBluetooth BLE loopback not supported on single machine
- First CBPeripheralManager/CBCentralManager init takes ~12s to reach poweredOn
- macOS Tahoe (26.x) requires non-sandboxed build for automated BLE testing
- `open -n` required (direct binary launch doesn't deliver CB delegate callbacks)
