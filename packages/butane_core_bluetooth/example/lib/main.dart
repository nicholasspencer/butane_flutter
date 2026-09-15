import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  static const MethodChannel _channel = MethodChannel(
    'butane_core_bluetooth',
  );

  String _platformVersion = 'Unknown';

  @override
  void initState() {
    super.initState();
    initPlatformState();
  }

  Future<void> initPlatformState() async {
    String platformVersion;

    try {
      platformVersion =
          await _channel.invokeMethod<String>('getPlatformVersion') ??
              'Unknown platform version';
    } on PlatformException {
      platformVersion = 'Failed to get platform version.';
    } on MissingPluginException {
      platformVersion = 'Failed to get platform version.';
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _platformVersion = platformVersion;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(body: Text('Running on: $_platformVersion')),
    );
  }
}
