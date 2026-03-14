# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

Butane is a Flutter BLE (Bluetooth Low Energy) plugin implementing the Central role. It supports iOS, macOS, and Android (Android is a stub). It uses a federated plugin architecture with Pigeon for Dart↔native communication.

## Monorepo Structure

Uses **Dart pub workspaces** to manage four packages under `packages/`:

- **butane** — Public API ("porcelain" layer). Entry point: `lib/butane.dart`
- **butane_platform_interface** — Abstract interface + Pigeon-generated channels. Pigeon source of truth: `pigeons/api.dart`
- **butane_core_bluetooth** — iOS/macOS native implementation (Swift, wraps CoreBluetooth)
- **butane_android** — Android native implementation (Kotlin, currently stub)

## Build Commands

```bash
dart pub get                       # Install deps (single resolution at root)
./tool/gen_api.sh                  # Regenerate Pigeon channels (Dart, Swift, Kotlin)
flutter analyze                    # Lint (in any package or example dir)
flutter test                       # Run tests (in a package dir)
flutter test path/to/test.dart     # Run a single test
```

## Code Generation

Pigeon generates the method channel layer from `packages/butane_platform_interface/pigeons/api.dart`. Running `./tool/gen_api.sh` outputs:
- Dart: `packages/butane_platform_interface/lib/src/channels/api.g.dart`
- Swift: `packages/butane_core_bluetooth/darwin/Classes/Api.gen.swift`
- Kotlin: `packages/butane_android/android/src/main/kotlin/com/nicospencer/butane_android/Api.gen.kt`

After modifying `pigeons/api.dart`, always regenerate.

## Architecture

```
App → butane (Porcelain) → butane_platform_interface → Method Channels (Pigeon) → Native (Swift/Kotlin)
```

**Dart porcelain layer** (`packages/butane/lib/src/procelain/`): `CentralManager` is the main entry point. It manages scanning, peripheral discovery, and exposes `Peripheral` objects with `Service`/`Characteristic` trees. Uses `PlatformStreamController` for bidirectional stream communication with the platform.

**Native layer** (Swift): `ButaneCoreBluetoothPlugin` implements `ButaneHostApi`. `CentralManager` wraps `CBCentralManager`. `PeripheralActor` is a Swift actor managing per-peripheral state with continuations for async callbacks.

**Session model**: Uses `Session`/`PeripheralSession` with identifiers (client, peripheral, adapter, restoration) to support multiple clients on the same adapter.

## Lint Rules

- Trailing commas are **required** (enforced as error)
- Strict casts, inference, and raw types are all enabled
