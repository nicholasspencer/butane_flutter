import 'src/central_role.dart';
import 'src/config.dart';
import 'src/harness_app.dart';
import 'src/harness_client_bridge.dart';
import 'src/harness_connection.dart';
import 'src/harness_log.dart';
import 'src/harness_server.dart';
import 'src/peripheral_role.dart';
import 'package:flutter/material.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final config = HarnessConfig.fromEnvironment();
  final log = HarnessLog();

  // Choose server (listens for connections) or client bridge (connects out).
  final HarnessConnection connection;
  if (config.useRelay) {
    connection = HarnessClientBridge(relayUrl: config.relayUrl!);
  } else {
    connection = HarnessServer(port: config.wsPort);
  }

  CentralRole? centralRole;
  PeripheralRole? peripheralRole;

  switch (config.role) {
    case HarnessRole.central:
      centralRole = CentralRole(server: connection, log: log);
    case HarnessRole.peripheral:
      peripheralRole = PeripheralRole(server: connection, log: log);
  }

  runApp(HarnessApp(
    config: config,
    connection: connection,
    log: log,
    onDispose: () {
      centralRole?.dispose();
      peripheralRole?.dispose();
    },
  ));
}
