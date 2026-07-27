import 'package:args/args.dart';
import 'package:butane_grid_assets/butane_grid_assets.dart';
import 'package:test/test.dart';

const FollowerEndpoint _endpoint = FollowerEndpoint(
  vmServiceUri: 'ws://127.0.0.1:5599/test/ws',
  station: 'test-station',
);

class _RecordingLauncher implements FollowerLauncher {
  final List<LaunchSpec> launches = [];

  @override
  Future<LaunchedDaemon> launch(LaunchSpec spec) async {
    launches.add(spec);
    return const LaunchedDaemon(pid: 42, pgid: 42, endpoint: _endpoint);
  }
}

ArgResults _serveArgs([List<String> arguments = const []]) {
  final parser = ArgParser();
  configureBurnServeFlags(parser);
  return parser.parse(['--harness-dir', '/tmp/butane_harness', ...arguments]);
}

void main() {
  group('BurnTargetFollowerLauncher', () {
    late _RecordingLauncher ios;
    late _RecordingLauncher android;
    late _RecordingLauncher desktop;
    late BurnTargetFollowerLauncher launcher;

    setUp(() {
      ios = _RecordingLauncher();
      android = _RecordingLauncher();
      desktop = _RecordingLauncher();
      launcher = BurnTargetFollowerLauncher(
        ios: () => ios,
        android: () => android,
        desktop: () => desktop,
      );
    });

    Future<void> expectDispatch(
      String target,
      _RecordingLauncher expected,
    ) async {
      final spec = LaunchSpec(
        app: 'butane_harness',
        target: target,
        scenario: 'smoke',
      );
      await launcher.launch(spec);
      expect(expected.launches, [same(spec)]);
      for (final other in [ios, android, desktop]) {
        if (!identical(other, expected)) expect(other.launches, isEmpty);
      }
    }

    test('dispatches ios to the iOS launcher', () async {
      await expectDispatch('ios', ios);
    });

    test('dispatches android to the Android launcher', () async {
      await expectDispatch('android', android);
    });

    test('dispatches macos to the desktop launcher', () async {
      await expectDispatch('macos', desktop);
    });

    test('dispatches linux to the desktop launcher', () async {
      await expectDispatch('linux', desktop);
    });

    test('refuses an unknown target loudly', () {
      expect(
        () => launcher.launch(
          const LaunchSpec(app: 'butane_harness', target: 'solaris'),
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'unsupported burn follower target "solaris" '
                '(supported: ios, android, macos, linux)',
          ),
        ),
      );
      expect(ios.launches, isEmpty);
      expect(android.launches, isEmpty);
      expect(desktop.launches, isEmpty);
    });
  });

  group('butaneBurnServeHandler', () {
    test('composes a macos dispatch through the desktop launcher', () async {
      final ios = _RecordingLauncher();
      final android = _RecordingLauncher();
      final desktop = _RecordingLauncher();
      final served = butaneBurnServeHandler(
        _serveArgs(),
        (_) {},
        iosLauncher: () => ios,
        androidLauncher: () => android,
        desktopLauncher: () => desktop,
      );
      const spec = LaunchSpec(app: 'butane_harness', target: 'macos');

      final result = await served.handler(spec.toJson());

      expect(result, _endpoint.toJson());
      expect(desktop.launches.single.toJson(), spec.toJson());
      expect(ios.launches, isEmpty);
      expect(android.launches, isEmpty);
    });

    test('ios without a device id refuses before constructing a launcher',
        () async {
      final served = butaneBurnServeHandler(
        _serveArgs(),
        (_) {},
        desktopLauncher: _RecordingLauncher.new,
      );

      await expectLater(
        served.handler(
          const LaunchSpec(app: 'butane_harness', target: 'ios').toJson(),
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'burn follower target "ios" requires serve --device-id',
          ),
        ),
      );
    });

    test('macos remains usable without a device id', () async {
      final desktop = _RecordingLauncher();
      final served = butaneBurnServeHandler(
        _serveArgs(),
        (_) {},
        desktopLauncher: () => desktop,
      );
      const spec = LaunchSpec(app: 'butane_harness', target: 'macos');

      final result = await served.handler(spec.toJson());

      expect(result, _endpoint.toJson());
      expect(desktop.launches.single.toJson(), spec.toJson());
    });
  });
}
