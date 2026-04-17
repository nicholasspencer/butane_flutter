# Butane 🔥

> Light your comm on fire.

Butane is a Flutter Bluetooth Low Energy plugin. It uses a federated plugin
architecture with [Pigeon](https://pub.dev/packages/pigeon) for the
Dart ↔ native bridge, and exposes a unified porcelain API
(`CentralManager`, `PeripheralManager`, `PeerManager`) on top of
platform-specific implementations.

## Platform support

| Platform | Status | Backend |
|----------|--------|---------|
| iOS      | ✅     | CoreBluetooth (Swift) |
| macOS    | ✅     | CoreBluetooth (Swift) |
| Linux    | ✅     | BlueZ over D-Bus (central + peripheral) |
| Android  | 🚧 stub | Kotlin scaffold only, no BLE yet |

## Monorepo layout

This repo is a Dart pub workspace. Packages live under `packages/`:

| Package | Role |
|---------|------|
| [`butane`](packages/butane) | Public API ("porcelain"). Apps depend on this. |
| [`butane_platform_interface`](packages/butane_platform_interface) | Abstract platform interface + Pigeon-generated channels. |
| [`butane_core_bluetooth`](packages/butane_core_bluetooth) | iOS / macOS implementation via CoreBluetooth. |
| [`butane_bluez`](packages/butane_bluez) | Linux implementation via BlueZ. |
| [`butane_android`](packages/butane_android) | Android implementation (stub). |
| [`butane_harness`](packages/butane_harness) | Integration-test harness app (central or peripheral role, WebSocket-controlled). |
| [`butane_coordinator`](packages/butane_coordinator) | CLI that drives two harness instances through scripted scenarios. |

## Getting started

```bash
dart pub get                        # single resolution across the workspace
```

Start with `packages/butane/example/` for a runnable demo, and see
`packages/butane/lib/butane.dart` for the public surface.

## Developing

```bash
./tool/gen_api.sh            # regenerate Pigeon channels (Dart, Swift, Kotlin)
flutter analyze              # run from any package or example dir
flutter test                 # run from a package dir
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
  operational walkthrough for cross-device BLE integration runs: git
  remote setup, SSH orchestration, harness launch on each platform,
  coordinator invocation, and report artifacts.
- [`docs/harness-verification.md`](docs/harness-verification.md) —
  architecture diagrams and the 15-step verification report.
- [`docs/bluetoothctl.md`](docs/bluetoothctl.md) — `bluetoothctl` cheat
  sheet for Linux debugging.
