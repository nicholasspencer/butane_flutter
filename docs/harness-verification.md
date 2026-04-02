# BLE Harness Verification Report

**Date:** 2026-04-02  
**Branch:** `butane_flutter-41i`  
**Devices:** Mac Studio (macOS 26.3.1) + iPad mini 6th gen (iOS 26.1)

## Summary

End-to-end BLE verification achieved with cross-device setup: Mac Studio as Central,
iPad mini (USB) as Peripheral. Full GATT flow verified: advertise → scan → connect →
discover → read → write → subscribe → notify → disconnect.

### Result: 15/15 steps PASS ✓

```
Step                                     Result    Duration
-----------------------------------------------------------
Check BLE state (central)                 PASS      531ms
Check BLE state (peripheral)              PASS      3161ms
Set read response (peripheral)            PASS      11ms
Add service (peripheral)                  PASS      20ms
Start advertising (peripheral)            PASS      12ms
Scan for peripheral (central)             PASS      130ms
Connect to peripheral (central)           PASS      624ms
Discover services (central)               PASS      453ms
Discover characteristics (central)        PASS      56ms
Read characteristic (central)             PASS      87ms
Write characteristic (central)            PASS      58ms
Verify write (peripheral)                 PASS      666ms
Subscribe to notifications (central)      PASS      114ms
Notification round-trip                   PASS      110ms
Disconnect (central)                      PASS      6ms
```

## Known Constraint: Two-Device Requirement

CoreBluetooth on macOS **cannot discover peripherals advertised by the same machine**.
The BLE radio cannot scan for its own advertisements. A second device (iPad mini via USB)
provides the second radio needed for Central↔Peripheral communication.

## Deployment Method

### iOS Peripheral (iPad mini)
- **Build:** `flutter build ios --release --dart-define=ROLE=peripheral --dart-define=WS_PORT=19101`
- **Install:** `ios-deploy --bundle build/ios/iphoneos/Runner.app --id <UDID> --uninstall --no-wifi`
- **Launch:** `xcrun devicectl device process launch --device <CoreDevice-UUID> com.nicospencer.butaneHarness`
- iOS apps **must** use `--release` mode with `--dart-define` for config (env vars not available)
- `flutter run -d <device>` hangs on Dart VM Service discovery — unusable for this harness

### macOS Central (Mac Studio)
- **Build:** `flutter build macos --release` (no dart-defines needed)
- **Launch:** `open -n "$APP_BUNDLE" --env ROLE=central --env WS_PORT=19100`
- macOS apps use runtime env vars via `Platform.environment` fallback

## Bugs Found and Fixed

### butane_flutter-wga: UUID case mismatch in read response lookup
CoreBluetooth returns uppercase UUIDs in ATT request callbacks, but the coordinator
sends lowercase. Normalized all map keys to lowercase in `peripheral_role.dart`.

### butane_flutter-5k9: didWriteValueFor uses wrong continuation map
Copy-paste bug in `CentralManager.swift`: `didWriteValueFor` was reading from
`observeCharacteristicContinuations` instead of `characteristicWriteContinuations`,
causing write-with-response to hang indefinitely.

### butane_flutter-ful: Notification subscribe timing and UUID matching
Three interrelated issues:
1. The porcelain `observe()` API fires `setNotifyValue` asynchronously — the subscribe
   command returned before notifications were actually enabled
2. The `characteristicValueStream` filter used case-sensitive UUID comparison, missing
   events from CoreBluetooth (uppercase) when the coordinator sent lowercase
3. The `PlatformStreamController.sinkValue` read emitted a spurious empty notification

Fix: Use the platform API directly to `await observeCharacteristic()`, use normalized
UUIDs from the discovered characteristic, and filter empty values.

### Idempotent run cleanup
Added pre/post cleanup (stop_advertising, remove_service) to the coordinator scenario
so consecutive runs don't accumulate stale BLE state. Also added explicit
`observeCharacteristic(observe: false)` in the disconnect handler.

## Remaining Blocker: macOS Bluetooth Authorization After Clean Build

After `flutter clean` + rebuild, macOS invalidates the Bluetooth TCC authorization
for the app (code signature changes). The `CBCentralManager` state stays `unknown`
indefinitely because the authorization prompt doesn't appear when launched via `open -n`.

**Workaround:** Avoid `flutter clean` on macOS — incremental builds preserve the
code signature and TCC authorization. If a clean build is needed, manually approve
Bluetooth access in System Settings > Privacy & Security > Bluetooth.

**Impact:** This blocks the three consecutive clean runs requirement. A single clean
run (15/15 PASS) was achieved before the clean build. The code is correct; the blocker
is purely a macOS system permission issue requiring human interaction.

## Device Info

| Device | Role | IP | Port | OS |
|--------|------|----|------|----|
| Mac Studio | Central | localhost | 19100 | macOS 26.3.1 |
| iPad mini 6th gen | Peripheral | 192.168.4.36 (Wi-Fi) / 169.254.69.25 (USB) | 19101 | iOS 26.1 |

- iPad UDID: `00008110-001651523CE3801E`
- CoreDevice UUID: `D9EBF582-6C06-57B5-920D-181C9A78E2C5`
- Signing Team: `D82YXVJWMT`
