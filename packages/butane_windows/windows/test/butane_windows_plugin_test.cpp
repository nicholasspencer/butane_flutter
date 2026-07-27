#include <gtest/gtest.h>
#include <chrono>
#include <cstdint>
#include <memory>
#include <optional>
#include <type_traits>
#include <unordered_map>
#include <vector>
#include "butane_central.h"
#include "butane_connection.h"
#include "butane_gatt_operations.h"
#include "butane_windows_plugin.h"
#include "butane_conversions.h"
namespace butane_windows::test {
using namespace std::chrono_literals;
template <typename T>
const T* CustomValue(const flutter::EncodableValue& value) {
  const auto& custom = std::get<flutter::CustomEncodableValue>(value);
  return std::any_cast<T>(&static_cast<const std::any&>(custom));
}
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
TEST(ConnectionStateMapping, ConnectedAndDisconnected) {
  using winrt::Windows::Devices::Bluetooth::BluetoothConnectionStatus;
  EXPECT_EQ(MapConnectionStatus(BluetoothConnectionStatus::Connected),
            ConnectionState::kConnected);
  EXPECT_EQ(MapConnectionStatus(BluetoothConnectionStatus::Disconnected),
            ConnectionState::kDisconnected);
}
TEST(PluginRegistrationGuard, RejectsMissingWindow) {
  EXPECT_FALSE(ProbePlatformWindow([] { return static_cast<HWND>(nullptr); }));
  EXPECT_TRUE(ProbePlatformWindow(
      [] { return reinterpret_cast<HWND>(static_cast<uintptr_t>(1)); }));
}
TEST(PluginRegistrationGuard, ContainsApartmentFailure) {
  EXPECT_FALSE(TryInitializeWinrtApartment([] {
    throw winrt::hresult_error(E_FAIL);
  }));
  bool invoked = false;
  EXPECT_TRUE(TryInitializeWinrtApartment([&] { invoked = true; }));
  EXPECT_TRUE(invoked);
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
  explicit FakeRunner(
      std::shared_ptr<std::vector<std::string>> lifecycle = nullptr)
      : lifecycle(std::move(lifecycle)) {}
  ~FakeRunner() override {
    if (lifecycle) lifecycle->push_back("runner");
  }
  void PostTask(std::function<void()> task) override { tasks.push_back(std::move(task)); }
  void RunAll() {
    auto pending = std::move(tasks); tasks.clear();
    for (auto& task : pending) task();
  }
  std::vector<std::function<void()>> tasks;
  std::shared_ptr<std::vector<std::string>> lifecycle;
};
class FakeConnection final : public ConnectionBackend {
 public:
  void Connect(uint64_t address, PeripheralSession session,
               StateCallback callback, ConnectCallback complete) override {
    ++connects;
    addresses.push_back(address);
    sessions.push_back(std::move(session));
    states[address] = ConnectionState::kConnecting;
    callbacks[address] = std::move(callback);
    completions[address] = std::move(complete);
  }
  void Disconnect(uint64_t address) override {
    ++disconnects;
    const auto callback = callbacks.find(address);
    if (callback == callbacks.end()) return;
    callback->second(
        {sessions.back(), ConnectionState::kDisconnecting});
    callback->second({sessions.back(), ConnectionState::kDisconnected});
    callbacks.erase(address);
    states.erase(address);
  }
  ConnectionState State(uint64_t address) const override {
    const auto it = states.find(address);
    return it == states.end() ? ConnectionState::kDisconnected : it->second;
  }
  void Emit(uint64_t address, ConnectionState state) {
    states[address] = state;
    callbacks.at(address)({sessions.back(), state});
  }
  void Complete(uint64_t address,
                std::optional<FlutterError> error = std::nullopt) {
    if (error) states.erase(address);
    completions.at(address)(std::move(error));
  }
  int connects = 0;
  int disconnects = 0;
  std::vector<uint64_t> addresses;
  std::vector<PeripheralSession> sessions;
  std::unordered_map<uint64_t, ConnectionState> states;
  std::unordered_map<uint64_t, StateCallback> callbacks;
  std::unordered_map<uint64_t, ConnectCallback> completions;
};
class FakeGattDiscovery final : public GattDiscoveryBackend {
 public:
  void DiscoverServices(uint64_t address, std::vector<std::string> uuids,
                        bool explicit_empty,
                        Completion completion) override {
    service_address = address;
    service_filter = std::move(uuids);
    service_explicit_empty = explicit_empty;
    completion(discover_error);
  }
  ErrorOr<std::vector<GattServiceData>> Services(
      uint64_t address) const override {
    last_read_address = address;
    if (read_error) return *read_error;
    return services;
  }
  void DiscoverCharacteristics(
      uint64_t address, std::string service_uuid,
      std::vector<std::string> uuids, bool explicit_empty,
      Completion completion) override {
    characteristic_address = address;
    characteristic_service = std::move(service_uuid);
    characteristic_filter = std::move(uuids);
    characteristic_explicit_empty = explicit_empty;
    completion(discover_error);
  }
  ErrorOr<std::vector<GattCharacteristicData>> Characteristics(
      uint64_t address, std::string_view service_uuid) const override {
    last_read_address = address;
    last_read_service = std::string(service_uuid);
    if (read_error) return *read_error;
    return characteristics;
  }

