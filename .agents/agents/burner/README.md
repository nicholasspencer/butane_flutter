# Burner 🔥

Integration test agent for butane_flutter. Builds, launches, and validates the BLE test harness autonomously.

## Quick Start

```bash
# Pre-grant Bluetooth permissions (one-time, or after TCC reset)
./grant_permissions.sh

# Run full integration suite
cd ../../  # project root
./tool/run_harness.sh
```

## Problem: Permissions Reset on Every Rebuild

macOS TCC identifies apps by **code signature**. Both harness example apps use ad-hoc signing (`CODE_SIGN_IDENTITY = "-"`), which generates a new signature on every Flutter rebuild. TCC treats each build as a new app and prompts for Bluetooth access again.

### Fix

1. **Short-term:** Run `grant_permissions.sh` before each harness run to pre-grant via TCC.db
2. **Long-term:** Switch both example apps to `Apple Development` signing identity so TCC grants persist

## Known Issues

- Both example apps share bundle ID `com.nicospencer.butaneCoreBluetoothExample` — this may confuse macOS when running simultaneously. The central example should get its own bundle ID.
- `butane_coordinator` has no `bin/` entry point yet — `run_harness.sh` references `bin/coordinator.dart` which doesn't exist.

## Files

| File | Purpose |
|------|---------|
| `AGENTS.md` | Full agent instructions for burner |
| `grant_permissions.sh` | Pre-grant Bluetooth TCC permissions |
| `README.md` | This file |
