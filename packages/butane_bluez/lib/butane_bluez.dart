import 'package:butane_dart_bluez/butane_dart_bluez.dart';
import 'package:butane_platform_interface/butane_platform_interface.dart';

/// Flutter plugin shim for the Linux platform.
///
/// The BLE implementation lives in the pure-Dart [ButaneDartBluez] backend;
/// this class exists only to satisfy Flutter's federated plugin registration
/// — it is butane's `linux` `default_package` and `dartPluginClass`. Headless
/// (non-Flutter) consumers skip this and use `ButaneDartBluez` directly.
base class ButaneBluez extends ButaneDartBluez {
  /// Registers this backend as the platform implementation. Invoked by
  /// Flutter's generated plugin registrant on Linux.
  static void registerWith() {
    ButanePlatformInterface.instance = ButaneBluez();
  }
}
