import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'butane_android_method_channel.dart';

abstract class ButaneAndroidPlatform extends PlatformInterface {
  /// Constructs a ButaneAndroidPlatform.
  ButaneAndroidPlatform() : super(token: _token);

  static final Object _token = Object();

  static ButaneAndroidPlatform _instance = MethodChannelButaneAndroid();

  /// The default instance of [ButaneAndroidPlatform] to use.
  ///
  /// Defaults to [MethodChannelButaneAndroid].
  static ButaneAndroidPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [ButaneAndroidPlatform] when
  /// they register themselves.
  static set instance(ButaneAndroidPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
