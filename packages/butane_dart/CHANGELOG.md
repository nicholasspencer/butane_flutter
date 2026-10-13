## Unreleased

- Added the `Peripheral.bond()`, `bondState`, and `bondStateStream` porcelain APIs and the shared `BondState` model.
- **Breaking:** Backend and platform failures now surface as `ButaneException`, and `CentralManager.scan()` now awaits backend startup and surfaces setup failures; consumers matching legacy exception types must catch `ButaneException` and switch on `ButaneErrorCode`.
- `AdvertisementData` now exposes solicited and Darwin overflow service UUIDs, while `ScanResult` exposes per-advertisement RSSI and epoch-millisecond timestamps.

## 0.1.0

- Initial public release: pure-Dart reactive BLE porcelain (`CentralManager`/`PeripheralManager`) and the `ButanePlatformInterface` backend contract, no Flutter dependency.
