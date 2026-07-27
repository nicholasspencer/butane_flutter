#include "butane_windows_plugin.h"
#include "butane_central.h"
#define CharacteristicProperty ButaneConversionCharacteristicProperty
#include "butane_conversions.h"
#undef CharacteristicProperty
#include <windows.h>
#include <winrt/base.h>
#include <atomic>
#include <deque>

#include <memory>
#include <mutex>
#include <string>
#include <string_view>

namespace butane_windows {
namespace {

FlutterError Unimplemented(std::string_view method) {
  return FlutterError(
      "unimplemented",
      std::string(method) + " is not implemented on Windows.");
}
class FlutterPlatformTaskRunner final : public PlatformTaskRunner {
 public:
  explicit FlutterPlatformTaskRunner(flutter::PluginRegistrarWindows* registrar)
      : registrar_(registrar), window_(registrar->GetView()->GetNativeWindow()) {
    delegate_id_ = registrar_->RegisterTopLevelWindowProcDelegate(
        [this](HWND, UINT message, WPARAM, LPARAM) -> std::optional<LRESULT> {
          if (message != kTaskMessage) return std::nullopt;
          Drain();
          return 0;
        });
  }
  ~FlutterPlatformTaskRunner() override {
    registrar_->UnregisterTopLevelWindowProcDelegate(delegate_id_);
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
 private:
  ButaneFlutterApi api_;
};

}  // namespace

void ButaneWindowsPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  auto plugin = std::make_unique<ButaneWindowsPlugin>();
  static std::once_flag initialized;
  std::call_once(initialized, [] {
    winrt::init_apartment(winrt::apartment_type::multi_threaded);
  });
  plugin->messenger_ = registrar->messenger();
  plugin->platform_task_runner_ =
      std::make_unique<FlutterPlatformTaskRunner>(registrar);
  plugin->event_sink_ =
      std::make_unique<GeneratedFlutterEventSink>(plugin->messenger_);
  plugin->rssi_cache_ = std::make_unique<RssiCache>();
  plugin->central_ =
      std::make_unique<WindowsCentralBackend>(*plugin->rssi_cache_);
  ButaneHostApi::SetUp(registrar->messenger(), plugin.get());
  registrar->AddPlugin(std::move(plugin));
}

ButaneWindowsPlugin::ButaneWindowsPlugin() {}
ButaneWindowsPlugin::ButaneWindowsPlugin(
    std::unique_ptr<CentralBackend> central,
    std::unique_ptr<PlatformTaskRunner> runner,
    std::unique_ptr<FlutterEventSink> sink)
    : platform_task_runner_(std::move(runner)),
      event_sink_(std::move(sink)),
      central_(std::move(central)) {}
ButaneWindowsPlugin::~ButaneWindowsPlugin() {
  if (central_) central_->StopScan();
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
        platform_task_runner_->PostTask([this, client_id, state] {
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
        if (scan_result.has_error()) return;
        platform_task_runner_->PostTask(
            [this, value = ScanResult(scan_result.value())] {
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
  result(Unimplemented("connect"));
}

void ButaneWindowsPlugin::CancelConnection(
    const PeripheralSession& session,
    std::function<void(std::optional<FlutterError> reply)> result) {
  result(Unimplemented("cancelConnection"));
}

void ButaneWindowsPlugin::ConnectionState(
    const PeripheralSession& session,
    std::function<void(ErrorOr<butane_windows::ConnectionState> reply)> result) {
  result(Unimplemented("connectionState"));
}

void ButaneWindowsPlugin::DiscoverServices(
    const PeripheralSession& session,
    const flutter::EncodableList* service_uuids,
    std::function<void(std::optional<FlutterError> reply)> result) {
  result(Unimplemented("discoverServices"));
}

void ButaneWindowsPlugin::Services(
    const PeripheralSession& session,
    std::function<void(ErrorOr<flutter::EncodableList> reply)> result) {
  result(Unimplemented("services"));
}

void ButaneWindowsPlugin::DiscoverCharacteristics(
    const PeripheralSession& session, const std::string& service_uuid,
    const flutter::EncodableList* characteristic_uuids,
    std::function<void(std::optional<FlutterError> reply)> result) {
  result(Unimplemented("discoverCharacteristics"));
}

void ButaneWindowsPlugin::Characteristics(
    const PeripheralSession& session, const std::string& service_uuid,
    std::function<void(ErrorOr<flutter::EncodableList> reply)> result) {
  result(Unimplemented("characteristics"));
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
