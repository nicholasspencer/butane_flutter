import 'package:flutter_test/flutter_test.dart';
import 'package:butane_core_bluetooth/butane_core_bluetooth.dart';
import 'package:butane_core_bluetooth/butane_core_bluetooth_platform_interface.dart';
import 'package:butane_core_bluetooth/butane_core_bluetooth_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockButaneCoreBluetoothPlatform
    with MockPlatformInterfaceMixin
    implements ButaneCoreBluetoothPlatform {

  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final ButaneCoreBluetoothPlatform initialPlatform = ButaneCoreBluetoothPlatform.instance;

  test('$MethodChannelButaneCoreBluetooth is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelButaneCoreBluetooth>());
  });

  test('getPlatformVersion', () async {
    ButaneCoreBluetooth butaneCoreBluetoothPlugin = ButaneCoreBluetooth();
    MockButaneCoreBluetoothPlatform fakePlatform = MockButaneCoreBluetoothPlatform();
    ButaneCoreBluetoothPlatform.instance = fakePlatform;

    expect(await butaneCoreBluetoothPlugin.getPlatformVersion(), '42');
  });
}
