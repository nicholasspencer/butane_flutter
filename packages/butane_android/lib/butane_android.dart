
import 'butane_android_platform_interface.dart';

class ButaneAndroid {
  Future<String?> getPlatformVersion() {
    return ButaneAndroidPlatform.instance.getPlatformVersion();
  }
}
