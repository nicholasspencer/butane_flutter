#include "butane_connection.h"

namespace butane_windows {

ConnectionState MapConnectionStatus(
    winrt::Windows::Devices::Bluetooth::BluetoothConnectionStatus status) {
  using winrt::Windows::Devices::Bluetooth::BluetoothConnectionStatus;
  return status == BluetoothConnectionStatus::Connected
             ? ConnectionState::kConnected
             : ConnectionState::kDisconnected;
}

}  // namespace butane_windows
