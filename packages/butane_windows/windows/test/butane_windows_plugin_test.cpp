#include <gtest/gtest.h>
#include <chrono>
#include <memory>
#include <optional>
#include <type_traits>
#include <vector>
#include "butane_central.h"
#include "butane_windows_plugin.h"
#define CharacteristicProperty ButaneConversionCharacteristicProperty
#include "butane_conversions.h"
#undef CharacteristicProperty
namespace butane_windows::test {
using namespace std::chrono_literals;
static_assert(std::is_base_of_v<ButaneHostApi, ButaneWindowsPlugin>);
static_assert(std::is_class_v<ButaneFlutterApi>);
TEST(ClientStateMapping, MapsAllRows) {
  EXPECT_EQ(MapClientState(false, false, NativeRadioState::kUnknown), ClientState::kUnsupported);
  EXPECT_EQ(MapClientState(true, true, NativeRadioState::kOn), ClientState::kUnauthorized);
  EXPECT_EQ(MapClientState(true, false, NativeRadioState::kOn), ClientState::kPoweredOn);
  EXPECT_EQ(MapClientState(true, false, NativeRadioState::kOff), ClientState::kPoweredOff);
  EXPECT_EQ(MapClientState(true, false, NativeRadioState::kDisabled), ClientState::kUnauthorized);
  EXPECT_EQ(MapClientState(true, false, NativeRadioState::kUnknown), ClientState::kUnknown);
}
TEST(ServiceFilter, NullAndUuidWidthsNormalize) {
  EXPECT_TRUE(NormalizeServiceFilter(nullptr).value().empty());
  flutter::EncodableList values{flutter::EncodableValue("180D"),
      flutter::EncodableValue("0000180F"),
      flutter::EncodableValue("12345678-1234-5678-9ABC-DEF012345678")};
  auto result = NormalizeServiceFilter(&values);
  ASSERT_FALSE(result.has_error());
  EXPECT_EQ(result.value()[0], "0000180d-0000-1000-8000-00805f9b34fb");
  EXPECT_EQ(result.value()[1], "0000180f-0000-1000-8000-00805f9b34fb");
  EXPECT_EQ(result.value()[2], "12345678-1234-5678-9abc-def012345678");
}
TEST(ServiceFilter, RejectsMalformedUuid) {
  flutter::EncodableList values{flutter::EncodableValue("bad")};
  auto result = NormalizeServiceFilter(&values);
  ASSERT_TRUE(result.has_error());
  EXPECT_EQ(result.error().code(), "invalid_argument");
}
AdvertisementEvent Advertisement() {
  return {0x00A1B2C3D4E5ULL, int16_t{-63}, std::string("Peripheral"),
      std::string("Local"), {{0x1234, {0xaa, 0xbb}}, {0x00ff, {0xcc}}},
      {"180D"}, {{"180F", {1, 2, 3}}}, int16_t{-8}, true};
}
TEST(AdvertisementMapping, MapsCompleteAdvertisement) {
  const std::string client = "client";
  ClientSession session(nullptr, &client, nullptr, nullptr);
  auto result = BuildScanResult(Advertisement(), &session);
  ASSERT_FALSE(result.has_error());
  const auto& scan = result.value();
  EXPECT_EQ(scan.peripheral().session().peripheral_identifier(), "00:A1:B2:C3:D4:E5");
  EXPECT_EQ(*scan.peripheral().name(), "Peripheral");
  EXPECT_EQ(*scan.peripheral().rssi(), -63);
  EXPECT_EQ(scan.peripheral().state(), ConnectionState::kDisconnected);
  const auto& data = scan.advertisement_data();
  EXPECT_EQ(*data.local_name(), "Local");
  EXPECT_EQ(*data.manufacturer_data(),
      (std::vector<uint8_t>{0x34, 0x12, 0xaa, 0xbb, 0xff, 0x00, 0xcc}));
  EXPECT_EQ(std::get<std::string>((*data.service_uuids())[0]),
      "0000180d-0000-1000-8000-00805f9b34fb");
  auto key = flutter::EncodableValue("0000180f-0000-1000-8000-00805f9b34fb");
  EXPECT_EQ(std::get<std::vector<uint8_t>>(data.service_data()->at(key)),
      (std::vector<uint8_t>{1, 2, 3}));
  EXPECT_EQ(*data.tx_power_level(), -8);
  EXPECT_TRUE(*data.is_connectable());
}
TEST(AdvertisementMapping, NullFieldsAndMalformedUuid) {
  AdvertisementEvent event{1, int16_t{-80}, std::nullopt, std::nullopt, {}, {}, {},
      std::nullopt, std::nullopt};
  auto result = BuildScanResult(event, nullptr);
  ASSERT_FALSE(result.has_error());
  EXPECT_EQ(result.value().peripheral().name(), nullptr);
  EXPECT_EQ(result.value().advertisement_data().local_name(), nullptr);
  event.service_data["bad"] = {};
  result = BuildScanResult(event, nullptr);
  ASSERT_TRUE(result.has_error());
  EXPECT_EQ(result.error().code(), "invalid_argument");
}
class FakeCentral final : public CentralBackend {
 public:
  explicit FakeCentral(RssiCache* cache = nullptr) : cache(cache) {}
  void QueryState(StateCallback callback) override {
    state = std::move(callback);
    state(ClientState::kPoweredOn);
  }
  std::optional<FlutterError> StartScan(const std::vector<std::string>& uuids,
      AdvertisementCallback callback) override {
    if (scanning) return FlutterError("scan_in_progress", "A Windows BLE scan is already active.");
    filters = uuids; receipt = std::move(callback); scanning = true;
    return std::nullopt;
  }
  void StopScan() override { scanning = false; receipt = nullptr; ++stops; }
  void EmitState(ClientState value) { state(value); }
  void Emit(AdvertisementEvent value) {
    if (cache) cache->Observe(value.bluetooth_address, value.rssi, RssiCache::Clock::now());
    receipt(std::move(value));
  }
  RssiCache* cache;
  bool scanning = false;
  int stops = 0;
  std::vector<std::string> filters;
  StateCallback state;
  AdvertisementCallback receipt;
};
class FakeRunner final : public PlatformTaskRunner {
 public:
  void PostTask(std::function<void()> task) override { tasks.push_back(std::move(task)); }
  void RunAll() {
    auto pending = std::move(tasks); tasks.clear();
    for (auto& task : pending) task();
  }
  std::vector<std::function<void()>> tasks;
};
class FakeSink final : public FlutterEventSink {
 public:
  void OnClientState(const std::string* id, ClientState value) override {
    client_id = id ? std::optional<std::string>(*id) : std::nullopt;
    states.push_back(value);
  }
  void OnScanResult(const ScanResult& value) override { results.push_back(value); }
  std::optional<std::string> client_id;
  std::vector<ClientState> states;
  std::vector<ScanResult> results;
};
struct Fixture {
  explicit Fixture(RssiCache* cache = nullptr) {
    auto c = std::make_unique<FakeCentral>(cache); central = c.get();
    auto r = std::make_unique<FakeRunner>(); runner = r.get();
    auto s = std::make_unique<FakeSink>(); sink = s.get();
    plugin = std::make_unique<ButaneWindowsPlugin>(
        std::move(c), std::move(r), std::move(s));
  }
  FakeCentral* central;
  FakeRunner* runner;
  FakeSink* sink;
  std::unique_ptr<ButaneWindowsPlugin> plugin;
};
TEST(ButaneWindowsPlugin, StateRepliesAndPostsStateChanges) {
  Fixture f;
  const std::string id = "client";
  ClientSession session(nullptr, &id, nullptr, nullptr);
  bool replied = false;
  f.plugin->State(&session, [&](ErrorOr<ClientState> value) {
    replied = true; EXPECT_EQ(value.value(), ClientState::kPoweredOn);
  });
  EXPECT_TRUE(replied);
  f.central->EmitState(ClientState::kPoweredOff);
  EXPECT_TRUE(f.sink->states.empty());
  f.runner->RunAll();
  EXPECT_EQ(f.sink->states[0], ClientState::kPoweredOff);
  EXPECT_EQ(f.sink->client_id, id);
}
TEST(ButaneWindowsPlugin, ScanPostsReceiptBeforeFlutterApi) {
  Fixture f;
  f.plugin->Scan(nullptr, nullptr, [](auto error) { EXPECT_FALSE(error); });
  f.central->Emit(Advertisement());
  EXPECT_TRUE(f.sink->results.empty());
  f.runner->RunAll();
  EXPECT_EQ(f.sink->results.size(), 1u);
}
TEST(ButaneWindowsPlugin, ScanRejectsConcurrentStart) {
  Fixture f;
  f.plugin->Scan(nullptr, nullptr, [](auto error) { EXPECT_FALSE(error); });
  f.plugin->Scan(nullptr, nullptr, [](auto error) {
    ASSERT_TRUE(error); EXPECT_EQ(error->code(), "scan_in_progress");
  });
}
TEST(ButaneWindowsPlugin, CancelScanIsIdempotent) {
  Fixture f;
  f.plugin->CancelScan(nullptr, [](auto error) { EXPECT_FALSE(error); });
  f.plugin->CancelScan(nullptr, [](auto error) { EXPECT_FALSE(error); });
  EXPECT_EQ(f.central->stops, 2);
}
TEST(ButaneWindowsPlugin, ReceiptUpdatesRssiBeforeDelivery) {
  RssiCache cache;
  Fixture f(&cache);
  f.plugin->Scan(nullptr, nullptr, [](auto error) { EXPECT_FALSE(error); });
  auto event = Advertisement();
  f.central->Emit(event);
  EXPECT_EQ(cache.Get(event.bluetooth_address, RssiCache::Clock::now(), 30s),
      event.rssi);
  EXPECT_TRUE(f.sink->results.empty());
}
}  // namespace butane_windows::test
