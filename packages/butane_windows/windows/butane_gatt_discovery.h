#ifndef PACKAGES_BUTANE_WINDOWS_WINDOWS_BUTANE_GATT_DISCOVERY_H_
#define PACKAGES_BUTANE_WINDOWS_WINDOWS_BUTANE_GATT_DISCOVERY_H_

#include "Api.gen.h"

#include <cstdint>
#include <functional>
#include <mutex>
#include <optional>
#include <string>
#include <string_view>
#include <unordered_map>
#include <vector>

namespace butane_windows {

enum class GattDiscoveryStatus {
  kSuccess,
  kUnreachable,
  kProtocolError,
  kAccessDenied,
};

struct GattDescriptorData { std::string uuid; };
struct GattCharacteristicData {
  std::string uuid;
  uint32_t property_mask;
  std::vector<GattDescriptorData> descriptors;
};
struct GattServiceData {
  std::string uuid;
  bool is_primary;
};

FlutterError GattDiscoveryError(
    GattDiscoveryStatus status,
    std::optional<uint8_t> protocol_error);
ErrorOr<std::vector<std::string>> NormalizeGattFilter(
    const flutter::EncodableList* values);

// Thread-safe snapshots populated only by successful discovery operations.
class GattDiscoveryCache {
 public:
  void ReplaceServices(uint64_t address, std::vector<GattServiceData> services);
  ErrorOr<std::vector<GattServiceData>> Services(uint64_t address) const;
  bool HasService(uint64_t address, std::string_view service_uuid) const;
  void ReplaceCharacteristics(
      uint64_t address, std::string service_uuid,
      std::vector<GattCharacteristicData> characteristics);
  ErrorOr<std::vector<GattCharacteristicData>> Characteristics(
      uint64_t address, std::string_view service_uuid) const;

 private:
  struct Snapshot {
    std::vector<GattServiceData> services;
    std::unordered_map<std::string, std::vector<GattCharacteristicData>>
        characteristics;
  };
  mutable std::mutex mutex_;
  std::unordered_map<uint64_t, Snapshot> snapshots_;
};

class GattDiscoveryBackend {
 public:
  using Completion = std::function<void(std::optional<FlutterError>)>;
  virtual ~GattDiscoveryBackend() = default;
  virtual void DiscoverServices(
      uint64_t address, std::vector<std::string> service_uuids,
      bool explicit_empty, Completion completion) = 0;
  virtual ErrorOr<std::vector<GattServiceData>> Services(
      uint64_t address) const = 0;
  virtual void DiscoverCharacteristics(
      uint64_t address, std::string service_uuid,
      std::vector<std::string> characteristic_uuids,
      bool explicit_empty, Completion completion) = 0;
  virtual ErrorOr<std::vector<GattCharacteristicData>> Characteristics(
      uint64_t address, std::string_view service_uuid) const = 0;
};

}  // namespace butane_windows
#endif
