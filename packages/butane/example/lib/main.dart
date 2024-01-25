import 'dart:async';
import 'dart:typed_data';

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

  final Map<Service, Iterable<Characteristic>> _characteristics = {};

  @override
  void initState() {
    super.initState();

    _connectionStateSubscription =
        widget.scanResult.peripheral.stateStream.listen(onConnectionState);

    initCharacteristics();
  }

  Future<void> initCharacteristics() async {
    final Map<Service, Iterable<Characteristic>> characteristics = {};
    final peripheral = widget.scanResult.peripheral;
    final services = await peripheral.services;
    for (final service in services) {
      final char = await service.characteristics;
      characteristics[service] = char;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _characteristics.clear();
      _characteristics.addAll(characteristics);
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
                  IconButton(
                    onPressed: disconnect,
                    icon: const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(),
                    ),
                  ),
                _ => IconButton(
                    icon: const Icon(Icons.bluetooth_rounded, size: 20),
                    onPressed: connect,
                  ),
              },
              if (_connectionState == ConnectionState.connected)
                IconButton(
                  icon: const Icon(Icons.search_rounded, size: 20),
                  onPressed: discover,
                ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ScanResultDetails(scanResult: widget.scanResult),
              if (_characteristics.isNotEmpty)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Text('Services: '),
                      ],
                    ),
                    for (final entry in _characteristics.entries)
                      ServiceDetails(
                        service: entry.key,
                        characteristics: entry.value,
                      ),
                  ],
                ),
            ],
          ),
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

  void discover() async {
    final Map<Service, Iterable<Characteristic>> characteristics = {};
    final peripheral = widget.scanResult.peripheral;
    await peripheral.discoverServices();
    final services = await peripheral.services;
    print('Discovered services: ${services.map((e) => e.uuid.toString())}');
    for (final service in services) {
      print('Discovering characteristics for ${service.uuid.toString()}');
      await service.discoverCharacteristics();
      print('Discovered characteristics for ${service.uuid.toString()}');
      final char = await service.characteristics;
      print(
        'Discovered characteristics for ${service.uuid.toString()}: ${char.map((e) => e.uuid.toString())}',
      );
      characteristics[service] = char;
    }

    setState(() {
      _characteristics.clear();
      _characteristics.addAll(characteristics);
    });
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

class ServiceDetails extends StatelessWidget {
  const ServiceDetails({
    required this.service,
    required this.characteristics,
    super.key,
  });

  final Service service;

  final Iterable<Characteristic> characteristics;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.subdirectory_arrow_right_rounded,
              size: 20,
            ),
            Text('Service: ${service.uuid}'),
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                SizedBox(
                  width: 20,
                ),
                Icon(
                  Icons.subdirectory_arrow_right_rounded,
                  size: 20,
                ),
                Text('Characteristics: '),
              ],
            ),
            for (final characteristic in characteristics)
              CharacteristicDetails(characteristic: characteristic)
          ],
        ),
      ],
    );
  }
}

class CharacteristicDetails extends StatefulWidget {
  const CharacteristicDetails({
    super.key,
    required this.characteristic,
  });

  final Characteristic characteristic;

  @override
  State<CharacteristicDetails> createState() => _CharacteristicDetailsState();
}

class _CharacteristicDetailsState extends State<CharacteristicDetails> {
  Stream<Uint8List>? _values;

  @override
  void initState() {
    super.initState();

    _values = widget.characteristic.observe();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const SizedBox(
              width: 40,
            ),
            const Icon(
              Icons.subdirectory_arrow_right_rounded,
              size: 20,
            ),
            Text(widget.characteristic.uuid.toString()),
          ],
        ),
        Row(
          children: [
            const SizedBox(
              width: 60,
            ),
            const Icon(
              Icons.subdirectory_arrow_right_rounded,
              size: 20,
            ),
            const Text('Value: '),
            StreamBuilder<Uint8List>(
              stream: _values,
              builder: (context, snapshot) {
                if (snapshot.hasData) {
                  return Text(snapshot.data!.toString());
                } else if (snapshot.hasError) {
                  return Text(snapshot.error.toString());
                } else {
                  return const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(),
                  );
                }
              },
            ),
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
