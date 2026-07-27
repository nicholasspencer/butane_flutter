#include "butane_central.h"
#include <optional>
#include <string_view>
namespace butane_windows {
std::string FormatBluetoothAddress(uint64_t address);
std::optional<std::string> NormalizeUuid(std::string_view uuid);
ClientState MapClientState(bool adapter_present, bool access_denied,
                           NativeRadioState state) {
  if (!adapter_present) return ClientState::kUnsupported;
  if (access_denied) return ClientState::kUnauthorized;
  switch (state) {
    case NativeRadioState::kOn: return ClientState::kPoweredOn;
    case NativeRadioState::kOff: return ClientState::kPoweredOff;
    case NativeRadioState::kDisabled: return ClientState::kUnauthorized;
    default: return ClientState::kUnknown;
  }
}
ErrorOr<ScanResult> BuildScanResult(const AdvertisementEvent& event,
                                    const ClientSession* session) {
  flutter::EncodableList service_uuids;
  for (const auto& uuid : event.service_uuids) {
    auto normalized = NormalizeUuid(uuid);
    if (!normalized) return FlutterError("invalid_argument", "Advertisement contains an invalid service UUID.");
    service_uuids.emplace_back(*normalized);
  }
  flutter::EncodableMap service_data;
  for (const auto& [uuid, bytes] : event.service_data) {
    auto normalized = NormalizeUuid(uuid);
    if (!normalized) return FlutterError("invalid_argument", "Advertisement contains an invalid service-data UUID.");
    service_data.emplace(flutter::EncodableValue(*normalized),
                         flutter::EncodableValue(bytes));
  }
  std::vector<uint8_t> manufacturer_bytes;
  for (const auto& section : event.manufacturer_data) {
    manufacturer_bytes.push_back(section.company_id & 0xff);
    manufacturer_bytes.push_back((section.company_id >> 8) & 0xff);
    manufacturer_bytes.insert(manufacturer_bytes.end(), section.data.begin(),
                              section.data.end());
  }
  const std::string identifier = FormatBluetoothAddress(event.bluetooth_address);
  PeripheralSession peripheral_session(
      identifier, session ? session->client_identifier() : nullptr,
      session ? session->adapter_identifier() : nullptr,
      session ? session->restoration_identifier() : nullptr);
  const int64_t rssi = event.rssi;
  Peripheral peripheral(peripheral_session,
      event.peripheral_name ? &*event.peripheral_name : nullptr, &rssi,
      ConnectionState::kDisconnected);
  const int64_t tx_power = event.tx_power ? *event.tx_power : 0;
  AdvertisementData data(
      event.local_name ? &*event.local_name : nullptr, &manufacturer_bytes,
      &service_uuids, &service_data, event.tx_power ? &tx_power : nullptr,
      event.is_connectable ? &*event.is_connectable : nullptr);
  return ScanResult(peripheral, data);
}
ErrorOr<std::vector<std::string>> NormalizeServiceFilter(
    const flutter::EncodableList* for_services) {
  std::vector<std::string> result;
  if (!for_services) return result;
  for (const auto& value : *for_services) {
    const auto* uuid = std::get_if<std::string>(&value);
    if (!uuid) return FlutterError("invalid_argument", "Service filters must contain only UUID strings.");
    auto normalized = NormalizeUuid(*uuid);
    if (!normalized) return FlutterError("invalid_argument", "Service filter contains an invalid UUID.");
    result.push_back(*normalized);
  }
  return result;
}
}  // namespace butane_windows
