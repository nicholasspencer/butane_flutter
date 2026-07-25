library butane.windows;

import 'package:butane_platform_interface/butane_platform_interface.dart';
import 'package:butane_platform_interface/channels.dart';

/// The Windows platform implementation of butane.
///
/// Mirrors `ButaneCoreBluetooth` and the Android registrant: all behaviour
/// lives in [ButanePlatform], the generated-method-channel implementation of
/// [ButanePlatformInterface]. This class exists only so Flutter's federated
/// plugin registration has something to instantiate — it is butane's `windows`
/// `default_package` and `dartPluginClass`.
///
/// The real work is native, under `windows/` (C++/WinRT implementing the
/// Pigeon `ButaneHostApi`). See `docs/windows-dev-environment.md` for the
/// build target, and the Windows epic for why Windows cannot use the pure-Dart
/// shape Linux uses.
final class ButaneWindows extends ButanePlatform {
  /// Registers this backend as the platform implementation. Invoked by
  /// Flutter's generated plugin registrant on Windows.
  static void registerWith() {
    ButanePlatformInterface.instance = ButaneWindows();
  }
}
