# butane_platform_interface

The abstract interface that every Butane platform implementation
(`butane_core_bluetooth`, `butane_bluez`, `butane_android`, …) extends,
plus the Pigeon-generated method-channel bindings that carry calls and
events between Dart and native code.

**App developers do not depend on this package directly** — they depend
on [`butane`](../butane), which re-exports the public types. This
package exists so that platform implementations can share a single
contract.

## Pigeon is the source of truth

`pigeons/api.dart` defines every host-API call and flutter-API event.
The generated files are checked in:

- Dart: `lib/src/channels/api.g.dart`
- Swift: `../butane_core_bluetooth/darwin/Classes/Api.gen.swift`
- Kotlin: `../butane_android/android/src/main/kotlin/com/nicospencer/butane_android/Api.gen.kt`

After editing `pigeons/api.dart`, always regenerate:

```bash
../../tool/gen_api.sh
```
