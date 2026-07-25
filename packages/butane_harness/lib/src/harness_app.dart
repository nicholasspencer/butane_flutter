import 'package:flutter/material.dart';

import 'config.dart';
import 'harness_log.dart';

class HarnessApp extends StatelessWidget {
  const HarnessApp({
    super.key,
    required this.config,
    required this.log,
    this.onDispose,
  });

  final HarnessConfig config;
  final HarnessLog log;
  final VoidCallback? onDispose;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Butane Harness - ${config.role.displayName}',
      theme: ThemeData(
        colorSchemeSeed: config.role == HarnessRole.central
            ? Colors.blue
            : Colors.deepOrange,
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      home: _HarnessHome(
        config: config,
        log: log,
        onDispose: onDispose,
      ),
    );
  }
}

class _HarnessHome extends StatefulWidget {
  const _HarnessHome({
    required this.config,
    required this.log,
    this.onDispose,
  });

  final HarnessConfig config;
  final HarnessLog log;
  final VoidCallback? onDispose;

  @override
  State<_HarnessHome> createState() => _HarnessHomeState();
}

class _HarnessHomeState extends State<_HarnessHome> {
  final List<String> _logEntries = [];
  final _scrollController = ScrollController();

  late final Future<void> Function() _cancelLog;

  @override
  void initState() {
    super.initState();

    _cancelLog = widget.log.entries.listen((entry) {
      setState(() {
        _logEntries.add(entry);
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 100),
            curve: Curves.easeOut,
          );
        }
      });
    }).cancel;
  }

  @override
  void dispose() {
    _cancelLog();
    widget.onDispose?.call();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.config.role.displayName),
      ),
      body: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.all(8),
        itemCount: _logEntries.length,
        itemBuilder: (context, index) {
          return Text(
            _logEntries[index],
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
            ),
          );
        },
      ),
    );
  }
}
