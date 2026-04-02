import 'src/config.dart';
import 'src/harness_app.dart';
import 'src/harness_server.dart';
import 'package:flutter/material.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final config = HarnessConfig.fromEnvironment();
  final server = HarnessServer(port: config.wsPort);

  runApp(HarnessApp(config: config, server: server));
}
