# butane_android

The Android implementation of the [`butane`](https://pub.dev/packages/butane)
BLE plugin — central and peripheral roles in Kotlin over the Android Bluetooth
LE APIs, min SDK 31.

Endorsed as `butane`'s Android `default_package`: apps depending on `butane`
get this implementation transparently and never import it directly.

## What it implements

Both sides of `butane_platform_interface`'s contract:

- **Central** — runtime permission handling, scanning, connection management,
  GATT service and characteristic discovery, reads, writes, and
  characteristic notifications.
- **Peripheral** — advertising, a full GATT server (`GattServerManager`),
  per-central connection tracking (`PeripheralConnection`), read/write
  request routing, and value-update notifications.
- **Adapter lifecycle** — Bluetooth adapter state surfaced through the
  interface's client-state stream.

The Dart ↔ Kotlin bridge is Pigeon-generated (`Api.gen.kt`); the channel
definitions live in `butane_platform_interface`.

## Requirements

- `minSdkVersion 31` (Android 12) — the modern `BLUETOOTH_SCAN` /
  `BLUETOOTH_ADVERTISE` / `BLUETOOTH_CONNECT` permission model.
- Declare the relevant permissions in your app manifest; the plugin handles
  runtime requests.

## Regenerating channels

Pigeon output is checked in. After editing
`packages/butane_platform_interface/pigeons/api.dart`, run
`tool/gen_api.sh` from the repo root.

## Manual source receipt

`PeripheralConnection.writeDescriptorValue` calls Nordic's
`writeDescriptor(descriptor, value).suspend()`. Its
`PeripheralConnection.requestMtuValue` counterpart calls
`requestMtu(mtu).suspend()`, which completes with the negotiated value delivered
through Android's `BluetoothGattCallback.onMtuChanged` callback.

The current Kotlin unit target has no injectable `BluetoothGatt` fake, so these
native paths are recorded by source inspection. On-radio behavior remains part
of the separate hardware burn workflow documented in
[`docs/burn-workflow.md`](../../docs/burn-workflow.md).

## License

MIT — see [LICENSE](LICENSE).
