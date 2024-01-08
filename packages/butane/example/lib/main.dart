import 'dart:async';

import 'package:butane/butane.dart';
import 'package:flutter/material.dart' hide ConnectionState;

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final manager = CentralManager();

  final Map<Identifier, ScanResult> _scanResults = {};

  StreamSubscription<ScanResult>? _scanSubscription;

  StreamSubscription<PeerManagerState>? _managerStateStream;

  bool ready = false;

  @override
  void initState() {
    super.initState();

    _managerStateStream = manager.stateStream.listen(onManagerState);
  }

  void onManagerState(PeerManagerState state) {
    if (state == PeerManagerState.poweredOn) {
      setState(() {
        ready = true;
      });
    }
  }

  void onScanResult(ScanResult scanResult) {
    setState(() {
      _scanResults[scanResult.peripheral.identifier] = scanResult;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Plugin example app'),
          actions: [
            if (_scanResults.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.delete_rounded),
                onPressed: () {
                  setState(() {
                    _scanResults.clear();
                  });
                },
              ),
            if (_scanSubscription != null)
              IconButton(
                icon: const Icon(Icons.stop_rounded),
                onPressed: () {
                  setState(() {
                    _scanSubscription?.cancel();
                    _scanSubscription = null;
                  });
                },
              )
            else
              IconButton(
                icon: const Icon(
                  Icons.search_rounded,
                ),
                onPressed: ready
                    ? () {
                        setState(() {
                          _scanSubscription?.cancel();
                          _scanSubscription =
                              manager.scan().listen(onScanResult);
                        });
                      }
                    : null,
              ),
            const SizedBox(
              width: 40,
            ),
          ],
        ),
        body: _scanResults.isEmpty
            ? _scanSubscription != null
                ? const Center(
                    child: CircularProgressIndicator(),
                  )
                : const Center(
                    child: Icon(Icons.search_off_rounded),
                  )
            : ListView.builder(
                itemCount: _scanResults.length,
                itemBuilder: (context, index) {
                  final scanResult = _scanResults.values.elementAt(index);
                  return ScanResultListItem(scanResult: scanResult);
                },
              ),
      ),
    );
  }

  @override
  void dispose() {
    _scanSubscription?.cancel();
    _managerStateStream?.cancel();
    super.dispose();
  }
}

class ScanResultListItem extends StatefulWidget {
  const ScanResultListItem({
    required this.scanResult,
    super.key,
  });

  final ScanResult scanResult;

  @override
  State<ScanResultListItem> createState() => _ScanResultStateListItem();
}

class _ScanResultStateListItem extends State<ScanResultListItem> {
  ConnectionState _connectionState = ConnectionState.disconnected;

  StreamSubscription<ConnectionState>? _connectionStateSubscription;

  final _rssiStreamController = StreamController<int>();

  @override
  void initState() {
    super.initState();

    _connectionStateSubscription =
        widget.scanResult.peripheral.stateStream.listen(onConnectionState);

    Timer.periodic(const Duration(seconds: 1), (_) async {
      final rssi = await widget.scanResult.peripheral.rssi;
      _rssiStreamController.add(rssi);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              IconButton(
                icon: const Icon(Icons.bluetooth_rounded, size: 20),
                onPressed: _connectionState != ConnectionState.connected
                    ? connect
                    : null,
              ),
              IconButton(
                icon: const Icon(Icons.search_rounded, size: 20),
                onPressed: () {},
              ),
              StreamBuilder(
                stream: _rssiStreamController.stream,
                builder: (context, snapshot) {
                  return Text(
                    snapshot.data?.toString() ??
                        widget.scanResult.peripheral.initialRssi?.toString() ??
                        '??',
                  );
                },
              ),
            ],
          ),
          ScanResultDetails(scanResult: widget.scanResult),
        ],
      ),
    );
  }

  void onConnectionState(ConnectionState state) {
    setState(() {
      _connectionState = state;
    });
  }

  void connect() async {
    final peripheral = widget.scanResult.peripheral;
    await peripheral.connect();
  }

  void disconnect() async {
    final peripheral = widget.scanResult.peripheral;
    await peripheral.cancelConnection();
  }

  @override
  void dispose() {
    _connectionStateSubscription?.cancel();
    super.dispose();
  }
}

class ScanResultDetails extends StatelessWidget {
  const ScanResultDetails({
    required this.scanResult,
    super.key,
  });

  final ScanResult scanResult;

  @override
  Widget build(BuildContext context) {
    final localName = scanResult.advertisementData.localName ?? 'Unknown';
    final name = scanResult.peripheral.name ?? 'Unknown';
    final manufacturerData = scanResult.advertisementData.manufacturerData;
    final advertisedServices = scanResult.advertisementData.serviceUuids ?? [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Name: $name'),
          ],
        ),
        Row(
          children: [
            Text('Local Name: $localName'),
          ],
        ),
        Row(
          children: [
            Text(
              'Manufacturer Data: '
              '${manufacturerData != null ? manufacturerData.toString() : '(No manufacturer data)'}',
            ),
          ],
        ),
        Row(
          children: [
            Text(
              'Power level: '
              '${scanResult.advertisementData.txPowerLevel}',
            ),
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Text('Advertised Services: '),
              ],
            ),
            for (final service in advertisedServices)
              Row(
                children: [
                  const Icon(
                    Icons.subdirectory_arrow_right_rounded,
                    size: 20,
                  ),
                  Text(service),
                ],
              )
          ],
        ),
      ],
    );
  }
}
