#ifndef PACKAGES_BUTANE_WINDOWS_WINDOWS_BUTANE_GATT_OPERATIONS_H_
#define PACKAGES_BUTANE_WINDOWS_WINDOWS_BUTANE_GATT_OPERATIONS_H_

#include "Api.gen.h"

#include <cstdint>
#include <functional>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

namespace butane_windows {

struct GattValueEvent {
  uint64_t address;
  std::string service_uuid;
  std::string characteristic_uuid;
  std::vector<uint8_t> value;
};

enum class GattOperationStatus {
  kSuccess,
  kUnreachable,
  kProtocolError,
  kAccessDenied,
  kNotFound,
  kUnsupported,
};

FlutterError GattOperationError(
    std::string_view operation, GattOperationStatus status,
    std::optional<uint8_t> protocol_error = std::nullopt);

class GattOperationsBackend {
 public:
  using Completion = std::function<void(std::optional<FlutterError>)>;
  using ValueCallback = std::function<void(GattValueEvent)>;
  using MtuCompletion = std::function<void(ErrorOr<int64_t>)>;

  virtual ~GattOperationsBackend() = default;
  virtual void WriteCharacteristic(
      uint64_t address, std::string service_uuid,
      std::string characteristic_uuid, std::vector<uint8_t> value,
      bool without_response, Completion completion) = 0;
  virtual void ObserveCharacteristic(
      bool observe, uint64_t address, std::string service_uuid,
      std::string characteristic_uuid, ValueCallback on_value,
      Completion completion) = 0;
  virtual void WriteDescriptor(
      uint64_t address, std::string service_uuid,
      std::string characteristic_uuid, std::string descriptor_uuid,
      std::vector<uint8_t> value, Completion completion) = 0;
  virtual void RequestMtu(
      uint64_t address, int64_t requested_mtu,
      MtuCompletion completion) = 0;
  virtual void Close() = 0;
};

}  // namespace butane_windows

#endif
