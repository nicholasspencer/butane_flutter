# butane_core_bluetooth

iOS and macOS implementation of the Butane BLE plugin. Wraps Apple's
[CoreBluetooth](https://developer.apple.com/documentation/corebluetooth)
framework in Swift and satisfies the interface defined by
[`butane_platform_interface`](../butane_platform_interface).

Registered as the `default_package` for iOS and macOS in
[`butane`](../butane), so apps get this implementation transparently by
depending on `butane` — nothing else to wire up.

## What's inside

- `darwin/Classes/` — Swift code. `ButaneCoreBluetoothPlugin` implements
  `ButaneHostApi`; `CentralManager` wraps `CBCentralManager`;
  `PeripheralActor` is a Swift actor that owns per-peripheral state
  and bridges CoreBluetooth's delegate callbacks into async/await via
  continuations.
- `darwin/Classes/Api.gen.swift` — Pigeon-generated channel bindings
  (regenerate from the platform interface with
  [`../../tool/gen_api.sh`](../../tool/gen_api.sh)).
- [`example/`](example) — minimal app used during native development
  and on-device testing.

## When to touch this package

Changes that affect iOS / macOS behavior: scan filters, connection
state, GATT discovery, session model, or any platform-specific bug
fix. Changes that affect the Dart↔native contract belong in
[`butane_platform_interface`](../butane_platform_interface) instead.
