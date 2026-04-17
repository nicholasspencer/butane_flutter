# butane 🔥

The public API ("porcelain") layer of the Butane BLE plugin. This is the
package Flutter apps import.

Entry point: `package:butane/butane.dart`. The surface is exposed through
three managers:

- `CentralManager` — scan for and connect to peripherals; discover
  services and characteristics; read / write / subscribe.
- `PeripheralManager` — advertise services and respond to GATT requests
  (supported on platforms whose backend implements the peripheral role —
  currently Linux via `butane_bluez`).
- `PeerManager` — session-scoped peer lookup used by both sides.

Peripherals, services, characteristics, and descriptors are immutable
model objects; writes go through the managers.

## Platform routing

`butane` is a no-op Dart shim; actual BLE work is delegated to a
platform package selected by `default_package` in `pubspec.yaml`:

- iOS / macOS → [`butane_core_bluetooth`](../butane_core_bluetooth)
- Linux → [`butane_bluez`](../butane_bluez)
- Android → [`butane_android`](../butane_android) (stub)

## Example

See [`example/`](example) for a runnable Flutter app that scans,
connects, and reads characteristics through `CentralManager`.
