#include "butane_windows_plugin.h"
#include "butane_central.h"
#include "butane_connection_winrt.h"
#include "butane_conversions.h"
#include "butane_gatt_discovery_winrt.h"
#include <windows.h>
#include <winrt/base.h>
#include <atomic>
#include <algorithm>
#include <deque>

#include <memory>
#include <mutex>
#include <stdexcept>
#include <string>
#include <string_view>

namespace butane_windows {
namespace {

FlutterError Unimplemented(std::string_view method) {
  return FlutterError(
      "unimplemented",
      std::string(method) + " is not implemented on Windows.");
}
Characteristic ToPigeonCharacteristic(const GattCharacteristicData& data) {
  flutter::EncodableList descriptors;
  for (const auto& item : data.descriptors) {
    descriptors.emplace_back(
        flutter::CustomEncodableValue(Descriptor(item.uuid, nullptr)));
  }
  const DecodedCharacteristicProperty decoded =
      CharacteristicPropertyFromMask(data.property_mask);
  const CharacteristicProperty properties(
      decoded.broadcast, decoded.read, decoded.write_without_response,
      decoded.write, decoded.notify, decoded.indicate,
      decoded.authenticated_signed_writes, decoded.extended_properties,
      decoded.notify_encryption_required,
      decoded.indicate_encryption_required);
  return Characteristic(data.uuid, nullptr, &descriptors, &properties);
}
class FlutterPlatformTaskRunner final : public PlatformTaskRunner {
 public:
  FlutterPlatformTaskRunner(flutter::PluginRegistrarWindows* registrar,
                            HWND window)
      : registrar_(registrar), window_(window) {
    delegate_id_ = registrar_->RegisterTopLevelWindowProcDelegate(
        [this](HWND, UINT message, WPARAM, LPARAM) -> std::optional<LRESULT> {
          if (message != kTaskMessage) return std::nullopt;
          Drain();
          return 0;
        });
    delegate_registered_ = delegate_id_ >= 0;
    if (!delegate_registered_) {
      throw std::runtime_error("window delegate registration failed");
    }
  }
  ~FlutterPlatformTaskRunner() override {
    if (delegate_registered_) {
      registrar_->UnregisterTopLevelWindowProcDelegate(delegate_id_);
    }
  }
  void PostTask(std::function<void()> task) override {
    {
      const std::scoped_lock lock(mutex_);
      tasks_.push_back(std::move(task));
    }
    ::PostMessage(window_, kTaskMessage, 0, 0);
  }
 private:
  void Drain() {
    std::deque<std::function<void()>> tasks;
    {
      const std::scoped_lock lock(mutex_);
      tasks.swap(tasks_);
    }
    for (auto& task : tasks) task();
  }
  static constexpr UINT kTaskMessage = WM_APP + 0x42;
  flutter::PluginRegistrarWindows* registrar_;
  HWND window_;
  int delegate_id_;
  bool delegate_registered_ = false;
  std::mutex mutex_;
  std::deque<std::function<void()>> tasks_;
};
class GeneratedFlutterEventSink final : public FlutterEventSink {
 public:
  explicit GeneratedFlutterEventSink(flutter::BinaryMessenger* messenger)
      : api_(messenger) {}
  void OnClientState(const std::string* id, ClientState state) override {
    api_.OnClientState(id, state, [] {}, [](const FlutterError&) {});
  }
  void OnScanResult(const ScanResult& value) override {
    api_.OnScanResult(value, [] {}, [](const FlutterError&) {});
  }
  void OnConnectionState(const Peripheral& peripheral,
                         ConnectionState state) override {
    api_.OnConnectionState(peripheral, state, [] {},
                           [](const FlutterError&) {});
  }
 private:
  ButaneFlutterApi api_;
};

}  // namespace

bool TryInitializeWinrtApartment(
    const std::function<void()>& initializer) noexcept {
  try {
    initializer();
    return true;
  } catch (const winrt::hresult_error&) {
    return false;
  }
}

bool TryInitializeWinrtApartment() noexcept {
  return TryInitializeWinrtApartment([] {
    winrt::init_apartment(winrt::apartment_type::multi_threaded);
  });
}

bool ProbePlatformWindow(const std::function<HWND()>& probe) noexcept {
  try {
    return probe() != nullptr;
  } catch (...) {
    return false;
  }
}

std::unique_ptr<PlatformTaskRunner> CreatePlatformTaskRunner(
    flutter::PluginRegistrarWindows* registrar) noexcept {
  if (!registrar) return nullptr;
  HWND window = nullptr;
  try {
    const auto view = registrar->GetView();
    if (!view) return nullptr;
    window = view->GetNativeWindow();
    if (!window) return nullptr;
    return std::make_unique<FlutterPlatformTaskRunner>(registrar, window);
  } catch (...) {
    return nullptr;
  }
}

void ButaneWindowsPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  if (!registrar || !registrar->messenger()) return;
  auto plugin = std::make_unique<ButaneWindowsPlugin>();
  plugin->messenger_ = registrar->messenger();
  const bool apartment_ready = TryInitializeWinrtApartment();
  plugin->platform_task_runner_ = CreatePlatformTaskRunner(registrar);
  if (plugin->platform_task_runner_) {
    plugin->event_sink_ =
        std::make_unique<GeneratedFlutterEventSink>(plugin->messenger_);
  }
  if (apartment_ready) {
    plugin->rssi_cache_ = std::make_unique<RssiCache>();
    plugin->central_ =
        std::make_unique<WindowsCentralBackend>(*plugin->rssi_cache_);
    plugin->connection_ = std::make_unique<WindowsConnectionBackend>();
    plugin->discovery_ = std::make_unique<WindowsGattDiscoveryBackend>();
  }
  ButaneHostApi::SetUp(registrar->messenger(), plugin.get());
  registrar->AddPlugin(std::move(plugin));
}

