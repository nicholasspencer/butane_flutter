## Unreleased

- **Breaking:** Backend and platform failures now surface as `ButaneException`, and `CentralManager.scan()` now awaits backend startup and surfaces setup failures; consumers matching legacy exception types must catch `ButaneException` and switch on `ButaneErrorCode`.

## 0.1.0

- Initial public release: pure-Dart reactive BLE porcelain (`CentralManager`/`PeripheralManager`) and the `ButanePlatformInterface` backend contract, no Flutter dependency.
