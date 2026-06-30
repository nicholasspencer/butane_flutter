/// The pure-Dart BLE platform abstraction: [ButanePlatformInterface] and its
/// raw value types. Implemented by backends (e.g. `butane_dart_bluez`) and by
/// the Pigeon native adapter in `butane_platform_interface`; consumed by the
/// porcelain in `butane_dart.dart`.
library;

export 'src/interface/interface.dart';
