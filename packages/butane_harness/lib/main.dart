import 'src/central_role.dart';
import 'src/config.dart';
import 'src/harness_app.dart';
import 'src/harness_log.dart';
import 'src/harness_server.dart';
import 'package:flutter/material.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final config = HarnessConfig.fromEnvironment();
  final server = HarnessServer(port: config.wsPort, role: config.role);
  final log = HarnessLog();

  CentralRole? centralRole;
  if (config.role == HarnessRole.central) {
    centralRole = CentralRole(server: server, log: log);
  }

  runApp(HarnessApp(
    config: config,
    server: server,
    log: log,
    onDispose: () {
      centralRole?.dispose();
    },
  ));
}
