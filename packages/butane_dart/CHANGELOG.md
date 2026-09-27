## Unreleased

- **Breaking:** Backend and platform failures now surface as `ButaneException`; consumers matching legacy `PlatformException.code` strings or BlueZ `StateError`/`TimeoutException` types must catch `ButaneException` and switch on `ButaneErrorCode`.

## 0.1.0

- Initial public release: pure-Dart reactive BLE porcelain (`CentralManager`/`PeripheralManager`) and the `ButanePlatformInterface` backend contract, no Flutter dependency.
