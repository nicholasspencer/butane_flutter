#include "butane_connection_winrt.h"

#include <winrt/base.h>

#include <string>
#include <utility>
#include <vector>

namespace butane_windows {
namespace {
using winrt::Windows::Devices::Bluetooth::BluetoothLEDevice;
using winrt::Windows::Devices::Bluetooth::GenericAttributeProfile::GattSession;
}  // namespace

WindowsConnectionBackend::~WindowsConnectionBackend() {
  std::vector<uint64_t> addresses;
  {
    const std::scoped_lock lock(mutex_);
    addresses.reserve(entries_.size());
    for (const auto& item : entries_) addresses.push_back(item.first);
  }
  for (uint64_t address : addresses) Disconnect(address);
}

void WindowsConnectionBackend::Connect(uint64_t address,
                                       PeripheralSession session,
                                       StateCallback on_state,
                                       ConnectCallback on_complete) {
  auto entry = std::make_shared<ConnectionEntry>(
      std::move(session), std::move(on_state));
  {
    const std::scoped_lock lock(mutex_);
    const auto [it, inserted] = entries_.emplace(address, entry);
    if (!inserted) {
      on_complete(std::nullopt);
      return;
    }
  }
  entry->on_state(ConnectionSnapshot{entry->session,
                                     ConnectionState::kConnecting});
  ConnectAsync(address, std::move(entry), std::move(on_complete));
}

winrt::fire_and_forget WindowsConnectionBackend::ConnectAsync(
    uint64_t address, std::shared_ptr<ConnectionEntry> entry,
    ConnectCallback on_complete) {
  try {
    auto device =
        co_await BluetoothLEDevice::FromBluetoothAddressAsync(address);
    if (!device) {
      throw winrt::hresult_error(E_FAIL, L"Bluetooth device not found");
    }
    auto gatt_session =
        co_await GattSession::FromDeviceIdAsync(device.BluetoothDeviceId());
    if (!gatt_session) {
      device.Close();
      throw winrt::hresult_error(E_FAIL, L"GATT session unavailable");
    }

    gatt_session.MaintainConnection(true);
    auto revoker = device.ConnectionStatusChanged(
        winrt::auto_revoke,
        [this, address](BluetoothLEDevice const& sender, auto const&) {
          Publish(address, MapConnectionStatus(sender.ConnectionStatus()));
        });
    {
      const std::scoped_lock lock(mutex_);
      const auto it = entries_.find(address);
      if (it == entries_.end() || it->second != entry) {
        revoker.revoke();
        gatt_session.MaintainConnection(false);
        gatt_session.Close();
        device.Close();
        co_return;
      }
      entry->device = device;
      entry->gatt_session = gatt_session;
      entry->status_revoker = std::move(revoker);
    }
    Publish(address, MapConnectionStatus(device.ConnectionStatus()));
    on_complete(std::nullopt);
  } catch (const winrt::hresult_error& error) {
    Fail(address, entry, std::move(on_complete),
         winrt::to_string(error.message()));
  }
}

void WindowsConnectionBackend::Fail(
    uint64_t address, const std::shared_ptr<ConnectionEntry>& entry,
    ConnectCallback on_complete, std::string message) {
  bool retained = false;
  {
    const std::scoped_lock lock(mutex_);
    const auto it = entries_.find(address);
    if (it != entries_.end() && it->second == entry) {
      entries_.erase(it);
      retained = true;
    }
  }
  Close(*entry);
  if (!retained) return;
  entry->state = ConnectionState::kDisconnected;
  entry->on_state(
      ConnectionSnapshot{entry->session, ConnectionState::kDisconnected});
  on_complete(FlutterError("connection_failed", std::move(message)));
}

void WindowsConnectionBackend::Publish(uint64_t address,
                                       ConnectionState state) {
  std::shared_ptr<ConnectionEntry> entry;
  {
    const std::scoped_lock lock(mutex_);
    const auto it = entries_.find(address);
    if (it == entries_.end()) return;
    entry = it->second;
    entry->state = state;
  }
  entry->on_state(ConnectionSnapshot{entry->session, state});
}

void WindowsConnectionBackend::Disconnect(uint64_t address) {
  std::shared_ptr<ConnectionEntry> entry;
  {
    const std::scoped_lock lock(mutex_);
    const auto it = entries_.find(address);
    if (it == entries_.end()) return;
    entry = std::move(it->second);
    entries_.erase(it);
    entry->state = ConnectionState::kDisconnecting;
  }
  entry->on_state(
      ConnectionSnapshot{entry->session, ConnectionState::kDisconnecting});
  Close(*entry);
  entry->state = ConnectionState::kDisconnected;
  entry->on_state(
      ConnectionSnapshot{entry->session, ConnectionState::kDisconnected});
}

ConnectionState WindowsConnectionBackend::State(uint64_t address) const {
  const std::scoped_lock lock(mutex_);
  const auto it = entries_.find(address);
  return it == entries_.end() ? ConnectionState::kDisconnected
                              : it->second->state;
}

void WindowsConnectionBackend::Close(ConnectionEntry& entry) {
  try {
    entry.status_revoker.revoke();
  } catch (const winrt::hresult_error&) {
  }
  try {
    if (entry.gatt_session) {
      entry.gatt_session.MaintainConnection(false);
      entry.gatt_session.Close();
    }
  } catch (const winrt::hresult_error&) {
  }
  try {
    if (entry.device) entry.device.Close();
  } catch (const winrt::hresult_error&) {
  }
}

}  // namespace butane_windows
