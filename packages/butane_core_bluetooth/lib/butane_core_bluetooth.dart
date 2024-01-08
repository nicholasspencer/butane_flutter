library butane.core_bluetooth;

import 'package:butane_platform_interface/butane_platform_interface.dart';
import 'package:butane_platform_interface/channels.dart';

final class ButaneCoreBluetooth extends ButanePlatform {
  static void registerWith() {
    ButanePlatformInterface.instance =
        ButaneCoreBluetooth() as ButanePlatformInterface;
  }
}
