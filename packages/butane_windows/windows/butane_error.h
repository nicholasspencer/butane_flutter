#ifndef PACKAGES_BUTANE_WINDOWS_WINDOWS_BUTANE_ERROR_H_
#define PACKAGES_BUTANE_WINDOWS_WINDOWS_BUTANE_ERROR_H_

#include "Api.gen.h"

#include <cstdint>
#include <string>
#include <string_view>

namespace butane_windows {

FlutterError MakeButaneError(ButaneErrorCode fallback,
                             std::string message,
                             std::string_view native_code);
FlutterError MakeButaneError(ButaneErrorCode fallback,
                             std::string message,
                             uint8_t protocol_status);
FlutterError MakeButaneError(ButaneErrorCode fallback,
                             std::string message,
                             int32_t hresult);

}  // namespace butane_windows

#endif
