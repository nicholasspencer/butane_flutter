// A headless example: the butane_dart porcelain runs from plain Dart with no
// Flutter engine and no plugin registrant. A real consumer assigns
// `ButanePlatformInterface.instance` to a backend — e.g. `ButaneDartBluez()`
// from `butane_dart_bluez` — before using the managers (the headless
// equivalent of a Flutter plugin's `registerWith`). This file exists so
// `dart compile exe` proves the porcelain is AOT-compilable pure Dart.
import 'package:butane_dart/butane_dart.dart';

void main() {
  final central = CentralManager();
  print('butane_dart porcelain ready (no Flutter): ${central.runtimeType}');
  central.dispose();
}
