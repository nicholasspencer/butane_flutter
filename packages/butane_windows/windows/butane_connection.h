#ifndef PACKAGES_BUTANE_WINDOWS_WINDOWS_BUTANE_CONNECTION_H_
#define PACKAGES_BUTANE_WINDOWS_WINDOWS_BUTANE_CONNECTION_H_

#include "Api.gen.h"

#include <winrt/Windows.Devices.Bluetooth.h>

#include <cstdint>
#include <functional>
#include <optional>

namespace butane_windows {

struct ConnectionSnapshot {
  PeripheralSession session;
  ConnectionState state;
};

class ConnectionBackend {
 public:
  using StateCallback = std::function<void(ConnectionSnapshot)>;
  using ConnectCallback = std::function<void(std::optional<FlutterError>)>;

  virtual ~ConnectionBackend() = default;
  virtual void Connect(uint64_t address, PeripheralSession session,
                       StateCallback on_state,
                       ConnectCallback on_complete) = 0;
  virtual void Disconnect(uint64_t address) = 0;
  virtual ConnectionState State(uint64_t address) const = 0;
};

ConnectionState MapConnectionStatus(
    winrt::Windows::Devices::Bluetooth::BluetoothConnectionStatus status);

}  // namespace butane_windows

#endif
