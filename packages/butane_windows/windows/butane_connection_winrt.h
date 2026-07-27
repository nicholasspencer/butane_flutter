#ifndef PACKAGES_BUTANE_WINDOWS_WINDOWS_BUTANE_CONNECTION_WINRT_H_
#define PACKAGES_BUTANE_WINDOWS_WINDOWS_BUTANE_CONNECTION_WINRT_H_

#include "butane_connection.h"

#include <winrt/Windows.Devices.Bluetooth.GenericAttributeProfile.h>

#include <memory>
#include <mutex>
#include <unordered_map>

namespace butane_windows {

class WindowsConnectionBackend final : public ConnectionBackend {
 public:
  WindowsConnectionBackend() = default;
  ~WindowsConnectionBackend() override;

  void Connect(uint64_t address, PeripheralSession session,
               StateCallback on_state, ConnectCallback on_complete) override;
  void Disconnect(uint64_t address) override;
  ConnectionState State(uint64_t address) const override;

 private:
  struct ConnectionEntry {
    explicit ConnectionEntry(PeripheralSession value, StateCallback callback)
        : session(std::move(value)), on_state(std::move(callback)) {}

    winrt::Windows::Devices::Bluetooth::BluetoothLEDevice device{nullptr};
    winrt::Windows::Devices::Bluetooth::GenericAttributeProfile::GattSession
        gatt_session{nullptr};
    winrt::Windows::Devices::Bluetooth::BluetoothLEDevice::
        ConnectionStatusChanged_revoker status_revoker;
    PeripheralSession session;
    StateCallback on_state;
    ConnectionState state = ConnectionState::kConnecting;
  };

  winrt::fire_and_forget ConnectAsync(uint64_t address,
                                     std::shared_ptr<ConnectionEntry> entry,
                                     ConnectCallback on_complete);
  void Publish(uint64_t address, ConnectionState state);
  void Fail(uint64_t address, const std::shared_ptr<ConnectionEntry>& entry,
            ConnectCallback on_complete, std::string message);
  static void Close(ConnectionEntry& entry);

  mutable std::mutex mutex_;
  std::unordered_map<uint64_t, std::shared_ptr<ConnectionEntry>> entries_;
};

}  // namespace butane_windows

#endif
