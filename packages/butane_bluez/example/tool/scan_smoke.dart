// Runtime smoke test for ButaneBluez scan() / scanStream().
//
// Run on Linux with BlueZ + an adapter present:
//   dart run packages/butane_bluez/example/bin/scan_smoke.dart
//
// Scans for 10 seconds (LE, no UUID filter), prints each ScanResult as it
// arrives, then exits.
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
  final sub = bluez.scanStream().listen((r) {
    count++;
    final id = r.peripheral.session.peripheralIdentifier ?? '?';
    final name = r.peripheral.name ?? r.advertisementData.localName ?? '';
    final rssi = r.peripheral.rssi ?? 0;
    final services = r.advertisementData.serviceUuids ?? const [];
    stderr(
      '[${count.toString().padLeft(3)}] $id  rssi=$rssi  "$name"'
      '${services.isNotEmpty ? '  services=${services.join(",")}' : ''}',
    );
  });

  await bluez.scan();
  stderr('scanning for 10s...');
  await Future<void>.delayed(const Duration(seconds: 10));

  await bluez.cancelScan();
  await sub.cancel();
  stderr('done — $count events');
}

// Avoid pulling in dart:io just for stderr.writeln.
void stderr(String msg) {
  // ignore: avoid_print
  print(msg);
}
