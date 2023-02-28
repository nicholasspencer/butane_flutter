
import 'butane_core_bluetooth_platform_interface.dart';

class ButaneCoreBluetooth {
  Future<String?> getPlatformVersion() {
    return ButaneCoreBluetoothPlatform.instance.getPlatformVersion();
  }
}
