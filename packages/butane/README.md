# butane 🔥

Reactive Bluetooth Low Energy for Flutter — central *and* peripheral roles,
one API, federated platform implementations.

`butane` is the package Flutter apps import. It re-exports
[`butane_dart`](https://pub.dev/packages/butane_dart)'s reactive porcelain and
routes the actual BLE work to the platform implementation for the running OS.

## Platform support

| Platform | Central | Peripheral | Implementation |
|----------|---------|------------|----------------|
| iOS      | ✅      | ✅         | [`butane_core_bluetooth`](https://pub.dev/packages/butane_core_bluetooth) (CoreBluetooth, Swift) |
| macOS    | ✅      | ✅         | [`butane_core_bluetooth`](https://pub.dev/packages/butane_core_bluetooth) (CoreBluetooth, Swift) |
| Android  | ✅      | ✅         | [`butane_android`](https://pub.dev/packages/butane_android) (Android BLE, Kotlin, min API 31) |
| Linux    | ✅      | ✅         | [`butane_bluez`](https://pub.dev/packages/butane_bluez) (BlueZ 5.x over D-Bus) |

All implementations are endorsed (`default_package`), so depending on `butane`
alone gives you working BLE on every supported platform.

## The API in one glance

- **`CentralManager`** — scan for peripherals, connect, discover services and
  characteristics, read / write / subscribe to characteristic values.
- **`PeripheralManager`** — advertise services and serve a GATT server:
  `addService`, request streams (`readRequests`) with `respondToRequest`,
  and `updateValue` notifications.
- Both managers surface the adapter lifecycle (`state` / `stateStream`), and
  every observation is a `Stream` — scan results, connection events,
  characteristic notifications.
- Peripherals, services, characteristics, and descriptors are immutable model
  objects; mutation goes through the managers.

## Scan for peripherals

```dart
import 'package:butane/butane.dart';

final manager = CentralManager(
  restorationIdentifier: 'com.example.my_app',
);

final subscription = manager.scan().listen((ScanResult result) {
  print('${result.peripheral.identifier} ${result.rssi}');
});

// later:
await subscription.cancel();
```

See [`example/`](example) for a complete runnable app that scans, connects,
and reads characteristics through `CentralManager`.

## Architecture

Butane is a federated plugin:
[`butane_platform_interface`](https://pub.dev/packages/butane_platform_interface)
defines the platform contract (Pigeon-generated channels implementing
`butane_dart`'s `ButanePlatformInterface`), and each platform package
implements it natively. Pure-Dart programs can skip Flutter entirely and use
[`butane_dart`](https://pub.dev/packages/butane_dart) with a backend such as
[`butane_dart_bluez`](https://pub.dev/packages/butane_dart_bluez).

## License

MIT — see [LICENSE](LICENSE).
