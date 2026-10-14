## 0.2.0

- The Pigeon `connect` now carries `ConnectOptions`, and a new `requestEnable` host call asks the platform to turn Bluetooth on.
- Added the cross-platform bonding contract for `bond`, `bondState`, and bond-state callbacks.
- **Breaking:** Host failures now use the shared `ButaneErrorCode` vocabulary and surface as `ButaneException`, with scan startup awaited; Windows GATT access-denied failures map to `operationFailed`, and an absent Windows backend maps to `unavailable`. Consumers must catch `ButaneException` and switch on `ButaneErrorCode`.
- The Pigeon scan payload now carries solicited and overflow service UUIDs plus per-advertisement RSSI and epoch-millisecond timestamps.

## 0.1.0

- Initial public release: the Flutter federated-plugin interface binding `butane` to its platform implementations over `butane_dart`'s contract.
