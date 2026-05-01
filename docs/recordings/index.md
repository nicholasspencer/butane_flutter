# Burn recordings — `ble_flow`

Screen recordings of the [`ble_flow`](../harness-verification.md) integration scenario run in both directions between a macOS host and a Pixel 7a. Each video stitches the two directions together at 8× speed with duplicate frames removed.

## Devices

| | Device | OS |
|---|---|---|
| macOS | Mac Studio (arm64) | macOS 26.4.1 |
| Android | Pixel 7a (`3A251JEHN03975`) | Android 16 (API 36) |

## Videos

| File | Platform | Resolution | Duration |
|---|---|---|---|
| [`macos_both_8x.mp4`](macos_both_8x.mp4) | macOS | 960×540 | 37s |
| [`android_both_8x.mp4`](android_both_8x.mp4) | Android | 540×1200 | 16s |

Both are H.264, no audio, 8× speed, VFR with mpdecimate (duplicate frames dropped). The macOS video plays peripheral direction first, then central. The Android video plays central direction first, then peripheral.

---

## Run 1 — Android central ↔ macOS peripheral

**Date:** 2026-04-30  
**Scenario:** `ble_flow`  
**Coordinator:** `central=adb:3A251JEHN03975 peripheral=local`

| Step | Result | Duration |
|---|---|---|
| Check BLE state (central) | ✓ | 9ms |
| Check BLE state (peripheral) | ✓ | 37ms |
| Set read response (peripheral) | ✓ | 4ms |
| Add service (peripheral) | ✓ | 12ms |
| Start advertising (peripheral) | ✓ | 17ms |
| Scan for peripheral (central) | ✓ | 1605ms |
| Connect to peripheral (central) | ✓ | 528ms |
| Discover services (central) | ✓ | 419ms |
| Discover characteristics (central) | ✓ | 120ms |
| Read characteristic (central) | ✓ | 57ms |
| Write characteristic (central) | ✓ | 59ms |
| Verify write (peripheral) | ✓ | 521ms |
| Subscribe to notifications (central) | ✓ | 169ms |
| Notification round-trip | ✓ | 50ms |
| Disconnect (central) | ✓ | 56ms |

**15/15 passed**

---

## Run 2 — macOS central ↔ Android peripheral

**Date:** 2026-05-01  
**Scenario:** `ble_flow`  
**Coordinator:** `central=local peripheral=adb:3A251JEHN03975`

| Step | Result | Duration |
|---|---|---|
| Check BLE state (central) | ✓ | 518ms |
| Check BLE state (peripheral) | ✓ | 22ms |
| Set read response (peripheral) | ✓ | 6ms |
| Add service (peripheral) | ✓ | 9ms |
| Start advertising (peripheral) | ✓ | 24ms |
| Scan for peripheral (central) | ✓ | 1879ms |
| Connect to peripheral (central) | ✓ | 538ms |
| Discover services (central) | ✓ | 422ms |
| Discover characteristics (central) | ✓ | 117ms |
| Read characteristic (central) | ✓ | 90ms |
| Write characteristic (central) | ✓ | 58ms |
| Verify write (peripheral) | ✓ | 511ms |
| Subscribe to notifications (central) | ✓ | 178ms |
| Notification round-trip | ✓ | 50ms |
| Disconnect (central) | ✓ | 57ms |

**15/15 passed**
