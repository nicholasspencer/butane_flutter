# butane_core_bluetooth

The iOS and macOS implementation of the Butane BLE plugin — central and
peripheral roles wrapping Apple's
[CoreBluetooth](https://developer.apple.com/documentation/corebluetooth)
framework in Swift, satisfying the contract defined by
[`butane_platform_interface`](https://pub.dev/packages/butane_platform_interface).

Endorsed as the `default_package` for iOS and macOS in
[`butane`](https://pub.dev/packages/butane), so apps get this implementation
transparently by depending on `butane` — nothing else to wire up.

## What's inside

- `darwin/Classes/` — Swift code. `ButaneCoreBluetoothPlugin` implements
  `ButaneHostApi`; `CentralManager` wraps `CBCentralManager`;
  `PeripheralActor` is a Swift actor that owns per-peripheral state
  and bridges CoreBluetooth's delegate callbacks into async/await via
  continuations.
- `darwin/Classes/Api.gen.swift` — Pigeon-generated channel bindings
  (regenerate from the platform interface with `tool/gen_api.sh` at the
  repo root).
- [`example/`](example) — minimal app used during native development
  and on-device testing.

## When to touch this package

Changes that affect iOS / macOS behavior: scan filters, connection
state, GATT discovery, session model, or any platform-specific bug
fix. Changes that affect the Dart↔native contract belong in
[`butane_platform_interface`](https://pub.dev/packages/butane_platform_interface)
instead.
