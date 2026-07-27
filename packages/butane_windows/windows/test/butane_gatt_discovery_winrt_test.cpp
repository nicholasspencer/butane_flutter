#include <gtest/gtest.h>

#include "butane_gatt_discovery_winrt.h"

namespace butane_windows::test {
class FakeNativeGattDiscovery final : public NativeGattDiscovery {
 public:
  void Close() override {
    if (closed) return;
    closed = true;
    ++close_calls;
  }
  void GetServices(uint64_t, ServicesCallback callback) override {
    ++service_calls;
    if (defer_callbacks) {
      pending_services = std::move(callback);
      return;
    }
    callback(status, error, services);
  }
  void GetCharacteristics(uint64_t, std::string,
                          CharacteristicsCallback callback) override {
    ++characteristic_calls;
    if (defer_callbacks) {
      pending_characteristics = std::move(callback);
      return;
    }
    callback(status, error, characteristics);
  }
  void CompleteServices() {
    auto callback = std::move(pending_services);
    callback(status, error, services);
  }
  void CompleteCharacteristics() {
    auto callback = std::move(pending_characteristics);
    callback(status, error, characteristics);
  }
  bool defer_callbacks = false;
  bool closed = false;
  int close_calls = 0;
  int service_calls = 0;
  int characteristic_calls = 0;
  ServicesCallback pending_services;
  CharacteristicsCallback pending_characteristics;
  GattDiscoveryStatus status = GattDiscoveryStatus::kSuccess;
  std::optional<uint8_t> error;
  std::vector<GattServiceData> services;
  std::vector<GattCharacteristicData> characteristics;
};

TEST(WindowsGattDiscoveryBackend, FiltersAndCachesServices) {
  auto native = std::make_shared<FakeNativeGattDiscovery>();
  native->services = {{"a", true}, {"b", true}};
  WindowsGattDiscoveryBackend backend(native);
  backend.DiscoverServices(1, {"b"}, false, [](auto error) {
    EXPECT_FALSE(error);
  });
  ASSERT_EQ(backend.Services(1).value().size(), 1u);
  EXPECT_EQ(backend.Services(1).value()[0].uuid, "b");
}
TEST(WindowsGattDiscoveryBackend,
     FiltersCharacteristicsAndEnumeratesDescriptors) {
  auto native = std::make_shared<FakeNativeGattDiscovery>();
  native->services = {{"s", true}};
  native->characteristics = {
      {"a", 1, {{"d"}}}, {"b", 2, {{"e"}}}};
  WindowsGattDiscoveryBackend backend(native);
  backend.DiscoverServices(1, {}, false, [](auto) {});
  backend.DiscoverCharacteristics(1, "s", {"b"}, false, [](auto error) {
    EXPECT_FALSE(error);
  });
  const auto values = backend.Characteristics(1, "s").value();
  ASSERT_EQ(values.size(), 1u);
  EXPECT_EQ(values[0].descriptors[0].uuid, "e");
}
TEST(WindowsGattDiscoveryBackend, EmptyFilterCachesEmptyList) {
  auto native = std::make_shared<FakeNativeGattDiscovery>();
  WindowsGattDiscoveryBackend backend(native);
  backend.DiscoverServices(1, {}, true, [](auto) {});
  EXPECT_TRUE(backend.Services(1).value().empty());
  EXPECT_EQ(native->service_calls, 0);
}
TEST(WindowsGattDiscoveryBackend, CommunicationFailurePreservesCache) {
  auto native = std::make_shared<FakeNativeGattDiscovery>();
  native->services = {{"a", true}};
  WindowsGattDiscoveryBackend backend(native);
  backend.DiscoverServices(1, {}, false, [](auto) {});
  native->status = GattDiscoveryStatus::kUnreachable;
  backend.DiscoverServices(1, {}, false, [](auto error) {
    ASSERT_TRUE(error);
    EXPECT_EQ(error->code(), "not-connected");
  });
  EXPECT_EQ(backend.Services(1).value()[0].uuid, "a");
}
TEST(WindowsGattDiscoveryBackend, CallbackMayReadCache) {
  auto native = std::make_shared<FakeNativeGattDiscovery>();
  native->services = {{"a", true}};
  WindowsGattDiscoveryBackend backend(native);
  backend.DiscoverServices(1, {}, false, [&](auto error) {
    EXPECT_FALSE(error);
    EXPECT_EQ(backend.Services(1).value()[0].uuid, "a");
  });
}
TEST(WindowsGattDiscoveryBackend, TeardownDuringDiscoveryDropsCallbacks) {
  auto service_native = std::make_shared<FakeNativeGattDiscovery>();
  service_native->defer_callbacks = true;
  int service_completions = 0;
  auto service_backend =
      std::make_unique<WindowsGattDiscoveryBackend>(service_native);
  service_backend->DiscoverServices(
      1, {}, false, [&](auto) { ++service_completions; });
  service_backend.reset();
  EXPECT_EQ(service_native->close_calls, 1);
  service_native->CompleteServices();
  EXPECT_EQ(service_completions, 0);

  auto characteristic_native = std::make_shared<FakeNativeGattDiscovery>();
  characteristic_native->services = {{"s", true}};
  auto characteristic_backend =
      std::make_unique<WindowsGattDiscoveryBackend>(characteristic_native);
  characteristic_backend->DiscoverServices(1, {}, false, [](auto) {});
  characteristic_native->defer_callbacks = true;
  characteristic_native->characteristics = {{"c", 2, {{"d"}}}};
  int characteristic_completions = 0;
  characteristic_backend->DiscoverCharacteristics(
      1, "s", {}, false,
      [&](auto) { ++characteristic_completions; });
  characteristic_backend.reset();
  EXPECT_EQ(characteristic_native->close_calls, 1);
  characteristic_native->CompleteCharacteristics();
  EXPECT_EQ(characteristic_completions, 0);
}
}  // namespace butane_windows::test
