#include "butane_connection_winrt.h"

#include <winrt/Windows.Devices.Bluetooth.GenericAttributeProfile.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/base.h>

#include <utility>
#include <vector>

namespace butane_windows {
namespace {
using winrt::Windows::Devices::Bluetooth::BluetoothLEDevice;
using winrt::Windows::Devices::Bluetooth::GenericAttributeProfile::GattSession;

class WinrtNativeConnection final
    : public NativeConnection,
      public std::enable_shared_from_this<WinrtNativeConnection> {
 public:
  explicit WinrtNativeConnection(uint64_t address) : address_(address) {}

  void Start(StateCallback on_state, ReadyCallback on_ready) override {
    {
      const std::scoped_lock lock(mutex_);
      if (closed_) return;
      on_state_ = std::move(on_state);
      on_ready_ = std::move(on_ready);
    }
    ConnectAsync(shared_from_this());
  }

  void Close() override {
    BluetoothLEDevice device{nullptr};
    GattSession session{nullptr};
    BluetoothLEDevice::ConnectionStatusChanged_revoker revoker;
    {
      const std::scoped_lock lock(mutex_);
      if (closed_) return;
      closed_ = true;
      on_state_ = nullptr;
      on_ready_ = nullptr;
      device = std::move(device_);
      session = std::move(session_);
      revoker = std::move(status_revoker_);
    }
    Cleanup(device, session, revoker);
  }

 private:
  static void Cleanup(
      BluetoothLEDevice& device, GattSession& session,
      BluetoothLEDevice::ConnectionStatusChanged_revoker& revoker) {
    try {
      revoker.revoke();
    } catch (const winrt::hresult_error&) {
    }
    try {
      if (session) {
        session.MaintainConnection(false);
        session.Close();
      }
    } catch (const winrt::hresult_error&) {
    }
    try {
      if (device) device.Close();
    } catch (const winrt::hresult_error&) {
    }
  }

  bool IsClosed() const {
    const std::scoped_lock lock(mutex_);
    return closed_;
  }

  void Complete(std::optional<std::string> error) {
    ReadyCallback callback;
    {
      const std::scoped_lock lock(mutex_);
      if (closed_ || ready_reported_) return;
      ready_reported_ = true;
      callback = std::move(on_ready_);
    }
    if (callback) callback(std::move(error));
  }

  static winrt::fire_and_forget ConnectAsync(
      std::shared_ptr<WinrtNativeConnection> self) {
    BluetoothLEDevice device{nullptr};
    GattSession session{nullptr};
    BluetoothLEDevice::ConnectionStatusChanged_revoker revoker;
    try {
      device =
          co_await BluetoothLEDevice::FromBluetoothAddressAsync(self->address_);
      if (self->IsClosed()) {
        Cleanup(device, session, revoker);
        co_return;
      }
      if (!device) {
        self->Complete("Bluetooth device not found");
        co_return;
      }

      session = co_await GattSession::FromDeviceIdAsync(
          device.BluetoothDeviceId());
      if (self->IsClosed()) {
        Cleanup(device, session, revoker);
        co_return;
      }
      if (!session) {
        Cleanup(device, session, revoker);
        self->Complete("GATT session unavailable");
        co_return;
      }

      session.MaintainConnection(true);
      std::weak_ptr<WinrtNativeConnection> weak = self;
      revoker = device.ConnectionStatusChanged(
          winrt::auto_revoke,
          [weak](BluetoothLEDevice const& sender, auto const&) {
            const auto owner = weak.lock();
            if (!owner) return;
            StateCallback callback;
            {
              const std::scoped_lock lock(owner->mutex_);
              if (owner->closed_) return;
              callback = owner->on_state_;
            }
            if (callback) {
              callback(MapConnectionStatus(sender.ConnectionStatus()));
            }
          });

      const auto current_state =
          MapConnectionStatus(device.ConnectionStatus());
      StateCallback state_callback;
      {
        const std::scoped_lock lock(self->mutex_);
        if (self->closed_) {
          // Cleanup below must happen without holding the object's mutex.
        } else {
          self->device_ = std::move(device);
          self->session_ = std::move(session);
          self->status_revoker_ = std::move(revoker);
          state_callback = self->on_state_;
        }
      }
      if (self->IsClosed()) {
        Cleanup(device, session, revoker);
        co_return;
      }
      if (state_callback) {
        state_callback(current_state);
      }
      self->Complete(std::nullopt);
    } catch (const winrt::hresult_error& error) {
      Cleanup(device, session, revoker);
      if (!self->IsClosed()) {
        self->Complete(winrt::to_string(error.message()));
      }
    }
  }

  uint64_t address_;
  mutable std::mutex mutex_;
  bool closed_ = false;
  bool ready_reported_ = false;
  StateCallback on_state_;
  ReadyCallback on_ready_;
  BluetoothLEDevice device_{nullptr};
  GattSession session_{nullptr};
  BluetoothLEDevice::ConnectionStatusChanged_revoker status_revoker_;
};

class WinrtConnectionFactory final : public NativeConnectionFactory {
 public:
  std::shared_ptr<NativeConnection> Create(uint64_t address) override {
    return std::make_shared<WinrtNativeConnection>(address);
  }
};
}  // namespace

std::shared_ptr<NativeConnectionFactory> CreateWinrtConnectionFactory() {
  return std::make_shared<WinrtConnectionFactory>();
}

WindowsConnectionBackend::WindowsConnectionBackend(
    std::shared_ptr<NativeConnectionFactory> factory)
    : factory_(std::move(factory)) {}

WindowsConnectionBackend::~WindowsConnectionBackend() {
  std::vector<std::shared_ptr<NativeConnection>> connections;
  {
    const std::scoped_lock lock(mutex_);
    connections.reserve(entries_.size());
    for (auto& item : entries_) {
      connections.push_back(std::move(item.second->native));
    }
    entries_.clear();
  }
  for (const auto& connection : connections) connection->Close();
}

void WindowsConnectionBackend::Connect(uint64_t address,
                                       PeripheralSession session,
                                       StateCallback on_state,
                                       ConnectCallback on_complete) {
  std::shared_ptr<ConnectionEntry> entry;
  bool duplicate = false;
  {
    const std::scoped_lock lock(mutex_);
    duplicate = entries_.find(address) != entries_.end();
    if (!duplicate) {
      entry = std::make_shared<ConnectionEntry>(
          std::move(session), std::move(on_state), factory_->Create(address));
      entries_.emplace(address, entry);
    }
  }
  if (duplicate) {
    on_complete(std::nullopt);
    return;
  }

  entry->on_state(
      ConnectionSnapshot{entry->session, ConnectionState::kConnecting});
  entry->native->Start(
      [this, address, entry](ConnectionState state) {
        Publish(address, entry, state);
      },
      [this, address, entry,
       on_complete = std::move(on_complete)](
          std::optional<std::string> error) mutable {
        Ready(address, entry, std::move(on_complete), std::move(error));
      });
}

void WindowsConnectionBackend::Ready(
    uint64_t address, const std::shared_ptr<ConnectionEntry>& entry,
    ConnectCallback on_complete, std::optional<std::string> error) {
  if (!error) {
    bool retained;
    {
      const std::scoped_lock lock(mutex_);
      const auto it = entries_.find(address);
      retained = it != entries_.end() && it->second == entry;
    }
    if (retained) on_complete(std::nullopt);
    return;
  }

  bool retained = false;
  {
    const std::scoped_lock lock(mutex_);
    const auto it = entries_.find(address);
    if (it != entries_.end() && it->second == entry) {
      entries_.erase(it);
      retained = true;
    }
  }
  entry->native->Close();
  if (!retained) return;
  entry->state = ConnectionState::kDisconnected;
  entry->on_state(
      ConnectionSnapshot{entry->session, ConnectionState::kDisconnected});
  on_complete(FlutterError("connection_failed", std::move(*error)));
}

void WindowsConnectionBackend::Publish(
    uint64_t address, const std::shared_ptr<ConnectionEntry>& expected,
    ConnectionState state) {
  StateCallback callback;
  {
    const std::scoped_lock lock(mutex_);
    const auto it = entries_.find(address);
    if (it == entries_.end() || it->second != expected) return;
    it->second->state = state;
    callback = it->second->on_state;
  }
  callback(ConnectionSnapshot{expected->session, state});
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
  entry->native->Close();
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

}  // namespace butane_windows
