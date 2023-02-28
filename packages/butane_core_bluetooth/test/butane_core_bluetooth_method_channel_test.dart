import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:butane_core_bluetooth/butane_core_bluetooth_method_channel.dart';

void main() {
  MethodChannelButaneCoreBluetooth platform = MethodChannelButaneCoreBluetooth();
  const MethodChannel channel = MethodChannel('butane_core_bluetooth');

  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    channel.setMockMethodCallHandler((MethodCall methodCall) async {
      return '42';
    });
  });

  tearDown(() {
    channel.setMockMethodCallHandler(null);
  });

  test('getPlatformVersion', () async {
    expect(await platform.getPlatformVersion(), '42');
  });
}
