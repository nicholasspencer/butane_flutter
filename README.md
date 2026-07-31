# Butane 🔥

Butane is a Flutter Bluetooth Low Energy plugin. It uses a federated plugin
architecture with [Pigeon](https://pub.dev/packages/pigeon) for the
Dart ↔ native bridge, and exposes a unified porcelain API
(`CentralManager`, `PeripheralManager`, `PeerManager`) on top of
platform-specific implementations.

## Platform support

| Platform | Central | Peripheral | Backend |
|----------|---------|------------|---------|
| iOS      | ✅      | ✅         | CoreBluetooth (Swift) |
| macOS    | ✅      | ✅         | CoreBluetooth (Swift) |
| Linux    | ✅      | ✅         | BlueZ 5.x via D-Bus + raw `dbus` for GATT server / advertising |
| Android  | ✅      | ✅         | Android BLE APIs (Kotlin), min API 31 |

All four platforms have passed the full 15-step [`ble_flow`](docs/harness-verification.md) scenario. Screen recordings of the Android ↔ macOS cross-device burns (both directions) are in [`docs/recordings/`](docs/recordings/).

## Monorepo layout

This repo is a Dart pub workspace. Packages live under `packages/`:

| Package | Role |
|---------|------|
| [`butane`](packages/butane) | Flutter-facing porcelain API. |
| [`butane_platform_interface`](packages/butane_platform_interface) | Abstract platform interface and Pigeon channels. |
| [`butane_core_bluetooth`](packages/butane_core_bluetooth) | iOS/macOS CoreBluetooth implementation. |
| [`butane_android`](packages/butane_android) | Complete Android Kotlin implementation for central and peripheral BLE roles. |
| [`butane_bluez`](packages/butane_bluez) | Flutter Linux implementation through BlueZ. |
| [`butane_dart`](packages/butane_dart) | Flutter-free reactive BLE API. |
| [`butane_dart_bluez`](packages/butane_dart_bluez) | Flutter-free BlueZ backend. |
| [`butane_harness`](packages/butane_harness) | Dual-role Flutter integration harness driven through Leonard. |
| [`butane_grid_assets`](packages/butane_grid_assets) | Grid burn domain: follower launchers, scripted scenarios, and reports. |

## Getting started

```bash
dart pub get
```

Start with `packages/butane/example/` for a runnable demo, and see
`packages/butane/lib/butane.dart` for the public surface.

## Developing

```bash
./tool/gen_api.sh                   # regenerate Pigeon channels

cd packages/butane
flutter analyze
flutter test

cd ../..
cd packages/butane_grid_assets
dart analyze
dart test
```

After editing
`packages/butane_platform_interface/pigeons/api.dart`, always rerun
`./tool/gen_api.sh`.

Repo conventions (enforced by `analysis_options.yaml`):

- Trailing commas are **required**.
- Strict casts, inference, and raw types are all on.

See [`CLAUDE.md`](CLAUDE.md) for the full architecture and contribution
guide.

## Docs

Additional notes live under [`docs/`](docs):

- [`docs/linux-dev-environment.md`](docs/linux-dev-environment.md) —
  required `ControllerMode = le` configuration for BlueZ on Linux when
  acting as central against dual-mode peers (Apple devices). Without this,
  bluetoothd will try BR/EDR and GATT will never resolve.
- [`docs/burn-workflow.md`](docs/burn-workflow.md) — end-to-end
  operational walkthrough for cross-device BLE integration runs: grid
  station setup, follower leasing, Leonard/Dart VM-service driving, and
  teardown.
- [`docs/harness-verification.md`](docs/harness-verification.md) —
  architecture diagrams and the 15-step verification report.
- [`docs/bluetoothctl.md`](docs/bluetoothctl.md) — `bluetoothctl` cheat
  sheet for Linux debugging.
- [`docs/recordings/`](docs/recordings/) — screen recordings of the
  Android ↔ macOS cross-device burns in both central/peripheral directions,
  with per-step coordinator results.
