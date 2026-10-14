## Unreleased

- **Breaking:** The minimum deployment targets are now iOS 15 and macOS 12, the oldest targets current Xcode builds.
- Added explicit typed `ButaneErrorCode.unsupported` failures for `Peripheral.bond()` and `bondState` because Core Bluetooth pairing is implicit.
- **Breaking:** Backend failures now surface as `ButaneException`; a Darwin state query for an unregistered peripheral returns `disconnected`, while connect and cancel report `notFound`. Consumers must catch `ButaneException` and switch on `ButaneErrorCode`.
- First-seen scan results now populate solicited and overflow service UUIDs, delegate RSSI, and epoch-millisecond timestamps.

## 0.1.0

- Initial public release: iOS and macOS implementation over Apple Core Bluetooth (central and peripheral roles).