ButaneWindowsPlugin::ButaneWindowsPlugin() {}
ButaneWindowsPlugin::ButaneWindowsPlugin(
    std::unique_ptr<CentralBackend> central,
    std::unique_ptr<ConnectionBackend> connection,
    std::unique_ptr<GattDiscoveryBackend> discovery,
    std::unique_ptr<PlatformTaskRunner> runner,
    std::unique_ptr<FlutterEventSink> sink)
    : platform_task_runner_(std::move(runner)),
      event_sink_(std::move(sink)),
      central_(std::move(central)),
      connection_(std::move(connection)),
      discovery_(std::move(discovery)) {}
ButaneWindowsPlugin::~ButaneWindowsPlugin() {
  if (central_) central_->StopScan();
  connection_.reset();
  discovery_.reset();
  central_.reset();
  event_sink_.reset();
  platform_task_runner_.reset();
  rssi_cache_.reset();
  messenger_ = nullptr;
}

void ButaneWindowsPlugin::State(
    const ClientSession* session,
    std::function<void(ErrorOr<ClientState> reply)> result) {
  if (!central_) { result(Unimplemented("state")); return; }
  const std::optional<std::string> client_id =
      session && session->client_identifier()
          ? std::optional<std::string>(*session->client_identifier())
          : std::nullopt;
  auto initial = std::make_shared<std::atomic_bool>(true);
  central_->QueryState(
      [this, client_id, initial, result = std::move(result)](
          ClientState state) mutable {
        if (initial->exchange(false)) { result(state); return; }
        if (!platform_task_runner_ || !event_sink_) return;
        platform_task_runner_->PostTask([this, client_id, state] {
          if (!event_sink_) return;
          event_sink_->OnClientState(client_id ? &*client_id : nullptr, state);
        });
      });
}

void ButaneWindowsPlugin::Scan(
    const ClientSession* session,
    const flutter::EncodableList* for_services,
    std::function<void(std::optional<FlutterError> reply)> result) {
  if (!central_) { result(Unimplemented("scan")); return; }
  auto filter = NormalizeServiceFilter(for_services);
  if (filter.has_error()) { result(filter.error()); return; }
  const ClientSession copy = session ? *session : ClientSession();
  auto error = central_->StartScan(
      filter.value(), [this, copy](AdvertisementEvent event) {
        auto scan_result = BuildScanResult(event, &copy);
        if (scan_result.has_error() || !platform_task_runner_ || !event_sink_) {
          return;
        }
        platform_task_runner_->PostTask(
            [this, value = ScanResult(scan_result.value())] {
              if (!event_sink_) return;
              event_sink_->OnScanResult(value);
            });
      });
  result(std::move(error));
}

void ButaneWindowsPlugin::CancelScan(
    const ClientSession* session,
    std::function<void(std::optional<FlutterError> reply)> result) {
  if (central_) central_->StopScan();
  result(std::nullopt);
}

void ButaneWindowsPlugin::Peripherals(
    const ClientSession* session,
    const flutter::EncodableList& peripheral_identifiers,
    std::function<void(ErrorOr<flutter::EncodableList> reply)> result) {
  result(Unimplemented("peripherals"));
}

void ButaneWindowsPlugin::ConnectedPeripherals(
    const ClientSession* session,
    const flutter::EncodableList& service_uuids,
    std::function<void(ErrorOr<flutter::EncodableList> reply)> result) {
  result(Unimplemented("connectedPeripherals"));
}

