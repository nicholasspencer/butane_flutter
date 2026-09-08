import 'dart:io';

import 'package:butane_grid_assets/butane_grid_assets.dart';
import 'package:test/test.dart';

const _valid = BurnOrderInputs(
  followerDevice: 'device',
  harnessDirectory: '/harness',
  leonardDrive: '/leonard',
);

final class _FakeCatalog implements FlutterDeviceCatalog {
  _FakeCatalog({this.devices = const [], this.error, this.onList});

  final List<FlutterDevice> devices;
  final Object? error;
  final void Function()? onList;
  var calls = 0;

  @override
  Future<List<FlutterDevice>> listDevices() async {
    calls++;
    onList?.call();
    if (error case final error?) throw error;
    return devices;
  }
}

BurnPreflight _preflight({
  FlutterDeviceCatalog? devices,
  BurnHostReachability? hostReachable,
  BurnPeerReachability? peerReachable,
  BurnPathPredicate directoryExists = _directoryExists,
  BurnPathPredicate fileExists = _fileExists,
}) => BurnPreflight(
  directoryExists: directoryExists,
  fileExists: fileExists,
  devices: devices ?? _FakeCatalog(),
  hostReachable: hostReachable ?? (_) async => true,
  peerReachable: peerReachable ?? (_, _) async => true,
);

Matcher _stateError(String message) => throwsA(
  isA<StateError>().having((error) => error.message, 'message', message),
);

