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
  late final manager = CentralManager(
    restorationIdentifier: 'com.example.butane_example',
  );

  final Map<Identifier, ScanResult> _scanResults = {};

  final Map<Identifier, Peripheral> _peripherals = {};

  StreamSubscription<ScanResult>? _scanSubscription;

  StreamSubscription<PeerManagerState>? _managerStateStream;

  bool ready = false;

  @override
  void initState() {
    super.initState();

    _managerStateStream = manager.stateStream.listen(onManagerState);
  }

  Future<void> onManagerState(PeerManagerState state) async {
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
    final items = [
      ..._scanResults.values,
      ..._peripherals.values,
    ];

    var count = items.length;

    if (_scanSubscription != null) {
      count += 1;
    }

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
        body: items.isEmpty
            ? _scanSubscription != null
                ? const Center(
                    child: CircularProgressIndicator(),
                  )
                : const Center(
                    child: Icon(Icons.search_off_rounded),
                  )
            : ListView.builder(
                itemCount: count,
                itemBuilder: (context, index) {
                  if (_scanSubscription != null && index == count - 1) {
                    return const Padding(
                      padding: EdgeInsets.all(8.0),
                      child: Center(
                        child: CircularProgressIndicator(),
                      ),
                    );
                  }
                  final item = items.elementAt(index);
                  return switch (item) {
                    Peripheral() => PeripheralListItem(peripheral: item),
                    ScanResult() => ScanResultListItem(scanResult: item),
                    _ => const SizedBox(),
                  };
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

class PeripheralListItem extends StatelessWidget {
  const PeripheralListItem({
    required this.peripheral,
    super.key,
  });

  final Peripheral peripheral;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              RssiIcon(
                value: peripheral.initialRssi ?? 0,
              ),
              IconButton(
                icon: const Icon(Icons.bluetooth_rounded, size: 20),
                onPressed: () {},
              ),
              IconButton(
                icon: const Icon(Icons.search_rounded, size: 20),
                onPressed: () {},
              ),
            ],
          ),
          Text(peripheral.name ?? 'Unknown'),
        ],
      ),
    );
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

  @override
  void initState() {
    super.initState();

    _connectionStateSubscription =
        widget.scanResult.peripheral.stateStream.listen(onConnectionState);
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
              RssiIcon(
                value: widget.scanResult.peripheral.initialRssi ?? 0,
              ),
              switch (_connectionState) {
                ConnectionState.connected => IconButton(
                    icon: const Icon(Icons.bluetooth_rounded, size: 20),
                    color: const Color(0xFF0082FC),
                    onPressed: disconnect,
                  ),
                ConnectionState.connecting ||
                ConnectionState.disconnecting =>
                  const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(),
                  ),
                _ => IconButton(
                    icon: const Icon(Icons.bluetooth_rounded, size: 20),
                    onPressed: connect,
                  ),
              },
              IconButton(
                icon: const Icon(Icons.search_rounded, size: 20),
                onPressed: () {},
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

class RssiIcon extends StatelessWidget {
  const RssiIcon({
    required this.value,
    super.key,
  });

  final num? value;

  /// • A more strong connection is between -30 to -55
  /// • A strong connection starts from -55 to -67
  /// • A terrible connection starts from -80 to -90
  /// • An unusable connection starts from -90 and below
  @override
  Widget build(BuildContext context) {
    switch (value) {
      case null:
        return const Icon(Icons.wifi_off_rounded);
      case > -67:
        return const Icon(Icons.wifi_rounded);
      case > -80 && <= -67:
        return const Icon(Icons.wifi_2_bar_rounded);
      case > -90 && <= -80:
        return const Icon(Icons.wifi_1_bar_rounded);
      default:
        return const Icon(Icons.wifi_off_rounded);
    }
  }
}
