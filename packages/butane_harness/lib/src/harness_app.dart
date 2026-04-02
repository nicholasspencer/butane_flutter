import 'dart:async';

import 'package:butane/butane.dart';
import 'package:flutter/material.dart';

import 'config.dart';
import 'harness_server.dart';

class HarnessApp extends StatelessWidget {
  const HarnessApp({
    super.key,
    required this.config,
    required this.server,
  });

  final HarnessConfig config;
  final HarnessServer server;

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
      home: _HarnessHome(config: config, server: server),
    );
  }
}

class _HarnessHome extends StatefulWidget {
  const _HarnessHome({required this.config, required this.server});

  final HarnessConfig config;
  final HarnessServer server;

  @override
  State<_HarnessHome> createState() => _HarnessHomeState();
}

class _HarnessHomeState extends State<_HarnessHome> {
  late final CentralManager _centralManager;
  PeerManagerState _bleState = PeerManagerState.unknown;
  String _wsStatus = 'Starting...';
  final List<String> _log = [];
  final _scrollController = ScrollController();

  late final StreamSubscription<PeerManagerState> _bleSub;
  late final StreamSubscription<String> _wsStatusSub;
  late final StreamSubscription<Map<String, dynamic>> _commandSub;

  @override
  void initState() {
    super.initState();
    _centralManager = CentralManager();

    _bleSub = _centralManager.stateStream.listen((state) {
      setState(() => _bleState = state);
      _addLog('BLE: ${state.name}');
    });

    _wsStatusSub = widget.server.statusStream.listen((status) {
      setState(() => _wsStatus = status);
      _addLog('WS: $status');
    });

    _commandSub = widget.server.commands.listen((cmd) {
      _addLog('CMD: $cmd');
      // Echo back a result
      widget.server.send({
        'type': 'result',
        'action': cmd['action'],
        'success': true,
        'data': {},
      });
    });

    _startServer();
  }

  Future<void> _startServer() async {
    try {
      await widget.server.start();
    } catch (e) {
      _addLog('Server start failed: $e');
      setState(() => _wsStatus = 'Failed: $e');
    }
  }

  void _addLog(String entry) {
    setState(() {
      _log.add(
        '${DateTime.now().toIso8601String().substring(11, 19)} $entry',
      );
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
  }

  @override
  void dispose() {
    _bleSub.cancel();
    _wsStatusSub.cancel();
    _commandSub.cancel();
    _centralManager.dispose();
    widget.server.stop();
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
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Center(
              child: Text(
                'BLE: ${_bleState.name}',
                style: TextStyle(
                  color: _bleState == PeerManagerState.poweredOn
                      ? Colors.greenAccent
                      : Colors.orangeAccent,
                ),
              ),
            ),
          ),
        ],
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
                  widget.server.isConnected
                      ? Icons.link
                      : Icons.link_off,
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
              itemCount: _log.length,
              itemBuilder: (context, index) {
                return Text(
                  _log[index],
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
