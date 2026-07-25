#include "butane_windows_plugin.h"

#include <memory>
#include <string>
#include <string_view>

namespace butane_windows {
namespace {

FlutterError Unimplemented(std::string_view method) {
  return FlutterError(
      "unimplemented",
      std::string(method) + " is not implemented on Windows.");
}

}  // namespace

void ButaneWindowsPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  auto plugin = std::make_unique<ButaneWindowsPlugin>();
  ButaneHostApi::SetUp(registrar->messenger(), plugin.get());
  registrar->AddPlugin(std::move(plugin));
}

ButaneWindowsPlugin::ButaneWindowsPlugin() {}
ButaneWindowsPlugin::~ButaneWindowsPlugin() {}

void ButaneWindowsPlugin::State(
    const ClientSession* session,
    std::function<void(ErrorOr<ClientState> reply)> result) {
  result(Unimplemented("state"));
}

void ButaneWindowsPlugin::Scan(
    const ClientSession* session,
    const flutter::EncodableList* for_services,
    std::function<void(std::optional<FlutterError> reply)> result) {
  result(Unimplemented("scan"));
}

void ButaneWindowsPlugin::CancelScan(
    const ClientSession* session,
    std::function<void(std::optional<FlutterError> reply)> result) {
  result(Unimplemented("cancelScan"));
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
