#ifndef FLUTTER_PLUGIN_BUTANE_WINDOWS_PLUGIN_H_
#define FLUTTER_PLUGIN_BUTANE_WINDOWS_PLUGIN_H_

#include "Api.gen.h"
#include "butane_central_winrt.h"
#include "butane_connection.h"

#include <flutter/plugin_registrar_windows.h>

#include <memory>
#include <functional>

namespace butane_windows {
class PlatformTaskRunner {
 public:
  virtual ~PlatformTaskRunner() = default;
  virtual void PostTask(std::function<void()> task) = 0;
};
class FlutterEventSink {
 public:
  virtual ~FlutterEventSink() = default;
  virtual void OnClientState(const std::string* client_identifier,
                             ClientState state) = 0;
  virtual void OnScanResult(const ScanResult& scan_result) = 0;
  virtual void OnConnectionState(const Peripheral& peripheral,
                                 ConnectionState state) = 0;
};

bool TryInitializeWinrtApartment() noexcept;
bool TryInitializeWinrtApartment(
    const std::function<void()>& initializer) noexcept;
bool ProbePlatformWindow(const std::function<HWND()>& probe) noexcept;
std::unique_ptr<PlatformTaskRunner> CreatePlatformTaskRunner(
    flutter::PluginRegistrarWindows* registrar) noexcept;

class ButaneWindowsPlugin : public flutter::Plugin, public ButaneHostApi {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);
  ButaneWindowsPlugin();
  ButaneWindowsPlugin(std::unique_ptr<CentralBackend> central,
                      std::unique_ptr<ConnectionBackend> connection,
                      std::unique_ptr<PlatformTaskRunner> platform_task_runner,
                      std::unique_ptr<FlutterEventSink> event_sink);
  ~ButaneWindowsPlugin() override;

  ButaneWindowsPlugin(const ButaneWindowsPlugin&) = delete;
  ButaneWindowsPlugin& operator=(const ButaneWindowsPlugin&) = delete;

  void State(const ClientSession* session,
             std::function<void(ErrorOr<ClientState> reply)> result) override;
  void Scan(const ClientSession* session,
            const flutter::EncodableList* for_services,
            std::function<void(std::optional<FlutterError> reply)> result)
      override;
  void CancelScan(
      const ClientSession* session,
      std::function<void(std::optional<FlutterError> reply)> result) override;
  void Peripherals(
      const ClientSession* session,
      const flutter::EncodableList& peripheral_identifiers,
      std::function<void(ErrorOr<flutter::EncodableList> reply)> result)
      override;
  void ConnectedPeripherals(
      const ClientSession* session,
      const flutter::EncodableList& service_uuids,
      std::function<void(ErrorOr<flutter::EncodableList> reply)> result)
      override;
  void Connect(
      const PeripheralSession& session,
      std::function<void(std::optional<FlutterError> reply)> result) override;
  void CancelConnection(
      const PeripheralSession& session,
      std::function<void(std::optional<FlutterError> reply)> result) override;
  void ConnectionState(
      const PeripheralSession& session,
      std::function<void(ErrorOr<butane_windows::ConnectionState> reply)> result)
      override;
  void DiscoverServices(
      const PeripheralSession& session,
      const flutter::EncodableList* service_uuids,
      std::function<void(std::optional<FlutterError> reply)> result) override;
  void Services(
      const PeripheralSession& session,
      std::function<void(ErrorOr<flutter::EncodableList> reply)> result)
      override;
  void DiscoverCharacteristics(
      const PeripheralSession& session, const std::string& service_uuid,
      const flutter::EncodableList* characteristic_uuids,
      std::function<void(std::optional<FlutterError> reply)> result) override;
  void Characteristics(
      const PeripheralSession& session, const std::string& service_uuid,
      std::function<void(ErrorOr<flutter::EncodableList> reply)> result)
      override;
  void ReadCharacteristic(
      const PeripheralSession& session, const std::string& service_uuid,
      const std::string& characteristic_uuid,
      std::function<void(ErrorOr<std::vector<uint8_t>> reply)> result) override;
  void WriteCharacteristic(
      const PeripheralSession& session, const std::string& service_uuid,
      const std::string& characteristic_uuid,
      const std::vector<uint8_t>& value, bool without_response,
      std::function<void(std::optional<FlutterError> reply)> result) override;
  void ObserveCharacteristic(
      bool observe, const PeripheralSession& session,
      const std::string& service_uuid,
      const std::string& characteristic_uuid,
      std::function<void(std::optional<FlutterError> reply)> result) override;
  void ReadDescriptor(
      const PeripheralSession& session, const std::string& service_uuid,
      const std::string& characteristic_uuid,
      const std::string& descriptor_uuid,
      std::function<void(ErrorOr<std::vector<uint8_t>> reply)> result) override;
  void WriteDescriptor(
      const PeripheralSession& session, const std::string& service_uuid,
      const std::string& characteristic_uuid,
      const std::string& descriptor_uuid, const std::vector<uint8_t>& value,
      std::function<void(std::optional<FlutterError> reply)> result) override;
  void ReadRssi(const PeripheralSession& session,
                std::function<void(ErrorOr<int64_t> reply)> result) override;
  void RequestMtu(const PeripheralSession& session, int64_t mtu,
                  std::function<void(ErrorOr<int64_t> reply)> result) override;
  void PeripheralManagerState(
      const PeripheralManagerSession& session,
      std::function<void(ErrorOr<ClientState> reply)> result) override;
  void StartAdvertising(
      const PeripheralManagerSession& session, const std::string* local_name,
      const flutter::EncodableList* service_uuids,
      std::function<void(std::optional<FlutterError> reply)> result) override;
  void StopAdvertising(
      const PeripheralManagerSession& session,
      std::function<void(std::optional<FlutterError> reply)> result) override;
  void AddService(
      const PeripheralManagerSession& session, const MutableService& service,
      std::function<void(std::optional<FlutterError> reply)> result) override;
  void RemoveService(
      const PeripheralManagerSession& session,
      const std::string& service_uuid,
      std::function<void(std::optional<FlutterError> reply)> result) override;
  void RemoveAllServices(
      const PeripheralManagerSession& session,
      std::function<void(std::optional<FlutterError> reply)> result) override;
  void RespondToRequest(
      const PeripheralManagerSession& session, int64_t request_id,
      const AttResult& request_result, const std::vector<uint8_t>* value,
      std::function<void(std::optional<FlutterError> reply)> result) override;
  void UpdateValue(
      const PeripheralManagerSession& session,
      const std::string& service_uuid,
      const std::string& characteristic_uuid,
      const std::vector<uint8_t>& value,
      std::function<void(ErrorOr<bool> reply)> result) override;
 private:
  flutter::BinaryMessenger* messenger_ = nullptr;
  std::unique_ptr<RssiCache> rssi_cache_;
  std::unique_ptr<PlatformTaskRunner> platform_task_runner_;
  std::unique_ptr<FlutterEventSink> event_sink_;
  std::unique_ptr<CentralBackend> central_;
  std::unique_ptr<ConnectionBackend> connection_;
};

}  // namespace butane_windows

#endif  // FLUTTER_PLUGIN_BUTANE_WINDOWS_PLUGIN_H_
