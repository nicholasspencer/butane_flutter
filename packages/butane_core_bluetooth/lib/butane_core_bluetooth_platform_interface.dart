import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'butane_core_bluetooth_method_channel.dart';

abstract class ButaneCoreBluetoothPlatform extends PlatformInterface {
  /// Constructs a ButaneCoreBluetoothPlatform.
  ButaneCoreBluetoothPlatform() : super(token: _token);

  static final Object _token = Object();

  static ButaneCoreBluetoothPlatform _instance = MethodChannelButaneCoreBluetooth();

  /// The default instance of [ButaneCoreBluetoothPlatform] to use.
  ///
  /// Defaults to [MethodChannelButaneCoreBluetooth].
  static ButaneCoreBluetoothPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [ButaneCoreBluetoothPlatform] when
  /// they register themselves.
  static set instance(ButaneCoreBluetoothPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
