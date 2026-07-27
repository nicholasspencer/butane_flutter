#ifndef PACKAGES_BUTANE_WINDOWS_WINDOWS_BUTANE_CENTRAL_WINRT_H_
#define PACKAGES_BUTANE_WINDOWS_WINDOWS_BUTANE_CENTRAL_WINRT_H_
#include "butane_central.h"
#include <winrt/Windows.Devices.Bluetooth.Advertisement.h>
#include <winrt/Windows.Devices.Bluetooth.h>
#include <winrt/Windows.Devices.Radios.h>
#include <functional>
#include <optional>
#include <vector>
namespace butane_windows {
class RssiCache;
class CentralBackend {
 public:
  using StateCallback = std::function<void(ClientState)>;
  using AdvertisementCallback = std::function<void(AdvertisementEvent)>;
  virtual ~CentralBackend() = default;
  virtual void QueryState(StateCallback callback) = 0;
  virtual std::optional<FlutterError> StartScan(
      const std::vector<std::string>& service_uuids,
      AdvertisementCallback callback) = 0;
  virtual void StopScan() = 0;
};
class WindowsCentralBackend final : public CentralBackend {
 public:
  explicit WindowsCentralBackend(RssiCache& rssi_cache);
  ~WindowsCentralBackend() override;
  void QueryState(StateCallback callback) override;
  std::optional<FlutterError> StartScan(
      const std::vector<std::string>& service_uuids,
      AdvertisementCallback callback) override;
  void StopScan() override;
 private:
  winrt::fire_and_forget QueryStateAsync(StateCallback callback);
  static NativeRadioState ToNativeRadioState(
      winrt::Windows::Devices::Radios::RadioState state);
  static AdvertisementEvent CopyAdvertisement(
      const winrt::Windows::Devices::Bluetooth::Advertisement::
          BluetoothLEAdvertisementReceivedEventArgs& args);
  RssiCache& rssi_cache_;
  winrt::Windows::Devices::Bluetooth::BluetoothAdapter adapter_{nullptr};
  winrt::Windows::Devices::Radios::Radio radio_{nullptr};
  winrt::Windows::Devices::Bluetooth::Advertisement::
      BluetoothLEAdvertisementWatcher watcher_{nullptr};
  winrt::Windows::Devices::Radios::Radio::StateChanged_revoker state_revoker_;
  winrt::Windows::Devices::Bluetooth::Advertisement::
      BluetoothLEAdvertisementWatcher::Received_revoker received_revoker_;
  StateCallback state_callback_;
  AdvertisementCallback advertisement_callback_;
};
}  // namespace butane_windows
#endif
