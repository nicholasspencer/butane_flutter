// Run on Linux with BlueZ and an adapter present:
//   dart run example/butane_bluez.dart
import 'dart:async';

import 'package:butane_bluez/butane_bluez.dart';
import 'package:butane_platform_interface/butane_platform_interface.dart';

Future<void> main() async {
  final bluez = ButaneBluez();
  final state = await bluez.clientState();
  stderr('adapter state: $state');
  if (state != ClientState.poweredOn) {
    stderr('adapter not powered on — enable Bluetooth and retry');
    return;
  }

  var count = 0;
  final subscription = bluez.scanStream().listen((result) {
    count++;
    final id = result.peripheral.session.peripheralIdentifier;
    final name =
        result.peripheral.name ?? result.advertisementData.localName ?? '';
    stderr('[${count.toString().padLeft(3)}] $id "$name"');
  });
  await bluez.scan();
  await Future<void>.delayed(const Duration(seconds: 10));
  await bluez.cancelScan();
  await subscription.cancel();
  stderr('done — $count total events');
}

void stderr(String message) {
  // ignore: avoid_print
  print(message);
}
