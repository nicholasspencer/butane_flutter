#ifndef PACKAGES_BUTANE_WINDOWS_WINDOWS_BUTANE_BONDING_H_
#define PACKAGES_BUTANE_WINDOWS_WINDOWS_BUTANE_BONDING_H_

#include "Api.gen.h"

#include <cstdint>
#include <functional>
#include <optional>

namespace butane_windows {

struct BondSnapshot {
  PeripheralSession session;
  BondState state;
};

class BondingBackend {
 public:
  using StateCallback = std::function<void(BondSnapshot)>;
  using Completion = std::function<void(std::optional<FlutterError>)>;
  using StateCompletion = std::function<void(ErrorOr<BondState>)>;

  virtual ~BondingBackend() = default;
  virtual void Bond(uint64_t address, PeripheralSession session,
                    StateCallback on_state, Completion completion) = 0;
  virtual void State(uint64_t address, StateCompletion completion) = 0;
  virtual void Close() = 0;
};

}  // namespace butane_windows

#endif
