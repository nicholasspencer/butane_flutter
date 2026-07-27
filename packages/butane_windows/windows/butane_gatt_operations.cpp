#include "butane_gatt_operations.h"

#include <stdexcept>
#include <string>

namespace butane_windows {

FlutterError GattOperationError(
    std::string_view operation, GattOperationStatus status,
    std::optional<uint8_t> protocol_error) {
  const std::string operation_name(operation);
  switch (status) {
    case GattOperationStatus::kUnreachable:
      return FlutterError(
          "not-connected",
          "Peripheral is unreachable during " + operation_name + ".");
    case GattOperationStatus::kProtocolError:
      return FlutterError(
          "gatt-operation-failed",
          operation_name + " failed with GATT protocol error " +
              std::to_string(static_cast<unsigned>(
                  protocol_error.value_or(uint8_t{0}))) +
              ".");
    case GattOperationStatus::kAccessDenied:
      return FlutterError(
          "unauthorized", "Bluetooth GATT access was denied during " +
                              operation_name + ".");
    case GattOperationStatus::kNotFound:
      return FlutterError(
          "not-found", "A GATT attribute required for " + operation_name +
                           " was not found.");
    case GattOperationStatus::kUnsupported:
      return FlutterError(
          "unsupported", operation_name + " is not supported by this device.");
    case GattOperationStatus::kSuccess:
      throw std::logic_error("success is not a GATT operation error");
  }
  throw std::logic_error("unknown GATT operation status");
}

}  // namespace butane_windows