void main() {
  test('returns valid inputs unchanged without invoking probes', () async {
    final devices = _FakeCatalog();
    var hostCalls = 0;
    var peerCalls = 0;
    final preflight = _preflight(
      devices: devices,
      hostReachable: (_) async {
        hostCalls++;
        return true;
      },
      peerReachable: (_, _) async {
        peerCalls++;
        return true;
      },
    );

    expect(await preflight.validate(_valid), same(_valid));
    expect(devices.calls, 0);
    expect(hostCalls, 0);
    expect(peerCalls, 0);
  });

  for (final entry in <({String name, BurnOrderInputs inputs, String error})>[
    (
      name: 'missing device',
      inputs: const BurnOrderInputs(
        followerDevice: '',
        harnessDirectory: '/harness',
        leonardDrive: '/leonard',
      ),
      error: 'burn preflight missing burn.follower_device',
    ),
    (
      name: 'missing harness directory',
      inputs: const BurnOrderInputs(
        followerDevice: 'device',
        harnessDirectory: '',
        leonardDrive: '/leonard',
      ),
      error: 'burn preflight invalid burn.harness_dir: ',
    ),
    (
      name: 'invalid harness directory',
      inputs: const BurnOrderInputs(
        followerDevice: 'device',
        harnessDirectory: '/missing',
        leonardDrive: '/leonard',
      ),
      error: 'burn preflight invalid burn.harness_dir: /missing',
    ),
    (
      name: 'missing leonard drive',
      inputs: const BurnOrderInputs(
        followerDevice: 'device',
        harnessDirectory: '/harness',
        leonardDrive: '',
      ),
      error: 'burn preflight invalid burn.leonard_drive: ',
    ),
    (
      name: 'invalid leonard drive',
      inputs: const BurnOrderInputs(
        followerDevice: 'device',
        harnessDirectory: '/harness',
        leonardDrive: '/missing',
      ),
      error: 'burn preflight invalid burn.leonard_drive: /missing',
    ),
  ]) {
    test(entry.name, () async {
      await expectLater(
        _preflight().validate(entry.inputs),
        _stateError(entry.error),
      );
    });
  }

  test('satisfies every declared precondition once and in order', () async {
    final calls = <String>[];
    final devices = _FakeCatalog(
      devices: const [
        FlutterDevice(
          id: 'device',
          name: 'iPhone',
          targetPlatform: 'ios',
          emulator: false,
        ),
      ],
      onList: () => calls.add('follower'),
    );
    final inputs = BurnOrderInputs(
      followerDevice: 'device',
      harnessDirectory: '/harness',
      leonardDrive: '/leonard',
      windowsHost: 'yoga-test',
      preconditions: const [
        BurnPrecondition.followerIosAttached(),
        BurnPrecondition.windowsHostReachable(),
        BurnPrecondition.peer(host: 'bench.local', port: 6123),
      ],
    );
    final preflight = _preflight(
      devices: devices,
      hostReachable: (host) async {
        calls.add('windows:$host');
        return true;
      },
      peerReachable: (host, port) async {
        calls.add('peer:$host:$port');
        return true;
      },
    );

    expect(await preflight.validate(inputs), same(inputs));
    expect(calls, ['follower', 'windows:yoga-test', 'peer:bench.local:6123']);
    expect(devices.calls, 1);
  });

  test('requires exactly one physical iOS row with the follower id', () async {
    for (final devices in const <List<FlutterDevice>>[
      [],
      [
        FlutterDevice(
          id: 'device',
          name: 'simulator',
          targetPlatform: 'ios',
          emulator: true,
        ),
      ],
      [
        FlutterDevice(
          id: 'device',
          name: 'Android',
          targetPlatform: 'android-arm64',
          emulator: false,
        ),
      ],
      [
        FlutterDevice(
          id: 'device',
          name: 'iPhone one',
          targetPlatform: 'ios',
          emulator: false,
        ),
        FlutterDevice(
          id: 'device',
          name: 'iPhone two',
          targetPlatform: 'ios',
          emulator: false,
        ),
      ],
    ]) {
      await expectLater(
        _preflight(devices: _FakeCatalog(devices: devices)).validate(
          const BurnOrderInputs(
            followerDevice: 'device',
            harnessDirectory: '/harness',
            leonardDrive: '/leonard',
            preconditions: [BurnPrecondition.followerIosAttached()],
          ),
        ),
        _stateError('burn preflight held follower-ios-attached: device=device'),
      );
    }
  });

  test('catalog exceptions become named follower holds', () async {
    await expectLater(
      _preflight(
        devices: _FakeCatalog(error: StateError('flutter broke')),
      ).validate(
        const BurnOrderInputs(
          followerDevice: 'device',
          harnessDirectory: '/harness',
          leonardDrive: '/leonard',
          preconditions: [BurnPrecondition.followerIosAttached()],
        ),
      ),
      _stateError('burn preflight held follower-ios-attached: device=device'),
    );
  });

  for (final throws in const [false, true]) {
    test(
      'Windows ${throws ? 'exception' : 'false'} becomes a named hold',
      () async {
        await expectLater(
          _preflight(
            hostReachable: (host) async {
              expect(host, 'yoga-test');
              if (throws) throw StateError('ssh broke');
              return false;
            },
          ).validate(
            const BurnOrderInputs(
              followerDevice: 'device',
              harnessDirectory: '/harness',
              leonardDrive: '/leonard',
              windowsHost: 'yoga-test',
              preconditions: [BurnPrecondition.windowsHostReachable()],
            ),
          ),
          _stateError(
            'burn preflight held windows-host-reachable: host=yoga-test',
          ),
        );
      },
    );

    test(
      'peer ${throws ? 'exception' : 'false'} becomes a named hold',
      () async {
        await expectLater(
          _preflight(
            peerReachable: (host, port) async {
              expect((host, port), ('bench.local', 8123));
              if (throws) throw StateError('socket broke');
              return false;
            },
          ).validate(
            const BurnOrderInputs(
              followerDevice: 'device',
              harnessDirectory: '/harness',
              leonardDrive: '/leonard',
              preconditions: [
                BurnPrecondition.peer(host: 'bench.local', port: 8123),
              ],
            ),
          ),
          _stateError('burn preflight held peer: endpoint=bench.local:8123'),
        );
      },
    );
  }

  test('the first unsatisfied declaration prevents later probes', () async {
    var peerCalls = 0;
    await expectLater(
      _preflight(
        hostReachable: (_) async => false,
        peerReachable: (_, _) async {
          peerCalls++;
          return true;
        },
      ).validate(
        const BurnOrderInputs(
          followerDevice: 'device',
          harnessDirectory: '/harness',
          leonardDrive: '/leonard',
          windowsHost: 'yoga-test',
          preconditions: [
            BurnPrecondition.windowsHostReachable(),
            BurnPrecondition.peer(host: 'bench.local', port: 8123),
          ],
        ),
      ),
      _stateError('burn preflight held windows-host-reachable: host=yoga-test'),
    );
    expect(peerCalls, 0);
  });

  group('systemBurnPreflight', () {
    test('uses the shared exact SSH contract and exit status', () async {
      final calls = <({String executable, List<String> arguments})>[];
      final preflight = systemBurnPreflight(
        directoryExists: _directoryExists,
        fileExists: _fileExists,
        devices: _FakeCatalog(),
        processProbe: (executable, arguments) async {
          calls.add((executable: executable, arguments: arguments));
          return 0;
        },
        socketProbe: (_, _, _) async {},
      );
      final inputs = const BurnOrderInputs(
        followerDevice: 'device',
        harnessDirectory: '/harness',
        leonardDrive: '/leonard',
        windowsHost: 'yoga-test',
        preconditions: [BurnPrecondition.windowsHostReachable()],
      );

      expect(await preflight.validate(inputs), same(inputs));
      expect(calls, hasLength(1));
      expect(calls.single.executable, 'ssh');
      expect(calls.single.arguments, [
        ...kBurnSshOptions,
        'yoga-test',
        'exit 0',
      ]);

      final unavailable = systemBurnPreflight(
        directoryExists: _directoryExists,
        fileExists: _fileExists,
        devices: _FakeCatalog(),
        processProbe: (_, _) async => 255,
        socketProbe: (_, _, _) async {},
      );
      await expectLater(
        unavailable.validate(inputs),
        _stateError(
          'burn preflight held windows-host-reachable: host=yoga-test',
        ),
      );
    });

    test('passes the exact peer endpoint and three-second timeout', () async {
      final calls = <({String host, int port, Duration timeout})>[];
      final preflight = systemBurnPreflight(
        directoryExists: _directoryExists,
        fileExists: _fileExists,
        devices: _FakeCatalog(),
        processProbe: (_, _) async => 0,
        socketProbe: (host, port, timeout) async =>
            calls.add((host: host, port: port, timeout: timeout)),
      );
      final inputs = const BurnOrderInputs(
        followerDevice: 'device',
        harnessDirectory: '/harness',
        leonardDrive: '/leonard',
        preconditions: [BurnPrecondition.peer(host: 'bench.local', port: 8123)],
      );

      expect(await preflight.validate(inputs), same(inputs));
      expect(calls, [
        (host: 'bench.local', port: 8123, timeout: const Duration(seconds: 3)),
      ]);
    });

    test('closes the system TCP connection after connecting', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final accepted = server.first;
      final preflight = systemBurnPreflight(
        directoryExists: _directoryExists,
        fileExists: _fileExists,
        devices: _FakeCatalog(),
        processProbe: (_, _) async => 0,
      );
      final inputs = BurnOrderInputs(
        followerDevice: 'device',
        harnessDirectory: '/harness',
        leonardDrive: '/leonard',
        preconditions: [
          BurnPrecondition.peer(host: '127.0.0.1', port: server.port),
        ],
      );

      try {
        final validation = preflight.validate(inputs);
        final socket = await accepted.timeout(const Duration(seconds: 3));
        final closed = socket.drain<void>();
        expect(await validation, same(inputs));
        await expectLater(
          closed.timeout(const Duration(seconds: 3)),
          completes,
        );
      } finally {
        await server.close();
      }
    });
  });
}

bool _directoryExists(String path) => path == '/harness';
bool _fileExists(String path) => path == '/leonard';
