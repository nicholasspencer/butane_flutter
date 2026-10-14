## 0.2.0

- `connect()` honours `autoConnect` and `refreshGattCache`; a refresh completes only once services are rediscovered.
- Added `requestEnable()` through `BluetoothAdapter.ACTION_REQUEST_ENABLE`.
- Accepts 16- and 32-bit Bluetooth UUIDs (for example `2901`) everywhere a UUID is passed, as Darwin and BlueZ do.
- Disconnecting a peripheral whose link already dropped is now a no-op instead of an error.
- Documented how to override the Bluetooth manifest entries the plugin merges into apps.
- Added peripheral bonding through `BluetoothDevice.createBond()` with current-state queries and `ACTION_BOND_STATE_CHANGED` observation.
- **Breaking:** Backend failures now surface as `ButaneException`; authored operation context leads each Android error message and a nonblank native cause message is appended. Consumers must catch `ButaneException` and switch on `ButaneErrorCode`.
- Scan results now populate solicited service UUIDs, per-advertisement RSSI, and epoch-millisecond timestamps; unsupported overflow UUIDs remain null.

## 0.1.0

- Initial public release: Android implementation of the Butane BLE plugin.
