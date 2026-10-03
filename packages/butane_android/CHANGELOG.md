## Unreleased

- Added peripheral bonding through `BluetoothDevice.createBond()` with current-state queries and `ACTION_BOND_STATE_CHANGED` observation.
- **Breaking:** Backend failures now surface as `ButaneException`; authored operation context leads each Android error message and a nonblank native cause message is appended. Consumers must catch `ButaneException` and switch on `ButaneErrorCode`.

## 0.1.0

- Initial public release: Android implementation of the Butane BLE plugin.
