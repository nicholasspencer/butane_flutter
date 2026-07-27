#ifndef PACKAGES_BUTANE_WINDOWS_WINDOWS_BUTANE_CONNECTION_WINRT_H_
#define PACKAGES_BUTANE_WINDOWS_WINDOWS_BUTANE_CONNECTION_WINRT_H_

#include "butane_connection.h"

#include <functional>
#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <unordered_map>

namespace butane_windows {

class NativeConnection {
 public:
  using StateCallback = std::function<void(ConnectionState)>;
  using ReadyCallback = std::function<void(std::optional<std::string> error)>;

  virtual ~NativeConnection() = default;
  virtual void Start(StateCallback on_state, ReadyCallback on_ready) = 0;
  virtual void Close() = 0;
};

class NativeConnectionFactory {
 public:
  virtual ~NativeConnectionFactory() = default;
  virtual std::shared_ptr<NativeConnection> Create(uint64_t address) = 0;
};

std::shared_ptr<NativeConnectionFactory> CreateWinrtConnectionFactory();

class WindowsConnectionBackend final : public ConnectionBackend {
 public:
  explicit WindowsConnectionBackend(
      std::shared_ptr<NativeConnectionFactory> factory =
          CreateWinrtConnectionFactory());
  ~WindowsConnectionBackend() override;

  void Connect(uint64_t address, PeripheralSession session,
               StateCallback on_state, ConnectCallback on_complete) override;
  void Disconnect(uint64_t address) override;
  ConnectionState State(uint64_t address) const override;

 private:
  struct ConnectionEntry {
    ConnectionEntry(PeripheralSession value, StateCallback callback,
                    std::shared_ptr<NativeConnection> native_value)
        : session(std::move(value)),
          on_state(std::move(callback)),
          native(std::move(native_value)) {}

    PeripheralSession session;
    StateCallback on_state;
    std::shared_ptr<NativeConnection> native;
    ConnectionState state = ConnectionState::kConnecting;
  };

  void Publish(uint64_t address,
               const std::shared_ptr<ConnectionEntry>& expected,
               ConnectionState state);
  void Ready(uint64_t address, const std::shared_ptr<ConnectionEntry>& entry,
             ConnectCallback on_complete,
             std::optional<std::string> error);

  std::shared_ptr<NativeConnectionFactory> factory_;
  mutable std::mutex mutex_;
  std::unordered_map<uint64_t, std::shared_ptr<ConnectionEntry>> entries_;
};

}  // namespace butane_windows

#endif
