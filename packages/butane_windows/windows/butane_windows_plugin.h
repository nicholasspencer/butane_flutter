#ifndef FLUTTER_PLUGIN_BUTANE_WINDOWS_PLUGIN_H_
#define FLUTTER_PLUGIN_BUTANE_WINDOWS_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>

namespace butane_windows {

class ButaneWindowsPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  ButaneWindowsPlugin();

  virtual ~ButaneWindowsPlugin();

  // Disallow copy and assign.
  ButaneWindowsPlugin(const ButaneWindowsPlugin&) = delete;
  ButaneWindowsPlugin& operator=(const ButaneWindowsPlugin&) = delete;

  // Called when a method is called on this plugin's channel from Dart.
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
};

}  // namespace butane_windows

#endif  // FLUTTER_PLUGIN_BUTANE_WINDOWS_PLUGIN_H_
