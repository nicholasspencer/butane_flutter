## Unreleased

- Added `Peripheral.bond()`, `bondState`, and `bondStateStream`; Android, Linux, and Windows perform platform pairing, while Darwin reports `ButaneErrorCode.unsupported`.
- **Breaking:** Backend and platform failures now surface as `ButaneException`; consumers matching legacy `PlatformException.code` strings or BlueZ `StateError`/`TimeoutException` types must catch `ButaneException` and switch on `ButaneErrorCode`.

## 0.1.0

- Initial public release: reactive BLE central/peripheral porcelain for Flutter with endorsed iOS/macOS (`butane_core_bluetooth`), Android (`butane_android`), and Linux (`butane_bluez`) implementations.
