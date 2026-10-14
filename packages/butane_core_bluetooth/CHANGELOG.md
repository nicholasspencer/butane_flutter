## 0.2.0

- `Characteristic.descriptors` is now populated; descriptors are discovered with their characteristics.
- Descriptor values are read by their Core Bluetooth type, fixing a crash on the user-description and configuration descriptors.
- A published characteristic may carry `2901` and `2904` descriptors; any other descriptor type reports `ButaneErrorCode.unsupported` instead of crashing.
- `connect()` options `autoConnect` and `refreshGattCache`, and `requestEnable()`, report `ButaneErrorCode.unsupported`.
- Requests pending when a peripheral disconnects now fail with `ButaneErrorCode.disconnected` instead of never completing.
- **Breaking:** The minimum deployment targets are now iOS 15 and macOS 12, the oldest targets current Xcode builds.
- Added explicit typed `ButaneErrorCode.unsupported` failures for `Peripheral.bond()` and `bondState` because Core Bluetooth pairing is implicit.
- **Breaking:** Backend failures now surface as `ButaneException`; a Darwin state query for an unregistered peripheral returns `disconnected`, while connect and cancel report `notFound`. Consumers must catch `ButaneException` and switch on `ButaneErrorCode`.
- Each scan now reports every peripheral it discovers, including ones an earlier scan already found.
- First-seen scan results now populate solicited and overflow service UUIDs, delegate RSSI, and epoch-millisecond timestamps.

## 0.1.0

- Initial public release: iOS and macOS implementation over Apple Core Bluetooth (central and peripheral roles).