  std::optional<FlutterError> discover_error;
  std::optional<FlutterError> read_error;
  std::vector<GattServiceData> services;
  std::vector<GattCharacteristicData> characteristics;
  uint64_t service_address = 0;
  std::vector<std::string> service_filter;
  bool service_explicit_empty = false;
  uint64_t characteristic_address = 0;
  std::string characteristic_service;
  std::vector<std::string> characteristic_filter;
  bool characteristic_explicit_empty = false;
  mutable uint64_t last_read_address = 0;
  mutable std::string last_read_service;
};
class FakeGattOperations final : public GattOperationsBackend {
 public:
  explicit FakeGattOperations(
      std::shared_ptr<std::vector<std::string>> lifecycle = nullptr)
      : lifecycle(std::move(lifecycle)) {}
  void WriteCharacteristic(uint64_t address, std::string service_uuid,
      std::string characteristic_uuid, std::vector<uint8_t> value,
      bool without_response, Completion completion) override {
    last_address = address; service = std::move(service_uuid);
    characteristic = std::move(characteristic_uuid); bytes = std::move(value);
    without = without_response; completion(error);
  }
  void ObserveCharacteristic(bool observe, uint64_t address,
      std::string service_uuid, std::string characteristic_uuid,
      ValueCallback on_value, Completion completion) override {
    observing = observe; last_address = address;
    service = std::move(service_uuid);
    characteristic = std::move(characteristic_uuid);
    value_callback = std::move(on_value); completion(error);
  }
  void WriteDescriptor(uint64_t address, std::string service_uuid,
      std::string characteristic_uuid, std::string descriptor_uuid,
      std::vector<uint8_t> value, Completion completion) override {
    last_address = address; service = std::move(service_uuid);
    characteristic = std::move(characteristic_uuid);
    descriptor = std::move(descriptor_uuid); bytes = std::move(value);
    completion(error);
  }
  void RequestMtu(uint64_t address, int64_t requested_mtu,
      MtuCompletion completion) override {
    last_address = address; mtu = requested_mtu;
    if (mtu_error) completion(*mtu_error); else completion(negotiated_mtu);
  }
  void Close() override {
    closed = true;
    if (lifecycle) lifecycle->push_back("operations");
  }
  uint64_t last_address = 0;
  std::string service, characteristic, descriptor;
  std::vector<uint8_t> bytes;
  bool without = false, observing = false, closed = false;
  int64_t mtu = 0, negotiated_mtu = 247;
  std::optional<FlutterError> error, mtu_error;
  ValueCallback value_callback;
  std::shared_ptr<std::vector<std::string>> lifecycle;
};
class FakeSink final : public FlutterEventSink {
 public:
  explicit FakeSink(
      std::shared_ptr<std::vector<std::string>> lifecycle = nullptr)
      : lifecycle(std::move(lifecycle)) {}
  ~FakeSink() override {
    if (lifecycle) lifecycle->push_back("sink");
  }
  void OnClientState(const std::string* id, ClientState value) override {
    client_id = id ? std::optional<std::string>(*id) : std::nullopt;
    states.push_back(value);
  }
  void OnScanResult(const ScanResult& value) override { results.push_back(value); }
  void OnConnectionState(const Peripheral& peripheral,
                         ConnectionState value) override {
    connection_sessions.push_back(peripheral.session());
    connection_states.push_back(value);
  }
  void OnCharacteristicValue(const Peripheral& peripheral,
      const Characteristic& characteristic,
      const std::vector<uint8_t>& value) override {
    characteristic_peripherals.push_back(peripheral);
    characteristics.push_back(characteristic);
    characteristic_values.push_back(value);
  }
  std::optional<std::string> client_id;
  std::vector<ClientState> states;
  std::vector<ScanResult> results;
  std::vector<PeripheralSession> connection_sessions;
  std::vector<ConnectionState> connection_states;
  std::vector<Peripheral> characteristic_peripherals;
  std::vector<Characteristic> characteristics;
  std::vector<std::vector<uint8_t>> characteristic_values;
  std::shared_ptr<std::vector<std::string>> lifecycle;
};
struct Fixture {
  Fixture() {
    lifecycle = std::make_shared<std::vector<std::string>>();
    auto cache_value = std::make_unique<RssiCache>(); cache = cache_value.get();
    auto c = std::make_unique<FakeCentral>(cache); central = c.get();
    auto connection_value = std::make_unique<FakeConnection>();
    connection = connection_value.get();
    auto discovery_value = std::make_unique<FakeGattDiscovery>();
    discovery = discovery_value.get();
    auto operations_value = std::make_unique<FakeGattOperations>(lifecycle);
    operations = operations_value.get();
    auto r = std::make_unique<FakeRunner>(lifecycle); runner = r.get();
    auto s = std::make_unique<FakeSink>(lifecycle); sink = s.get();
    plugin = std::make_unique<ButaneWindowsPlugin>(
        std::move(cache_value), std::move(c), std::move(connection_value),
        std::move(discovery_value), std::move(operations_value), std::move(r),
        std::move(s));
  }
  RssiCache* cache;
  FakeCentral* central;
  FakeRunner* runner;
  FakeSink* sink;
  FakeConnection* connection;
  FakeGattDiscovery* discovery;
  FakeGattOperations* operations;
  std::shared_ptr<std::vector<std::string>> lifecycle;
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
  Fixture f;
  f.plugin->Scan(nullptr, nullptr, [](auto error) { EXPECT_FALSE(error); });
  auto event = Advertisement();
  f.central->Emit(event);
  EXPECT_EQ(f.cache->Get(event.bluetooth_address, RssiCache::Clock::now(), 30s),
      event.rssi);
  EXPECT_TRUE(f.sink->results.empty());
}
TEST(ButaneWindowsPlugin, ConnectRejectsMalformedAddress) {
  Fixture f;
  f.plugin->Connect(PeripheralSession("bad"), [](auto error) {
    ASSERT_TRUE(error);
    EXPECT_EQ(error->code(), "invalid_argument");
  });
  EXPECT_EQ(f.connection->connects, 0);
}
TEST(ButaneWindowsPlugin, ConnectStartsAndDuplicateReusesEntry) {
  Fixture f;
  const PeripheralSession session("00:A1:B2:C3:D4:E5");
  f.plugin->Connect(session, [](auto) {});
  f.plugin->Connect(session, [](auto) {});
  EXPECT_EQ(f.connection->connects, 2);
  EXPECT_EQ(f.connection->addresses[0], 0x00A1B2C3D4E5ULL);
}
TEST(ButaneWindowsPlugin, ConnectionStateTracksPendingConnectedAndMissing) {
  Fixture f;
  const PeripheralSession session("00:A1:B2:C3:D4:E5");
  f.plugin->Connect(session, [](auto) {});
  f.plugin->ConnectionState(session, [](auto state) {
    EXPECT_EQ(state.value(), ConnectionState::kConnecting);
  });
  f.connection->Emit(0x00A1B2C3D4E5ULL, ConnectionState::kConnected);
  f.plugin->ConnectionState(session, [](auto state) {
    EXPECT_EQ(state.value(), ConnectionState::kConnected);
  });
  f.plugin->ConnectionState(PeripheralSession("00:00:00:00:00:01"),
                            [](auto state) {
    EXPECT_EQ(state.value(), ConnectionState::kDisconnected);
  });
}
TEST(ButaneWindowsPlugin, ConnectFailureErasesPendingState) {
  Fixture f;
  const PeripheralSession session("00:A1:B2:C3:D4:E5");
  f.plugin->Connect(session, [](auto) {});
  f.connection->Complete(
      0x00A1B2C3D4E5ULL,
      FlutterError("connection_failed", "failed"));
  f.plugin->ConnectionState(session, [](auto state) {
    EXPECT_EQ(state.value(), ConnectionState::kDisconnected);
  });
}
TEST(ButaneWindowsPlugin, CancelConnectionIsIdempotentAndCloses) {
  Fixture f;
  const PeripheralSession session("00:A1:B2:C3:D4:E5");
  f.plugin->Connect(session, [](auto) {});
  f.plugin->CancelConnection(session,
                             [](auto error) { EXPECT_FALSE(error); });
  f.plugin->CancelConnection(session,
                             [](auto error) { EXPECT_FALSE(error); });
  EXPECT_EQ(f.connection->disconnects, 2);
}
TEST(ButaneWindowsPlugin, MalformedCancelAndStateReturnInvalidArgument) {
  Fixture f;
  const PeripheralSession malformed("not-an-address");
  f.plugin->CancelConnection(malformed, [](auto error) {
    ASSERT_TRUE(error);
    EXPECT_EQ(error->code(), "invalid_argument");
  });
  f.plugin->ConnectionState(malformed, [](auto result) {
    ASSERT_TRUE(result.has_error());
    EXPECT_EQ(result.error().code(), "invalid_argument");
  });
}
TEST(ButaneWindowsPlugin, ConnectionChangePostsBeforeFlutterApi) {
  Fixture f;
  const PeripheralSession session(
      "00:A1:B2:C3:D4:E5", nullptr, nullptr, nullptr);
  f.plugin->Connect(session, [](auto) {});
  f.connection->Emit(0x00A1B2C3D4E5ULL, ConnectionState::kConnected);
  EXPECT_TRUE(f.sink->connection_states.empty());
  f.runner->RunAll();
  ASSERT_EQ(f.sink->connection_states.size(), 1u);
  EXPECT_EQ(f.sink->connection_states[0], ConnectionState::kConnected);
  EXPECT_EQ(f.sink->connection_sessions[0].peripheral_identifier(),
            session.peripheral_identifier());
}
TEST(ButaneWindowsPlugin, DiscoverServicesNormalizesFilter) {
  Fixture f;
  flutter::EncodableList filter{flutter::EncodableValue("180D")};
  f.plugin->DiscoverServices(PeripheralSession("00:A1:B2:C3:D4:E5"),
      &filter, [](auto error) { EXPECT_FALSE(error); });
  EXPECT_EQ(f.discovery->service_address, 0x00A1B2C3D4E5ULL);
  ASSERT_EQ(f.discovery->service_filter.size(), 1u);
  EXPECT_EQ(f.discovery->service_filter[0],
            "0000180d-0000-1000-8000-00805f9b34fb");
  EXPECT_FALSE(f.discovery->service_explicit_empty);
}
TEST(ButaneWindowsPlugin, ServicesMapPrimaryAndCanonicalUuid) {
  Fixture f;
  f.discovery->services = {
      {"0000180d-0000-1000-8000-00805f9b34fb", true}};
  f.plugin->Services(PeripheralSession("00:A1:B2:C3:D4:E5"),
      [](auto result) {
        ASSERT_FALSE(result.has_error());
        ASSERT_EQ(result.value().size(), 1u);
        const auto* service = CustomValue<Service>(result.value()[0]);
        ASSERT_NE(service, nullptr);
        EXPECT_EQ(service->uuid(),
                  "0000180d-0000-1000-8000-00805f9b34fb");
        EXPECT_TRUE(service->is_primary());
      });
}
TEST(ButaneWindowsPlugin, DiscoverCharacteristicsRejectsUnknownService) {
  Fixture f;
  f.discovery->services = {
      {"0000180f-0000-1000-8000-00805f9b34fb", true}};
  f.plugin->DiscoverCharacteristics(
      PeripheralSession("00:A1:B2:C3:D4:E5"), "180D", nullptr,
      [](auto error) {
        ASSERT_TRUE(error);
        EXPECT_EQ(error->code(), "not-found");
      });
  EXPECT_EQ(f.discovery->characteristic_address, 0u);
}
TEST(ButaneWindowsPlugin,
     CharacteristicsPopulateAllPropertiesAndDescriptors) {
  Fixture f;
  f.discovery->characteristics = {
      {"00002a37-0000-1000-8000-00805f9b34fb", 0x3ff,
       {{"00002902-0000-1000-8000-00805f9b34fb"}}},
      {"reliable", kGattPropertyReliableWrites, {}},
      {"auxiliary", kGattPropertyWritableAuxiliaries, {}}};
  f.plugin->Characteristics(PeripheralSession("00:A1:B2:C3:D4:E5"),
      "180D", [](auto result) {
        ASSERT_FALSE(result.has_error());
        ASSERT_EQ(result.value().size(), 3u);
        const auto* characteristic =
            CustomValue<Characteristic>(result.value()[0]);
        ASSERT_NE(characteristic, nullptr);
        ASSERT_NE(characteristic->properties(), nullptr);
        const auto& properties = *characteristic->properties();
        EXPECT_TRUE(properties.broadcast());
        EXPECT_TRUE(properties.read());
        EXPECT_TRUE(properties.write_without_response());
        EXPECT_TRUE(properties.write());
        EXPECT_TRUE(properties.notify());
        EXPECT_TRUE(properties.indicate());
        EXPECT_TRUE(properties.authenticated_signed_writes());
        EXPECT_TRUE(properties.extended_properties());
        EXPECT_FALSE(properties.notify_encryption_required());
        EXPECT_FALSE(properties.indicate_encryption_required());
        ASSERT_NE(characteristic->descriptors(), nullptr);
        ASSERT_EQ(characteristic->descriptors()->size(), 1u);
        const auto* descriptor =
            CustomValue<Descriptor>(characteristic->descriptors()->at(0));
        ASSERT_NE(descriptor, nullptr);
        EXPECT_EQ(descriptor->uuid(),
                  "00002902-0000-1000-8000-00805f9b34fb");
        EXPECT_EQ(descriptor->value(), nullptr);
        for (size_t index : {size_t{1}, size_t{2}}) {
          const auto* alias =
              CustomValue<Characteristic>(result.value()[index]);
          ASSERT_NE(alias, nullptr);
          ASSERT_NE(alias->properties(), nullptr);
          EXPECT_TRUE(alias->properties()->extended_properties());
        }
      });
}
TEST(ButaneWindowsPlugin, ZeroMaskStillReturnsNonNullProperties) {
  Fixture f;
  f.discovery->characteristics = {{"zero", 0, {}}};
  f.plugin->Characteristics(PeripheralSession("00:A1:B2:C3:D4:E5"),
      "180D", [](auto result) {
        ASSERT_FALSE(result.has_error());
        const auto* characteristic =
            CustomValue<Characteristic>(result.value()[0]);
        ASSERT_NE(characteristic, nullptr);
        ASSERT_NE(characteristic->properties(), nullptr);
        EXPECT_FALSE(characteristic->properties()->read());
      });
}
TEST(ButaneWindowsPlugin, MalformedDiscoveryInputReturnsInvalidArgument) {
  Fixture f;
  f.plugin->DiscoverServices(PeripheralSession("bad"), nullptr,
      [](auto error) {
        ASSERT_TRUE(error);
        EXPECT_EQ(error->code(), "invalid_argument");
      });
  f.plugin->Characteristics(PeripheralSession("00:A1:B2:C3:D4:E5"),
      "bad", [](auto result) {
        ASSERT_TRUE(result.has_error());
        EXPECT_EQ(result.error().code(), "invalid_argument");
      });
  flutter::EncodableList invalid_filter{flutter::EncodableValue(int32_t{1})};
  f.plugin->DiscoverServices(PeripheralSession("00:A1:B2:C3:D4:E5"),
      &invalid_filter, [](auto error) {
        ASSERT_TRUE(error);
        EXPECT_EQ(error->code(), "invalid_argument");
      });
}
TEST(ButaneWindowsPlugin, DiscoveryStatusUsesSharedErrors) {
  Fixture f;
  f.discovery->discover_error =
      GattDiscoveryError(GattDiscoveryStatus::kAccessDenied, std::nullopt);
  f.plugin->DiscoverServices(PeripheralSession("00:A1:B2:C3:D4:E5"),
      nullptr, [](auto error) {
        ASSERT_TRUE(error);
        EXPECT_EQ(error->code(), "unauthorized");
        EXPECT_EQ(error->message(), "Bluetooth GATT access was denied.");
      });
}
TEST(ButaneWindowsPlugin, WriteCharacteristicForwardsBothOptionsAndBytes) {
  Fixture f;
  const PeripheralSession session("00:A1:B2:C3:D4:E5");
  for (const bool without_response : {false, true}) {
    f.plugin->WriteCharacteristic(session, "180D", "2A37", {0, 1, 255},
        without_response, [](auto error) { EXPECT_FALSE(error); });
    EXPECT_EQ(f.operations->last_address, 0x00A1B2C3D4E5ULL);
    EXPECT_EQ(f.operations->bytes, (std::vector<uint8_t>{0, 1, 255}));
    EXPECT_EQ(f.operations->without, without_response);
  }
}
TEST(ButaneWindowsPlugin, WriteCharacteristicRejectsMalformedIdentity) {
  Fixture f;
  f.plugin->WriteCharacteristic(PeripheralSession("bad"), "180D", "2A37",
      {}, false, [](auto error) {
        ASSERT_TRUE(error); EXPECT_EQ(error->code(), "invalid_argument");
      });
  EXPECT_EQ(f.operations->last_address, 0u);
}
TEST(ButaneWindowsPlugin, ObservePostsValueBeforeFlutterApi) {
  Fixture f;
  const PeripheralSession session("00:A1:B2:C3:D4:E5");
  f.plugin->ObserveCharacteristic(true, session, "180D", "2A37",
      [](auto error) { EXPECT_FALSE(error); });
  ASSERT_TRUE(f.operations->value_callback);
  f.operations->value_callback({0x00A1B2C3D4E5ULL,
      "0000180d-0000-1000-8000-00805f9b34fb",
      "00002a37-0000-1000-8000-00805f9b34fb", {4, 5}});
  EXPECT_TRUE(f.sink->characteristic_values.empty());
  f.runner->RunAll();
  ASSERT_EQ(f.sink->characteristic_values.size(), 1u);
  EXPECT_EQ(f.sink->characteristic_values[0], (std::vector<uint8_t>{4, 5}));
  EXPECT_EQ(f.sink->characteristics[0].service_uuid(),
      "0000180d-0000-1000-8000-00805f9b34fb");
}
TEST(ButaneWindowsPlugin, UnobserveForwardsDisable) {
  Fixture f;
  f.plugin->ObserveCharacteristic(false,
      PeripheralSession("00:A1:B2:C3:D4:E5"), "180D", "2A37",
      [](auto error) { EXPECT_FALSE(error); });
  EXPECT_FALSE(f.operations->observing);
}
TEST(ButaneWindowsPlugin, WriteDescriptorForwardsFullPathAndErrors) {
  Fixture f;
  f.operations->error = FlutterError("unauthorized", "denied");
  f.plugin->WriteDescriptor(PeripheralSession("00:A1:B2:C3:D4:E5"),
      "180D", "2A37", "2902", {9, 8}, [](auto error) {
        ASSERT_TRUE(error); EXPECT_EQ(error->code(), "unauthorized");
      });
  EXPECT_EQ(f.operations->descriptor,
      "00002902-0000-1000-8000-00805f9b34fb");
  EXPECT_EQ(f.operations->bytes, (std::vector<uint8_t>{9, 8}));
}
TEST(ButaneWindowsPlugin, ReadRssiReturnsFreshAdvertisementSnapshot) {
  Fixture f;
  f.cache->Observe(0x00A1B2C3D4E5ULL, -61, RssiCache::Clock::now());
  f.plugin->ReadRssi(PeripheralSession("00:A1:B2:C3:D4:E5"),
      [](auto result) { ASSERT_FALSE(result.has_error());
                        EXPECT_EQ(result.value(), -61); });
}
TEST(ButaneWindowsPlugin, ReadRssiRejectsMissingAndStaleSnapshot) {
  Fixture f;
  f.plugin->ReadRssi(PeripheralSession("00:A1:B2:C3:D4:E5"),
      [](auto result) { ASSERT_TRUE(result.has_error());
                        EXPECT_EQ(result.error().code(), "rssi-unavailable"); });
  f.cache->Observe(0x00A1B2C3D4E5ULL, -61,
                   RssiCache::Clock::now() - 31s);
  f.plugin->ReadRssi(PeripheralSession("00:A1:B2:C3:D4:E5"),
      [](auto result) { ASSERT_TRUE(result.has_error());
                        EXPECT_EQ(result.error().code(), "rssi-unavailable"); });
}
TEST(ButaneWindowsPlugin, RequestMtuReturnsNegotiatedValueAndRejectsRange) {
  Fixture f;
  f.plugin->RequestMtu(PeripheralSession("00:A1:B2:C3:D4:E5"), 512,
      [](auto result) { ASSERT_FALSE(result.has_error());
                        EXPECT_EQ(result.value(), 247); });
  EXPECT_EQ(f.operations->mtu, 512);
  f.plugin->RequestMtu(PeripheralSession("00:A1:B2:C3:D4:E5"), 22,
      [](auto result) { ASSERT_TRUE(result.has_error());
                        EXPECT_EQ(result.error().code(), "invalid_argument"); });
  EXPECT_EQ(f.operations->mtu, 512);
}
TEST(ButaneWindowsPlugin, OperationsCloseBeforeDispatchDependencies) {
  Fixture f;
  const auto lifecycle = f.lifecycle;
  f.plugin.reset();
  ASSERT_EQ(lifecycle->size(), 3u);
  EXPECT_EQ((*lifecycle)[0], "operations");
  EXPECT_EQ((*lifecycle)[1], "sink");
  EXPECT_EQ((*lifecycle)[2], "runner");
}
}  // namespace butane_windows::test
