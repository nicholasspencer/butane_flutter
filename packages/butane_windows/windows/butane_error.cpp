#include "butane_error.h"

#include <flutter/encodable_value.h>

#include <cstdint>
#include <iomanip>
#include <sstream>
#include <stdexcept>
#include <string>
#include <utility>

namespace butane_windows {
namespace {

std::string WireName(ButaneErrorCode code) {
  switch (code) {
    case ButaneErrorCode::kUnsupported:
      return "unsupported";
    case ButaneErrorCode::kUnavailable:
      return "unavailable";
    case ButaneErrorCode::kPoweredOff:
      return "poweredOff";
    case ButaneErrorCode::kNotFound:
      return "notFound";
    case ButaneErrorCode::kNotConnected:
      return "notConnected";
    case ButaneErrorCode::kConnectFailed:
      return "connectFailed";
    case ButaneErrorCode::kDisconnected:
      return "disconnected";
    case ButaneErrorCode::kTimeout:
      return "timeout";
    case ButaneErrorCode::kInvalidArgument:
      return "invalidArgument";
    case ButaneErrorCode::kOperationFailed:
      return "operationFailed";
  }
  throw std::logic_error("unknown Butane error code");
}

FlutterError BuildError(ButaneErrorCode code, std::string message,
                        std::string native_code) {
  flutter::EncodableMap details;
  details.emplace(flutter::EncodableValue("platform"),
                  flutter::EncodableValue("windows"));
  details.emplace(flutter::EncodableValue("nativeCode"),
                  flutter::EncodableValue(std::move(native_code)));
  return FlutterError(WireName(code), message,
                      flutter::EncodableValue(std::move(details)));
}

ButaneErrorCode MapHresult(int32_t hresult, ButaneErrorCode fallback) {
  switch (static_cast<uint32_t>(hresult)) {
    case 0x80070057:
      return ButaneErrorCode::kInvalidArgument;
    case 0x80004001:
    case 0x80070032:
    case 0x80070078:
      return ButaneErrorCode::kUnsupported;
    case 0x80070002:
    case 0x80070003:
    case 0x80070490:
      return ButaneErrorCode::kNotFound;
    case 0x8007048F:
    case 0x800708CA:
      return ButaneErrorCode::kNotConnected;
    case 0x80000013:
    case 0x80070651:
      return ButaneErrorCode::kDisconnected;
    case 0x80070102:
    case 0x800705B4:
      return ButaneErrorCode::kTimeout;
    default:
      return fallback;
  }
}

std::string FormatHresult(int32_t hresult) {
  std::ostringstream stream;
  stream << "0x" << std::uppercase << std::hex << std::setw(8)
         << std::setfill('0') << static_cast<uint32_t>(hresult);
  return stream.str();
}

std::string FormatProtocolStatus(uint8_t protocol_status) {
  std::ostringstream stream;
  stream << "0x" << std::uppercase << std::hex << std::setw(2)
         << std::setfill('0') << static_cast<unsigned>(protocol_status);
  return stream.str();
}

}  // namespace

FlutterError MakeButaneError(ButaneErrorCode fallback, std::string message,
                             std::string_view native_code) {
  return BuildError(fallback, std::move(message), std::string(native_code));
}

FlutterError MakeButaneError(ButaneErrorCode fallback, std::string message,
                             uint8_t protocol_status) {
  return BuildError(fallback, std::move(message),
                    FormatProtocolStatus(protocol_status));
}

FlutterError MakeButaneError(ButaneErrorCode fallback, std::string message,
                             int32_t hresult) {
  return BuildError(MapHresult(hresult, fallback), std::move(message),
                    FormatHresult(hresult));
}

}  // namespace butane_windows