void ButaneWindowsPlugin::Connect(
    const PeripheralSession& session,
    std::function<void(std::optional<FlutterError> reply)> result) {
  const auto address = ParseBluetoothAddress(session.peripheral_identifier());
  if (!address) {
    result(FlutterError(
        "invalid_argument",
        "Peripheral identifier must be a Bluetooth address."));
    return;
  }
  if (!connection_) {
    result(Unimplemented("connect"));
    return;
  }
  connection_->Connect(
      *address, session,
      [runner = platform_task_runner_.get(),
       sink = event_sink_.get()](ConnectionSnapshot snapshot) {
        if (!runner || !sink) return;
        runner->PostTask([sink, snapshot = std::move(snapshot)] {
          const Peripheral peripheral(snapshot.session, snapshot.state);
          sink->OnConnectionState(peripheral, snapshot.state);
        });
      },
      std::move(result));
}

void ButaneWindowsPlugin::CancelConnection(
    const PeripheralSession& session,
    std::function<void(std::optional<FlutterError> reply)> result) {
  const auto address = ParseBluetoothAddress(session.peripheral_identifier());
  if (!address) {
    result(FlutterError(
        "invalid_argument",
        "Peripheral identifier must be a Bluetooth address."));
    return;
  }
  if (connection_) connection_->Disconnect(*address);
  result(std::nullopt);
}

void ButaneWindowsPlugin::ConnectionState(
    const PeripheralSession& session,
    std::function<void(ErrorOr<butane_windows::ConnectionState> reply)> result) {
  const auto address = ParseBluetoothAddress(session.peripheral_identifier());
  if (!address) {
    result(FlutterError(
        "invalid_argument",
        "Peripheral identifier must be a Bluetooth address."));
    return;
  }
  result(connection_ ? connection_->State(*address)
                     : ConnectionState::kDisconnected);
}

void ButaneWindowsPlugin::DiscoverServices(
    const PeripheralSession& session,
    const flutter::EncodableList* service_uuids,
    std::function<void(std::optional<FlutterError> reply)> result) {
  const auto address = ParseBluetoothAddress(session.peripheral_identifier());
  if (!address) {
    result(FlutterError("invalid_argument",
        "Peripheral identifier must be a Bluetooth address."));
    return;
  }
  if (!discovery_) { result(Unimplemented("discoverServices")); return; }
  auto filter = NormalizeGattFilter(service_uuids);
  if (filter.has_error()) { result(filter.error()); return; }
  discovery_->DiscoverServices(*address, std::move(filter.value()),
      service_uuids && service_uuids->empty(), std::move(result));
}

void ButaneWindowsPlugin::Services(
    const PeripheralSession& session,
    std::function<void(ErrorOr<flutter::EncodableList> reply)> result) {
  const auto address = ParseBluetoothAddress(session.peripheral_identifier());
  if (!address) {
    result(FlutterError("invalid_argument",
        "Peripheral identifier must be a Bluetooth address."));
    return;
  }
  if (!discovery_) { result(Unimplemented("services")); return; }
  auto services = discovery_->Services(*address);
  if (services.has_error()) { result(services.error()); return; }
  flutter::EncodableList values;
  for (const auto& item : services.value()) {
    values.emplace_back(
        flutter::CustomEncodableValue(Service(item.uuid, item.is_primary)));
  }
  result(std::move(values));
}

void ButaneWindowsPlugin::DiscoverCharacteristics(
    const PeripheralSession& session, const std::string& service_uuid,
    const flutter::EncodableList* characteristic_uuids,
    std::function<void(std::optional<FlutterError> reply)> result) {
  const auto address = ParseBluetoothAddress(session.peripheral_identifier());
  const auto service = NormalizeUuid(service_uuid);
  if (!address || !service) {
    result(FlutterError("invalid_argument",
        "Peripheral identifier and service UUID must be valid."));
    return;
  }
  if (!discovery_) {
    result(Unimplemented("discoverCharacteristics"));
    return;
  }
  auto services = discovery_->Services(*address);
  if (services.has_error()) { result(services.error()); return; }
  if (std::none_of(services.value().begin(), services.value().end(),
                   [&](const auto& item) { return item.uuid == *service; })) {
    result(FlutterError("not-found", "GATT discovery data was not found."));
    return;
  }
  auto filter = NormalizeGattFilter(characteristic_uuids);
  if (filter.has_error()) { result(filter.error()); return; }
  discovery_->DiscoverCharacteristics(
      *address, *service, std::move(filter.value()),
      characteristic_uuids && characteristic_uuids->empty(),
      std::move(result));
}

