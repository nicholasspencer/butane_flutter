import 'package:butane_platform_interface/butane_platform_interface.dart';
import 'package:butane_platform_interface/channels.dart';

final class ButaneAndroid extends ButanePlatform {
  static void registerWith() {
    ButanePlatformInterface.instance = ButaneAndroid();
  }
}
