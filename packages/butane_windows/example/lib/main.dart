// Minimal host for the butane_windows plugin.
//
// This example exists primarily so the plugin's C++ unit tests get built:
// windows/CMakeLists.txt gates the `butane_windows_test` googletest target on
// `include_butane_windows_tests`, which is set only when building an example.
// Running the tests therefore means building this app first.
//
// It deliberately does not drive a radio yet — the central-role implementation
// is still being written. It reports which platform implementation Flutter's
// federated registration installed, which is the one thing the Dart half of
// this package is responsible for.

import 'package:butane_platform_interface/butane_platform_interface.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(const ButaneWindowsExampleApp());
}

class ButaneWindowsExampleApp extends StatelessWidget {
  const ButaneWindowsExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    final implementation = ButanePlatformInterface.instance.runtimeType;
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('butane_windows')),
        body: Center(
          child: Text('Platform implementation: $implementation'),
        ),
      ),
    );
  }
}
