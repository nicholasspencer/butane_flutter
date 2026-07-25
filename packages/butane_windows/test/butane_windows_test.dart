import 'package:butane_platform_interface/butane_platform_interface.dart';
import 'package:butane_platform_interface/channels.dart';
import 'package:butane_windows/butane_windows.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('registerWith installs ButaneWindows as the platform instance', () {
    // The whole contract of the Dart half: Flutter's generated registrant
    // calls registerWith() on Windows, and butane must then route through
    // this backend.
    ButaneWindows.registerWith();
    expect(ButanePlatformInterface.instance, isA<ButaneWindows>());
  });

  test('ButaneWindows is a ButanePlatform', () {
    // Behaviour lives in ButanePlatform (the generated-method-channel
    // implementation); this backend must not diverge from it. If someone
    // re-parents ButaneWindows onto ButanePlatformInterface directly they
    // would have to reimplement ~30 methods, so pin the hierarchy.
    expect(ButaneWindows(), isA<ButanePlatform>());
  });

  test('registerWith is idempotent', () {
    ButaneWindows.registerWith();
    final first = ButanePlatformInterface.instance;
    ButaneWindows.registerWith();
    final second = ButanePlatformInterface.instance;

    expect(first, isA<ButaneWindows>());
    expect(second, isA<ButaneWindows>());
    // A fresh instance each call is fine; installing a DIFFERENT type is not.
    expect(second.runtimeType, first.runtimeType);
  });
}
