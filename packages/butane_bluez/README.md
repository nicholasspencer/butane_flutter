# butane_bluez

Linux implementation of the Butane BLE plugin, backed by
[BlueZ](https://www.bluez.org/) over D-Bus.

Registered as the `default_package` for Linux in [`butane`](../butane),
so apps depending on `butane` on Linux get this implementation
transparently.

## Central and peripheral

This package implements both roles:

- **Central** — uses the [`bluez`](https://pub.dev/packages/bluez) Dart
  package to scan, connect, discover services, and read/write
  characteristics.
- **Peripheral** — advertising (`LEAdvertisement1`), GATT server
  (`GattManager1` / `RegisterApplication`), and characteristic
  notifications (`StartNotify` / `StopNotify`) are **not** exposed by
  the `bluez` 0.1.4 public API, so the peripheral side is implemented
  directly against raw D-Bus using the
  [`dbus`](https://pub.dev/packages/dbus) package.

Central-role notifications also go through raw D-Bus for the same
reason.

## Linux prerequisites

BlueZ 5.72 cannot reliably force LE/GATT on dual-mode peers (Apple
devices advertise BR/EDR + LE on the same public address) through
D-Bus alone. `Device1.ConnectProfile` is BR/EDR-only, and
`ServicesResolved` never flips without help. The only deterministic
fix is to run the adapter in LE-only mode:

```ini
# /etc/bluetooth/main.conf
[General]
ControllerMode = le
```

Then `sudo systemctl restart bluetooth`. See
[`../../docs/linux-dev-environment.md`](../../docs/linux-dev-environment.md)
for the full story.

## Running smoke tests

See [`example/`](example) for runtime smoke tests that exercise the
package against a live `bluetoothd`.
