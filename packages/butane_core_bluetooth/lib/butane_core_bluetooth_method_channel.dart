import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'butane_core_bluetooth_platform_interface.dart';

/// An implementation of [ButaneCoreBluetoothPlatform] that uses method channels.
class MethodChannelButaneCoreBluetooth extends ButaneCoreBluetoothPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('butane_core_bluetooth');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }
}
