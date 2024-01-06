import 'dart:async';

import 'package:butane_core_bluetooth/butane_core_bluetooth.dart';
import 'package:butane_platform_interface/butane_platform_interface.dart';
import 'package:flutter/material.dart';

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

  @override
  void initState() {
    super.initState();

    ButaneCoreBluetooth.registerWith();

    _managerStateStream = manager.stateStream.listen(onManagerState);
  }

  void onManagerState(PeerManagerState state) {
    if (state == PeerManagerState.poweredOn) {
      _scanSubscription = manager.scan().listen(onScanResult);
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
        ),
        body: _scanResults.isEmpty
            ? const Center(
                child: CircularProgressIndicator(),
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
  @override
  Widget build(BuildContext context) {
    final localName =
        widget.scanResult.advertisementData.localName ?? 'Unknown';
    final name = widget.scanResult.peripheral.name ?? 'Unknown';
    final manufacturerData =
        widget.scanResult.advertisementData.manufacturerData;
    final advertisedServices =
        widget.scanResult.advertisementData.serviceUuids ?? [];
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              const Icon(Icons.bluetooth_rounded, size: 20),
              IconButton(
                icon: const Icon(Icons.search_rounded, size: 20),
                onPressed: () {},
              ),
            ],
          ),
          Column(
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
                    '${widget.scanResult.advertisementData.txPowerLevel}',
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
          ),
        ],
      ),
    );
  }
}
