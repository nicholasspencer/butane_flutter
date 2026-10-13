## Unreleased

- Added peripheral pairing through BlueZ `Device1.Pair()` with bond state read from and observed through the `Paired` property.
- **Breaking:** Failures that formerly threw `StateError` or `TimeoutException` now surface as `ButaneException`; consumers must catch `ButaneException` and switch on `ButaneErrorCode`.

## 0.1.0

- Initial public release: pure-Dart BlueZ/D-Bus backend implementing `ButanePlatformInterface` on Linux.
