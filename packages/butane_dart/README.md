# butane_dart

Pure-Dart reactive BLE porcelain and platform abstraction — the core of the
Butane plugin family, with no Flutter dependency.

`butane_dart` defines the reactive central/peripheral porcelain
(`CentralManager`, `PeripheralManager`: scanning, advertising, connections,
GATT services and characteristics) and `ButanePlatformInterface`, the backend
contract concrete transports implement. Flutter apps normally consume it
through the [`butane`](https://pub.dev/packages/butane) plugin; pure-Dart
programs (CLIs, daemons, tests) can drive a backend directly.

## Scan from a Dart program

```dart
import 'package:butane_dart/butane_dart.dart';

Future<void> main() async {
  // With a registered platform backend (e.g. butane_dart_bluez on Linux):
  final central = CentralManager(clientIdentifier: 'my-cli');
  await for (final result in central.scan()) {
    print('${result.peripheral} ${result.rssi}');
  }
}
```

## Backends

A backend implements `ButanePlatformInterface` over a real radio.
[`butane_dart_bluez`](https://pub.dev/packages/butane_dart_bluez) is the
pure-Dart BlueZ/D-Bus backend for Linux; the Flutter platform implementations
(`butane_core_bluetooth`, `butane_android`) bind their native radios through
the same contract.

## License

MIT — see [LICENSE](LICENSE).
