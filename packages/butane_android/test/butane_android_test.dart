import 'package:flutter_test/flutter_test.dart';
import 'package:butane_android/butane_android.dart';
import 'package:butane_android/butane_android_platform_interface.dart';
import 'package:butane_android/butane_android_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockButaneAndroidPlatform
    with MockPlatformInterfaceMixin
    implements ButaneAndroidPlatform {

  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final ButaneAndroidPlatform initialPlatform = ButaneAndroidPlatform.instance;

  test('$MethodChannelButaneAndroid is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelButaneAndroid>());
  });

  test('getPlatformVersion', () async {
    ButaneAndroid butaneAndroidPlugin = ButaneAndroid();
    MockButaneAndroidPlatform fakePlatform = MockButaneAndroidPlatform();
    ButaneAndroidPlatform.instance = fakePlatform;

    expect(await butaneAndroidPlugin.getPlatformVersion(), '42');
  });
}
