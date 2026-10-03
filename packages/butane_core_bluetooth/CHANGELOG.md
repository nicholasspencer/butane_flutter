## Unreleased

- **Breaking:** Backend failures now surface as `ButaneException`; a Darwin state query for an unregistered peripheral returns `disconnected`, while connect and cancel report `notFound`. Consumers must catch `ButaneException` and switch on `ButaneErrorCode`.

## 0.1.0

- Initial public release: iOS and macOS implementation over Apple Core Bluetooth (central and peripheral roles).
