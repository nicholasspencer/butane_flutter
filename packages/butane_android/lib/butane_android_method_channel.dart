import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'butane_android_platform_interface.dart';

/// An implementation of [ButaneAndroidPlatform] that uses method channels.
class MethodChannelButaneAndroid extends ButaneAndroidPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('butane_android');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }
}
