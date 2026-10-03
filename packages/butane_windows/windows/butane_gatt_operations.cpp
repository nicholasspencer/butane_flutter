#include "butane_gatt_operations.h"
#include "butane_error.h"

#include <stdexcept>
#include <string>

namespace butane_windows {

FlutterError GattOperationError(
    std::string_view operation, GattOperationStatus status,
    std::optional<uint8_t> protocol_error) {
  const std::string operation_name(operation);
  switch (status) {
    case GattOperationStatus::kUnreachable:
      return MakeButaneError(
          ButaneErrorCode::kNotConnected,
          "Peripheral is unreachable during " + operation_name + ".",
          "gattUnreachable");
    case GattOperationStatus::kProtocolError:
      return MakeButaneError(
          ButaneErrorCode::kOperationFailed,
          operation_name + " failed with GATT protocol error " +
              std::to_string(static_cast<unsigned>(
                  protocol_error.value_or(uint8_t{0}))) +
              ".",
          protocol_error.value_or(uint8_t{0}));
    case GattOperationStatus::kAccessDenied:
      return MakeButaneError(
          ButaneErrorCode::kOperationFailed,
          "Bluetooth GATT access was denied during " + operation_name + ".",
          "gattAccessDenied");
    case GattOperationStatus::kNotFound:
      return MakeButaneError(
          ButaneErrorCode::kNotFound,
          "A GATT attribute required for " + operation_name +
              " was not found.",
          "gattAttributeNotFound");
    case GattOperationStatus::kUnsupported:
      return MakeButaneError(
          ButaneErrorCode::kUnsupported,
          operation_name + " is not supported by this device.",
          "gattUnsupported");
    case GattOperationStatus::kSuccess:
      throw std::logic_error("success is not a GATT operation error");
  }
  throw std::logic_error("unknown GATT operation status");
}

}  // namespace butane_windows
