#ifndef PACKAGES_BUTANE_WINDOWS_WINDOWS_BUTANE_CENTRAL_H_
#define PACKAGES_BUTANE_WINDOWS_WINDOWS_BUTANE_CENTRAL_H_
#include "Api.gen.h"
#include <cstdint>
#include <map>
#include <optional>
#include <string>
#include <vector>
namespace butane_windows {
struct ManufacturerSection { uint16_t company_id; std::vector<uint8_t> data; };
struct AdvertisementEvent {
  uint64_t bluetooth_address;
  int16_t rssi;
  std::optional<std::string> peripheral_name;
  std::optional<std::string> local_name;
  std::vector<ManufacturerSection> manufacturer_data;
  std::vector<std::string> service_uuids;
  std::map<std::string, std::vector<uint8_t>> service_data;
  std::optional<int16_t> tx_power;
  std::optional<bool> is_connectable;
};
enum class NativeRadioState { kUnknown, kOn, kOff, kDisabled };
ClientState MapClientState(bool adapter_present, bool access_denied,
                           NativeRadioState state);
ErrorOr<ScanResult> BuildScanResult(const AdvertisementEvent& event,
                                    const ClientSession* session);
ErrorOr<std::vector<std::string>> NormalizeServiceFilter(
    const flutter::EncodableList* for_services);
}  // namespace butane_windows
#endif
