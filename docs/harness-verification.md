# BLE Harness Verification Report

## Summary

End-to-end BLE verification completed on **2026-04-02** using macOS (Central) and iPad mini (Peripheral) with the butane harness and coordinator.

**Result: 15/15 steps PASS ✓**

## Environment

| Component | Details |
|-----------|---------|
| Central Host | Mac Studio (macOS 26.3.1, arm64) |
| Central Role | `flutter run -d macos` (debug) |
| Peripheral Device | iPad mini 6 (iOS 26.1, arm64e) |
| Peripheral Device ID | `00008110-001651523CE3801E` |
| Peripheral IP | `192.168.4.36` (Wi-Fi) |
| Central WS Port | `19100` (localhost) |
| Peripheral WS Port | `19101` (192.168.4.36) |
| Signing Team | `D82YXVJWMT` |

## Test Results

```
Step                                     Result    Duration
-----------------------------------------------------------
Check BLE state (central)                 PASS      525ms
Check BLE state (peripheral)              PASS      604ms
Set read response (peripheral)            PASS      24ms
Add service (peripheral)                  PASS      33ms
Start advertising (peripheral)            PASS      14ms
Scan for peripheral (central)             PASS      78ms
Connect to peripheral (central)           PASS      581ms
Discover services (central)               PASS      450ms
Discover characteristics (central)        PASS      88ms
Read characteristic (central)             PASS      58ms
Write characteristic (central)            PASS      59ms
Verify write (peripheral)                 PASS      587ms
Subscribe to notifications (central)      PASS      102ms
Notification round-trip                   PASS      51ms
Disconnect (central)                      PASS      57ms

Results: 15/15 passed

ALL STEPS PASSED ✓
```

## BLE Flow Verified

1. **check_state** — Both central and peripheral report `poweredOn`
2. **set_read_response** — Peripheral stores preconfigured read value ("BUTANE" base64)
3. **add_service** — Peripheral adds GATT service with read/write + notify characteristics
4. **start_advertising** — Peripheral advertises with service UUID
5. **scan** — Central discovers peripheral by service UUID
6. **connect** — Central establishes BLE connection
7. **discover_services** — Central finds test service on peripheral
8. **discover_characteristics** — Central finds both characteristics
9. **read_characteristic** — Central reads "BUTANE" value correctly
10. **write_characteristic** — Central writes "HELLO" to peripheral
11. **verify_write** — Peripheral confirms received "HELLO"
12. **subscribe** — Central subscribes to notify characteristic
13. **notification_round_trip** — Peripheral sends "NOTIFIED", central receives it
14. **disconnect** — Clean BLE disconnection

## Test Service UUIDs

- Service: `12345678-1234-5678-1234-56789abcdef0`
- Read/Write Characteristic: `12345678-1234-5678-1234-56789abcdef1`
- Notify Characteristic: `12345678-1234-5678-1234-56789abcdef2`

## How to Run

### Prerequisites

1. **macOS Bluetooth TCC Authorization**: The macOS harness app must be authorized for Bluetooth access in System Settings > Privacy & Security > Bluetooth. This requires manual one-time approval when the app first requests BLE access.

2. **iPad Bluetooth Permission**: The iOS app must have Bluetooth permission granted. This persists across `flutter run` invocations (no reinstall needed).

### Launch Sequence

**Step 1: Launch macOS central (via tmux for persistent TTY)**
```bash
tmux new-session -d -s butane_macos \
  "cd packages/butane_harness && flutter run -d macos \
    --dart-define=ROLE=central --dart-define=WS_PORT=19100"
```

**Step 2: Wait for macOS WS**
```bash
while ! nc -z localhost 19100; do sleep 1; done
```

**Step 3: Launch iPad peripheral (via tmux)**
```bash
tmux new-session -d -s butane_ipad \
  "cd packages/butane_harness && flutter run -d 00008110-001651523CE3801E \
    --dart-define=ROLE=peripheral --dart-define=WS_PORT=19101"
```

**Step 4: Wait for iPad WS**
```bash
while ! nc -z 192.168.4.36 19101; do sleep 1; done
```

**Step 5: Run coordinator**
```bash
dart run packages/butane_coordinator/bin/coordinator.dart \
  --central-port 19100 --peripheral-port 19101 \
  --host localhost --peripheral-host 192.168.4.36 \
  --timeout 30 --runs 3
```

### Important Notes

- **Use tmux** for `flutter run` sessions — they need a real TTY to stay alive
- **Do NOT run two `flutter run` commands** from the same project directory simultaneously without tmux — the second build will kill the first
- **Use `--runs N`** on the coordinator for consecutive passes — this avoids app restart between runs
- **Do NOT reinstall** the iOS app between cycles — Bluetooth permission gets wiped
- The coordinator supports `--runs N` for N consecutive passes in a single session

## Error Forwarding

Flutter errors are forwarded to the coordinator via WebSocket as unsolicited events:
```json
{"type": "event", "event": "error", "message": "<error>", "stackTrace": "<trace>"}
```

The coordinator prints error events inline:
```
[CENTRAL ERROR] <error message>
[PERIPHERAL ERROR] <error message>
```

This was implemented in `main.dart` using `FlutterError.onError` and `PlatformDispatcher.instance.onError`.

## Known Issues

1. **macOS TCC Bluetooth Authorization**: The standalone macOS binary requires manual Bluetooth authorization via System Settings. Apps launched through `flutter run` inherit the debug TCC bypass, but standalone execution requires explicit permission. If check_state returns `unauthorized` or `unknown`, authorize the app in System Settings > Privacy & Security > Bluetooth.

2. **flutter run TTY Requirement**: `flutter run` sessions die quickly (~30s) when launched without a proper TTY. Use `tmux` to provide a persistent terminal.

3. **Same-directory flutter run Conflict**: Two `flutter run` instances from the same project directory cannot coexist — the second build invalidates the first. Use separate tmux sessions and ensure builds complete before the next `flutter run`.

4. **CBPeripheralManager addService Crash**: Re-adding a service without proper cleanup can cause a native `SIGABRT` in `[CBPeripheralManager addService:]`. The coordinator's scenario now includes pre-run cleanup (stop_advertising + remove_service) and post-run cleanup to prevent this.

## Commits

- `feat(harness): forward Flutter errors to coordinator via WebSocket`
- `feat(coordinator): add --runs flag for consecutive BLE flow passes`
- `chore(harness): add BLE verification script for automated multi-run testing`
