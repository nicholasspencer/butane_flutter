#ifndef PACKAGES_BUTANE_WINDOWS_WINDOWS_BUTANE_BONDING_WINRT_H_
#define PACKAGES_BUTANE_WINDOWS_WINDOWS_BUTANE_BONDING_WINRT_H_

#include "butane_bonding.h"

#include <cstdint>
#include <functional>
#include <memory>
#include <optional>
#include <string>

namespace butane_windows {

enum class NativeBondingStatus {
  kPaired,
  kUnpaired,
  kNotFound,
  kFailed,
};

struct NativeBondingResult {
  NativeBondingStatus status;
  std::string message;
  std::optional<int32_t> hresult;
};

class NativeBonding {
 public:
  using Completion = std::function<void(NativeBondingResult)>;

  virtual ~NativeBonding() = default;
  virtual void Pair(uint64_t address, Completion completion) = 0;
  virtual void State(uint64_t address, Completion completion) = 0;
  virtual void Close() = 0;
};

std::shared_ptr<NativeBonding> CreateNativeBonding();

class WindowsBondingBackend final : public BondingBackend {
 public:
  explicit WindowsBondingBackend(
      std::shared_ptr<NativeBonding> native = CreateNativeBonding());
  ~WindowsBondingBackend() override;

  void Bond(uint64_t address, PeripheralSession session,
            StateCallback on_state, Completion completion) override;
  void State(uint64_t address, StateCompletion completion) override;
  void Close() override;

 private:
  struct CallbackState;
  std::shared_ptr<NativeBonding> native_;
  std::shared_ptr<CallbackState> state_;
};

}  // namespace butane_windows

#endif
