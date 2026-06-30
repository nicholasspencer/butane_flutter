/// Pure-Dart BlueZ/D-Bus backend implementing the butane_dart platform
/// abstraction. No Flutter dependency — usable from headless Dart (CLI tools,
/// server apps, provisioning scripts). Assign it as the platform
/// implementation before using the porcelain:
///
///     ButanePlatformInterface.instance = ButaneDartBluez();
///
/// (The `butane_bluez` Flutter plugin wraps this and registers it
/// automatically for Flutter Linux apps.)
library;

export 'src/butane_dart_bluez.dart' show ButaneDartBluez;
