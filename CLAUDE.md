# CLAUDE.md

This file provides guidance to agents working in this repository.

## What This Is

Butane is a Flutter BLE (Bluetooth Low Energy) library supporting central and peripheral roles on iOS, macOS, Linux, and Android. It uses federated platform implementations and Pigeon for Flutter-to-native communication.

The Android implementation covers permissions, scanning, advertising, adapter state, connection management, GATT service and characteristic discovery, GATT reads and writes, notifications, and GATT server behavior.

## Monorepo Structure

The Dart pub workspace contains nine packages under `packages/`:

- `butane` — Flutter-facing porcelain API.
- `butane_platform_interface` — abstract platform interface and Pigeon channels.
- `butane_core_bluetooth` — iOS/macOS CoreBluetooth implementation.
- `butane_android` — complete Android Kotlin implementation for central and peripheral BLE roles.
- `butane_bluez` — Flutter Linux implementation through BlueZ.
- `butane_dart` — Flutter-free reactive BLE API.
- `butane_dart_bluez` — Flutter-free BlueZ backend.
- `butane_harness` — dual-role Flutter integration harness exposed through Leonard.
- `butane_grid_assets` — grid burn asset, follower launchers, scripted scenarios, and reports.

## Build Commands

The grid packages use private workspace dependencies. On a provisioned Gas City machine, generate the gitignored machine-local overrides before resolving:

    grid dart link
    dart pub get

Run Flutter package checks from the package being changed:

    cd packages/butane
    flutter analyze
    flutter test

Run the pure-Dart burn asset checks with the Dart runner:

    cd packages/butane_grid_assets
    dart analyze
    dart test

Regenerate Pigeon channels after changing `packages/butane_platform_interface/pigeons/api.dart`:

    ./tool/gen_api.sh

## Architecture

Flutter applications use `butane` → `butane_platform_interface` → Pigeon method channels → `butane_core_bluetooth`, `butane_android`, or `butane_bluez`.

Flutter-free applications use `butane_dart` → a backend such as `butane_dart_bluez`; this path does not depend on Flutter or Pigeon.

Cross-device burns use `butane_grid_assets` to lease and launch a `butane_harness` follower, launch the local harness role, and drive both harnesses through Leonard over their Dart VM-service endpoints. See `docs/burn-workflow.md`.

## Code Generation

Pigeon generates the method channel layer from `packages/butane_platform_interface/pigeons/api.dart`. Running `./tool/gen_api.sh` updates the generated Dart, Swift, Kotlin, and C++ channels. Always regenerate them after changing the Pigeon source.

## Lint Rules

- Trailing commas are required and enforced as errors.
- Strict casts, inference, and raw types are enabled.
