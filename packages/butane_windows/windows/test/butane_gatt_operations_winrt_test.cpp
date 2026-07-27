#include <gtest/gtest.h>

#include "butane_gatt_operations_winrt.h"

namespace butane_windows::test {
class FakeNativeGattOperations final : public NativeGattOperations {
 public:
  void WriteCharacteristic(
      uint64_t address, std::string service, std::string characteristic,
      std::vector<uint8_t> value, bool without_response,
      Completion completion) override {
    last_address = address;
    last_service = std::move(service);
    last_characteristic = std::move(characteristic);
    last_value = std::move(value);
    last_without_response = without_response;
    CompleteOrSave(std::move(completion));
  }
  void ObserveCharacteristic(
      bool observe, uint64_t address, std::string service,
      std::string characteristic, ValueCallback on_value,
      Completion completion) override {
    last_observe = observe;
    last_address = address;
    last_service = std::move(service);
    last_characteristic = std::move(characteristic);
    value_callback = std::move(on_value);
    CompleteOrSave(std::move(completion));
  }
  void WriteDescriptor(
      uint64_t address, std::string service, std::string characteristic,
      std::string descriptor, std::vector<uint8_t> value,
      Completion completion) override {
    last_address = address;
    last_service = std::move(service);
    last_characteristic = std::move(characteristic);
    last_descriptor = std::move(descriptor);
    last_value = std::move(value);
    CompleteOrSave(std::move(completion));
  }
  void ReadMaxPduSize(uint64_t address, MtuCompletion completion) override {
    last_address = address;
    if (defer) {
      pending_mtu = std::move(completion);
    } else {
      completion(status, protocol, mtu);
    }
  }
  void Close() override { ++close_calls; }
  void CompleteOrSave(Completion completion) {
    if (defer) {
      pending = std::move(completion);
    } else {
      completion(status, protocol);
    }
  }

  bool defer = false;
  bool last_without_response = false;
  bool last_observe = false;
  int close_calls = 0;
  uint64_t last_address = 0;
  uint16_t mtu = 247;
  std::string last_service;
  std::string last_characteristic;
  std::string last_descriptor;
  std::vector<uint8_t> last_value;
  GattOperationStatus status = GattOperationStatus::kSuccess;
  std::optional<uint8_t> protocol;
  Completion pending;
  MtuCompletion pending_mtu;
  ValueCallback value_callback;
};

TEST(WindowsGattOperationsBackend, WritesCharacteristicWithBothOptions) {
  auto native = std::make_shared<FakeNativeGattOperations>();
  WindowsGattOperationsBackend backend(native);
  for (const bool without_response : {false, true}) {
    backend.WriteCharacteristic(
        42, "service", "characteristic", {0, 1, 255}, without_response,
        [](auto error) { EXPECT_FALSE(error); });
    EXPECT_EQ(native->last_address, 42u);
    EXPECT_EQ(native->last_service, "service");
    EXPECT_EQ(native->last_characteristic, "characteristic");
    EXPECT_EQ(native->last_value, (std::vector<uint8_t>{0, 1, 255}));
    EXPECT_EQ(native->last_without_response, without_response);
  }
}

TEST(WindowsGattOperationsBackend, WritesDescriptorBytes) {
  auto native = std::make_shared<FakeNativeGattOperations>();
  WindowsGattOperationsBackend backend(native);
  backend.WriteDescriptor(7, "s", "c", "d", {3, 2, 1},
                          [](auto error) { EXPECT_FALSE(error); });
  EXPECT_EQ(native->last_descriptor, "d");
  EXPECT_EQ(native->last_value, (std::vector<uint8_t>{3, 2, 1}));
}

TEST(WindowsGattOperationsBackend, ObservesAndStopsValues) {
  auto native = std::make_shared<FakeNativeGattOperations>();
  WindowsGattOperationsBackend backend(native);
  std::optional<GattValueEvent> event;
  backend.ObserveCharacteristic(
      true, 9, "s", "c",
      [&](auto value) { event = std::move(value); },
      [](auto error) { EXPECT_FALSE(error); });
  native->value_callback({8, 9});
  ASSERT_TRUE(event);
  EXPECT_EQ(event->address, 9u);
  EXPECT_EQ(event->service_uuid, "s");
  EXPECT_EQ(event->characteristic_uuid, "c");
  EXPECT_EQ(event->value, (std::vector<uint8_t>{8, 9}));
  backend.ObserveCharacteristic(false, 9, "s", "c", [](auto) {},
                                [](auto error) { EXPECT_FALSE(error); });
  EXPECT_FALSE(native->last_observe);
}

TEST(WindowsGattOperationsBackend, MapsEveryErrorRow) {
  auto native = std::make_shared<FakeNativeGattOperations>();
  WindowsGattOperationsBackend backend(native);
  const std::vector<std::pair<GattOperationStatus, std::string>> rows = {
      {GattOperationStatus::kUnreachable, "not-connected"},
      {GattOperationStatus::kProtocolError, "gatt-operation-failed"},
      {GattOperationStatus::kAccessDenied, "unauthorized"},
      {GattOperationStatus::kNotFound, "not-found"},
      {GattOperationStatus::kUnsupported, "unsupported"}};
  for (const auto& [status, code] : rows) {
    native->status = status;
    native->protocol = status == GattOperationStatus::kProtocolError
                           ? std::optional<uint8_t>(0x0e)
                           : std::nullopt;
    backend.WriteDescriptor(1, "s", "c", "d", {}, [&](auto error) {
      ASSERT_TRUE(error);
      EXPECT_EQ(error->code(), code);
    });
  }
}

TEST(WindowsGattOperationsBackend, ReportsNegotiatedMtu) {
  auto native = std::make_shared<FakeNativeGattOperations>();
  native->mtu = 512;
  WindowsGattOperationsBackend backend(native);
  backend.RequestMtu(8, 23, [](ErrorOr<int64_t> result) {
    ASSERT_FALSE(result.has_error());
    EXPECT_EQ(result.value(), 512);
  });
}

TEST(WindowsGattOperationsBackend, TeardownDropsLateCallbacks) {
  auto native = std::make_shared<FakeNativeGattOperations>();
  native->defer = true;
  int completions = 0;
  auto backend = std::make_unique<WindowsGattOperationsBackend>(native);
  backend->WriteCharacteristic(1, "s", "c", {}, false,
                               [&](auto) { ++completions; });
  backend.reset();
  EXPECT_EQ(native->close_calls, 1);
  native->pending(GattOperationStatus::kSuccess, std::nullopt);
  EXPECT_EQ(completions, 0);
}
}  // namespace butane_windows::test
