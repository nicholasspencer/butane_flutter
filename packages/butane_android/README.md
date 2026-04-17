# butane_android

Android implementation of the Butane BLE plugin.

> ⚠️ **Stub.** The Kotlin plugin is wired up (registered as the Android
> implementation of [`butane_platform_interface`](../butane_platform_interface),
> Pigeon channels generated) but no real BLE functionality is
> implemented yet. Depending on this on Android gets you a working
> channel with unimplemented method handlers.

## What's inside

- `android/src/main/kotlin/com/nicospencer/butane_android/` — Kotlin
  plugin skeleton: `ButaneAndroidPlugin` and the generated
  `Api.gen.kt` bindings.
- [`example/`](example) — Android host app for exercising the plugin
  once implementation lands.

## Regenerating channels

Pigeon output is checked in. After editing
`packages/butane_platform_interface/pigeons/api.dart`, run
[`../../tool/gen_api.sh`](../../tool/gen_api.sh) from the repo root.
