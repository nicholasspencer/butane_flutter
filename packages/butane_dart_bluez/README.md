# butane_dart_bluez

Pure-Dart BlueZ/D-Bus backend for
[`butane_dart`](https://pub.dev/packages/butane_dart) — BLE on Linux with no
Flutter dependency.

`ButaneDartBluez` implements `ButanePlatformInterface` over BlueZ via the
system D-Bus, so any Dart program on a Linux host with a BlueZ-managed adapter
can act as a BLE central or peripheral. The Flutter Linux implementation
([`butane_bluez`](https://pub.dev/packages/butane_bluez)) delegates here; you
only depend on this package directly for non-Flutter use.

## Register the backend

```dart
import 'package:butane_dart/butane_dart.dart';
import 'package:butane_dart_bluez/butane_dart_bluez.dart';

Future<void> main() async {
  ButanePlatformInterface.instance = ButaneDartBluez();
  final central = CentralManager(clientIdentifier: 'my-linux-cli');
  await for (final result in central.scan()) {
    print('${result.peripheral} ${result.rssi}');
  }
}
```

## Requirements

- Linux with BlueZ ≥ 5 and a powered adapter.
- D-Bus system-bus access for the running user.

## Manual source receipt

`ButaneDartBluez.readDescriptor` and `ButaneDartBluez.writeDescriptor` use the
`bluez` package's `BlueZGattDescriptor.readValue()` and
`BlueZGattDescriptor.writeValue()` methods. Those methods call the
`org.bluez.GattDescriptor1` `ReadValue` and `WriteValue` D-Bus operations.

`ButaneDartBluez.requestMtu` waits for services to resolve, then reads the
negotiated `MTU` published by `org.bluez.GattCharacteristic1`. BlueZ does not
offer a client-side target-MTU request, so the requested target is ignored and
the published effective value is returned.

This pure-Dart package has no native BlueZ fake for exercising these D-Bus
operations. On-radio proof remains part of the separate hardware burn workflow
documented in [`docs/burn-workflow.md`](../../docs/burn-workflow.md).

## License

MIT — see [LICENSE](LICENSE).
