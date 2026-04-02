import 'src/central_role.dart';
import 'src/config.dart';
import 'src/harness_app.dart';
import 'src/harness_log.dart';
import 'src/harness_server.dart';
import 'src/peripheral_role.dart';
import 'package:flutter/material.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final config = HarnessConfig.fromEnvironment();
  final server = HarnessServer(port: config.wsPort);
  final log = HarnessLog();

  CentralRole? centralRole;
  PeripheralRole? peripheralRole;

  switch (config.role) {
    case HarnessRole.central:
      centralRole = CentralRole(server: server, log: log);
    case HarnessRole.peripheral:
      peripheralRole = PeripheralRole(server: server, log: log);
  }

  runApp(HarnessApp(
    config: config,
    server: server,
    log: log,
    onDispose: () {
      centralRole?.dispose();
      peripheralRole?.dispose();
    },
  ));
}
