## 0.2.0

- `connect()` honours `timeoutMillis` (30 s when unset); `autoConnect` and `refreshGattCache` report `ButaneErrorCode.unsupported`.
- Added `requestEnable()`, which powers the adapter through `Adapter1.Powered`.
- Added peripheral pairing through BlueZ `Device1.Pair()` with bond state read from and observed through the `Paired` property.
- **Breaking:** Failures that formerly threw `StateError` or `TimeoutException` now surface as `ButaneException`; consumers must catch `ButaneException` and switch on `ButaneErrorCode`.
- Scan results now populate per-advertisement RSSI and a Dart receive-time epoch-millisecond timestamp; unsupported solicited and overflow UUIDs remain null.

## 0.1.0

- Initial public release: pure-Dart BlueZ/D-Bus backend implementing `ButanePlatformInterface` on Linux.
