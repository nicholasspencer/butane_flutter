import 'dart:async';

import 'package:flutter/material.dart';

import 'config.dart';
import 'harness_log.dart';
import 'harness_server.dart';

class HarnessApp extends StatelessWidget {
  const HarnessApp({
    super.key,
    required this.config,
    required this.server,
    required this.log,
    this.onDispose,
  });

  final HarnessConfig config;
  final HarnessServer server;
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
        server: server,
        log: log,
        onDispose: onDispose,
      ),
    );
  }
}

class _HarnessHome extends StatefulWidget {
  const _HarnessHome({
    required this.config,
    required this.server,
    required this.log,
    this.onDispose,
  });

  final HarnessConfig config;
  final HarnessServer server;
  final HarnessLog log;
  final VoidCallback? onDispose;

  @override
  State<_HarnessHome> createState() => _HarnessHomeState();
}

class _HarnessHomeState extends State<_HarnessHome> {
  String _wsStatus = 'Starting...';
  final List<String> _logEntries = [];
  final _scrollController = ScrollController();

  late final StreamSubscription<String> _wsStatusSub;
  late final StreamSubscription<String> _logSub;

  @override
  void initState() {
    super.initState();

    _wsStatusSub = widget.server.statusStream.listen((status) {
      setState(() => _wsStatus = status);
      widget.log.add('WS: $status');
    });

    _logSub = widget.log.entries.listen((entry) {
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
    });

    _startServer();
  }

  Future<void> _startServer() async {
    try {
      await widget.server.start();
    } catch (e) {
      widget.log.add('Server start failed: $e');
      setState(() => _wsStatus = 'Failed: $e');
    }
  }

  @override
  void dispose() {
    _wsStatusSub.cancel();
    _logSub.cancel();
    widget.server.stop();
    widget.onDispose?.call();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${widget.config.role.displayName} · :${widget.config.wsPort}',
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Row(
              children: [
                Icon(
                  widget.server.isConnected ? Icons.link : Icons.link_off,
                  size: 16,
                  color: widget.server.isConnected
                      ? Colors.greenAccent
                      : Colors.grey,
                ),
                const SizedBox(width: 8),
                Text(
                  _wsStatus,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
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
          ),
        ],
      ),
    );
  }
}