void ButaneWindowsPlugin::Characteristics(
    const PeripheralSession& session, const std::string& service_uuid,
    std::function<void(ErrorOr<flutter::EncodableList> reply)> result) {
  const auto address = ParseBluetoothAddress(session.peripheral_identifier());
  const auto service = NormalizeUuid(service_uuid);
  if (!address || !service) {
    result(FlutterError("invalid_argument",
        "Peripheral identifier and service UUID must be valid."));
    return;
  }
  if (!discovery_) { result(Unimplemented("characteristics")); return; }
  auto characteristics = discovery_->Characteristics(*address, *service);
  if (characteristics.has_error()) {
    result(characteristics.error());
    return;
  }
  flutter::EncodableList values;
  for (const auto& item : characteristics.value()) {
    values.emplace_back(
        flutter::CustomEncodableValue(ToPigeonCharacteristic(item)));
  }
  result(std::move(values));
}

void ButaneWindowsPlugin::ReadCharacteristic(
    const PeripheralSession& session, const std::string& service_uuid,
    const std::string& characteristic_uuid,
    std::function<void(ErrorOr<std::vector<uint8_t>> reply)> result) {
  result(Unimplemented("readCharacteristic"));
}

void ButaneWindowsPlugin::WriteCharacteristic(
    const PeripheralSession& session, const std::string& service_uuid,
    const std::string& characteristic_uuid,
    const std::vector<uint8_t>& value, bool without_response,
    std::function<void(std::optional<FlutterError> reply)> result) {
  result(Unimplemented("writeCharacteristic"));
}

void ButaneWindowsPlugin::ObserveCharacteristic(
    bool observe, const PeripheralSession& session,
    const std::string& service_uuid, const std::string& characteristic_uuid,
    std::function<void(std::optional<FlutterError> reply)> result) {
  result(Unimplemented("observeCharacteristic"));
}

void ButaneWindowsPlugin::ReadDescriptor(
    const PeripheralSession& session, const std::string& service_uuid,
    const std::string& characteristic_uuid,
    const std::string& descriptor_uuid,
    std::function<void(ErrorOr<std::vector<uint8_t>> reply)> result) {
  result(Unimplemented("readDescriptor"));
}

void ButaneWindowsPlugin::WriteDescriptor(
    const PeripheralSession& session, const std::string& service_uuid,
    const std::string& characteristic_uuid,
    const std::string& descriptor_uuid, const std::vector<uint8_t>& value,
    std::function<void(std::optional<FlutterError> reply)> result) {
  result(Unimplemented("writeDescriptor"));
}

void ButaneWindowsPlugin::ReadRssi(
    const PeripheralSession& session,
    std::function<void(ErrorOr<int64_t> reply)> result) {
  result(Unimplemented("readRssi"));
}

void ButaneWindowsPlugin::RequestMtu(
    const PeripheralSession& session, int64_t mtu,
    std::function<void(ErrorOr<int64_t> reply)> result) {
  result(Unimplemented("requestMtu"));
}

void ButaneWindowsPlugin::PeripheralManagerState(
    const PeripheralManagerSession& session,
    std::function<void(ErrorOr<ClientState> reply)> result) {
  result(Unimplemented("peripheralManagerState"));
}

void ButaneWindowsPlugin::StartAdvertising(
    const PeripheralManagerSession& session, const std::string* local_name,
    const flutter::EncodableList* service_uuids,
    std::function<void(std::optional<FlutterError> reply)> result) {
  result(Unimplemented("startAdvertising"));
}

void ButaneWindowsPlugin::StopAdvertising(
    const PeripheralManagerSession& session,
    std::function<void(std::optional<FlutterError> reply)> result) {
  result(Unimplemented("stopAdvertising"));
}

void ButaneWindowsPlugin::AddService(
    const PeripheralManagerSession& session, const MutableService& service,
    std::function<void(std::optional<FlutterError> reply)> result) {
  result(Unimplemented("addService"));
}

void ButaneWindowsPlugin::RemoveService(
    const PeripheralManagerSession& session, const std::string& service_uuid,
    std::function<void(std::optional<FlutterError> reply)> result) {
  result(Unimplemented("removeService"));
}

void ButaneWindowsPlugin::RemoveAllServices(
    const PeripheralManagerSession& session,
    std::function<void(std::optional<FlutterError> reply)> result) {
  result(Unimplemented("removeAllServices"));
}

void ButaneWindowsPlugin::RespondToRequest(
    const PeripheralManagerSession& session, int64_t request_id,
    const AttResult& request_result, const std::vector<uint8_t>* value,
    std::function<void(std::optional<FlutterError> reply)> result) {
  result(Unimplemented("respondToRequest"));
}

void ButaneWindowsPlugin::UpdateValue(
    const PeripheralManagerSession& session, const std::string& service_uuid,
    const std::string& characteristic_uuid,
    const std::vector<uint8_t>& value,
    std::function<void(ErrorOr<bool> reply)> result) {
  result(Unimplemented("updateValue"));
}

}  // namespace butane_windows
