#include <gtest/gtest.h>

#include <memory>
#include <optional>
#include <string>
#include <utility>
#include <vector>

#include "butane_connection_winrt.h"

namespace butane_windows::test {
namespace {
class FakeNativeConnection final : public NativeConnection {
 public:
  explicit FakeNativeConnection(
      std::shared_ptr<std::vector<std::string>> ordering)
      : events(std::move(ordering)) {}

  void Start(StateCallback state, ReadyCallback ready) override {
    state_ = std::move(state);
    ready_ = std::move(ready);
    ++starts;
  }
  void Close() override {
    events->push_back("close");
    ++closes;
  }
  void EmitState(ConnectionState value) {
    events->push_back("state");
    state_(value);
  }
  void Complete(std::optional<std::string> error = std::nullopt) {
    events->push_back("complete");
    ready_(std::move(error));
  }

  std::shared_ptr<std::vector<std::string>> events;
  int starts = 0;
  int closes = 0;

 private:
  StateCallback state_;
  ReadyCallback ready_;
};

class FakeNativeConnectionFactory final : public NativeConnectionFactory {
 public:
  std::shared_ptr<NativeConnection> Create(uint64_t address) override {
    addresses.push_back(address);
    auto connection = std::make_shared<FakeNativeConnection>(events);
    connections.push_back(connection);
    return connection;
  }

  std::shared_ptr<std::vector<std::string>> events =
      std::make_shared<std::vector<std::string>>();
  std::vector<uint64_t> addresses;
  std::vector<std::shared_ptr<FakeNativeConnection>> connections;
};

constexpr uint64_t kAddress = 0x00A1B2C3D4E5ULL;

TEST(WindowsConnectionBackend, TracksTransportState) {
  auto factory = std::make_shared<FakeNativeConnectionFactory>();
  WindowsConnectionBackend backend(factory);
  std::vector<ConnectionState> states;
  bool complete = false;
  backend.Connect(
      kAddress, PeripheralSession("00:A1:B2:C3:D4:E5"),
      [&](ConnectionSnapshot value) { states.push_back(value.state); },
      [&](auto error) {
        EXPECT_FALSE(error);
        complete = true;
      });

  ASSERT_EQ(factory->connections.size(), 1u);
  EXPECT_EQ(states, (std::vector<ConnectionState>{
                        ConnectionState::kConnecting}));
  EXPECT_EQ(backend.State(kAddress), ConnectionState::kConnecting);
  factory->connections[0]->EmitState(ConnectionState::kConnected);
  EXPECT_EQ(backend.State(kAddress), ConnectionState::kConnected);
  factory->connections[0]->EmitState(ConnectionState::kDisconnected);
  EXPECT_EQ(backend.State(kAddress), ConnectionState::kDisconnected);
  factory->connections[0]->Complete();
  EXPECT_TRUE(complete);
}

TEST(WindowsConnectionBackend, DeduplicatesConnect) {
  auto factory = std::make_shared<FakeNativeConnectionFactory>();
  WindowsConnectionBackend backend(factory);
  int completions = 0;
  backend.Connect(kAddress, PeripheralSession("first"), [](auto) {},
                  [&](auto error) {
                    EXPECT_FALSE(error);
                    ++completions;
                  });
  backend.Connect(kAddress, PeripheralSession("second"), [](auto) {},
                  [&](auto error) {
                    EXPECT_FALSE(error);
                    ++completions;
                  });

  ASSERT_EQ(factory->connections.size(), 1u);
  EXPECT_EQ(factory->connections[0]->starts, 1);
  EXPECT_EQ(completions, 1);
  factory->connections[0]->Complete();
  EXPECT_EQ(completions, 2);
}

TEST(WindowsConnectionBackend, FailureClosesBeforeCallback) {
  auto factory = std::make_shared<FakeNativeConnectionFactory>();
  WindowsConnectionBackend backend(factory);
  std::vector<std::string> observed;
  backend.Connect(
      kAddress, PeripheralSession("peripheral"),
      [&](ConnectionSnapshot value) {
        if (value.state == ConnectionState::kDisconnected) {
          factory->events->push_back("disconnected");
        }
      },
      [&](auto error) {
        ASSERT_TRUE(error);
        EXPECT_EQ(error->code(), "connection_failed");
        factory->events->push_back("callback");
      });
  factory->events->clear();
  factory->connections[0]->Complete("failed");

  EXPECT_EQ(*factory->events,
            (std::vector<std::string>{"complete", "close", "disconnected",
                                      "callback"}));
  EXPECT_EQ(backend.State(kAddress), ConnectionState::kDisconnected);
}

TEST(WindowsConnectionBackend, DisconnectIsIdempotent) {
  auto factory = std::make_shared<FakeNativeConnectionFactory>();
  WindowsConnectionBackend backend(factory);
  backend.Disconnect(kAddress);
  backend.Connect(
      kAddress, PeripheralSession("peripheral"),
      [&](ConnectionSnapshot value) {
        if (value.state == ConnectionState::kDisconnecting) {
          factory->events->push_back("disconnecting");
        } else if (value.state == ConnectionState::kDisconnected) {
          factory->events->push_back("disconnected");
        }
      },
      [](auto) {});
  factory->events->clear();
  backend.Disconnect(kAddress);
  backend.Disconnect(kAddress);

  EXPECT_EQ(*factory->events,
            (std::vector<std::string>{"disconnecting", "close",
                                      "disconnected"}));
  EXPECT_EQ(factory->connections[0]->closes, 1);
}

TEST(WindowsConnectionBackend, RetainsDistinctTransportsAndClosesOnDestruction) {
  auto factory = std::make_shared<FakeNativeConnectionFactory>();
  {
    WindowsConnectionBackend backend(factory);
    backend.Connect(1, PeripheralSession("one"), [](auto) {}, [](auto) {});
    backend.Connect(2, PeripheralSession("two"), [](auto) {}, [](auto) {});
    EXPECT_EQ(factory->connections.size(), 2u);
  }
  EXPECT_EQ(factory->connections[0]->closes, 1);
  EXPECT_EQ(factory->connections[1]->closes, 1);
}

TEST(WindowsConnectionBackend, StateCallbacksMayQueryState) {
  auto factory = std::make_shared<FakeNativeConnectionFactory>();
  WindowsConnectionBackend backend(factory);
  backend.Connect(
      kAddress, PeripheralSession("peripheral"),
      [&](ConnectionSnapshot) { (void)backend.State(kAddress); },
      [](auto) {});
  factory->connections[0]->EmitState(ConnectionState::kConnected);
  backend.Disconnect(kAddress);
}
}  // namespace
}  // namespace butane_windows::test
