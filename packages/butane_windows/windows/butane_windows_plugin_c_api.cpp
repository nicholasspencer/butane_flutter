#include "include/butane_windows/butane_windows_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "butane_windows_plugin.h"

void ButaneWindowsPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  butane_windows::ButaneWindowsPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
