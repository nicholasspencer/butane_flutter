#include "butane_bonding_winrt.h"

#include "butane_error.h"

#include <winrt/Windows.Devices.Bluetooth.h>
#include <winrt/Windows.Devices.Enumeration.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/base.h>

#include <mutex>
#include <unordered_set>
#include <utility>

namespace butane_windows {
namespace {
using winrt::Windows::Devices::Bluetooth::BluetoothLEDevice;
using winrt::Windows::Devices::Enumeration::DeviceInformation;
using winrt::Windows::Devices::Enumeration::DevicePairingResultStatus;

NativeBondingResult PairedResult(bool paired) {
  return {paired ? NativeBondingStatus::kPaired
                 : NativeBondingStatus::kUnpaired,
          paired ? "The Bluetooth device is paired."
                 : "The Bluetooth device is not paired.",
          std::nullopt};
}

NativeBondingResult NotFoundResult() {
  return {NativeBondingStatus::kNotFound,
          "Bluetooth device information was not found.", std::nullopt};
}

NativeBondingResult FailedResult(const winrt::hresult_error& error) {
  return {NativeBondingStatus::kFailed, winrt::to_string(error.message()),
          error.code().value};
}

void CloseDevice(BluetoothLEDevice& device) {
  if (!device) return;
  try {
    device.Close();
  } catch (const winrt::hresult_error&) {
  }
}

class WinrtNativeBonding final
    : public NativeBonding,
      public std::enable_shared_from_this<WinrtNativeBonding> {
 public:
  void Pair(uint64_t address, Completion completion) override {
    PairAsync(shared_from_this(), address, std::move(completion));
  }

  void State(uint64_t address, Completion completion) override {
    StateAsync(shared_from_this(), address, std::move(completion));
  }

  void Close() override {
    const std::scoped_lock lock(mutex_);
    closed_ = true;
  }

 private:
  bool IsClosed() const {
    const std::scoped_lock lock(mutex_);
    return closed_;
  }

  static void Complete(const std::shared_ptr<WinrtNativeBonding>& owner,
                       const Completion& completion,
                       NativeBondingResult result) {
    if (!owner->IsClosed() && completion) completion(std::move(result));
  }

  static winrt::Windows::Foundation::IAsyncOperation<DeviceInformation>
  ResolveDeviceInformation(
      const std::shared_ptr<WinrtNativeBonding>& owner, uint64_t address,
      BluetoothLEDevice& device) {
    device = co_await BluetoothLEDevice::FromBluetoothAddressAsync(address);
    if (owner->IsClosed() || !device) {
      co_return DeviceInformation{nullptr};
    }
    co_return co_await DeviceInformation::CreateFromIdAsync(
        device.DeviceId());
  }

  static winrt::fire_and_forget PairAsync(
      std::shared_ptr<WinrtNativeBonding> owner, uint64_t address,
      Completion completion) {
    BluetoothLEDevice device{nullptr};
    try {
      const auto information =
          co_await ResolveDeviceInformation(owner, address, device);
      if (owner->IsClosed()) {
        CloseDevice(device);
        co_return;
      }
      if (!information) {
        CloseDevice(device);
        Complete(owner, completion, NotFoundResult());
        co_return;
      }

      const auto pairing = information.Pairing();
      if (pairing.IsPaired()) {
        CloseDevice(device);
        Complete(owner, completion, PairedResult(true));
        co_return;
      }
      const auto pairing_result = co_await pairing.PairAsync();
      const auto status = pairing_result.Status();
      CloseDevice(device);
      Complete(owner, completion,
               PairedResult(status == DevicePairingResultStatus::Paired ||
                            status ==
                                DevicePairingResultStatus::AlreadyPaired));
    } catch (const winrt::hresult_error& error) {
      CloseDevice(device);
      Complete(owner, completion, FailedResult(error));
    }
  }

  static winrt::fire_and_forget StateAsync(
      std::shared_ptr<WinrtNativeBonding> owner, uint64_t address,
      Completion completion) {
    BluetoothLEDevice device{nullptr};
    try {
      const auto information =
          co_await ResolveDeviceInformation(owner, address, device);
      if (owner->IsClosed()) {
        CloseDevice(device);
        co_return;
      }
      if (!information) {
        CloseDevice(device);
        Complete(owner, completion, NotFoundResult());
        co_return;
      }
      const bool paired = information.Pairing().IsPaired();
      CloseDevice(device);
      Complete(owner, completion, PairedResult(paired));
    } catch (const winrt::hresult_error& error) {
      CloseDevice(device);
      Complete(owner, completion, FailedResult(error));
    }
  }

  mutable std::mutex mutex_;
  bool closed_ = false;
};

FlutterError BondingError(const NativeBondingResult& result) {
  const ButaneErrorCode fallback =
      result.status == NativeBondingStatus::kNotFound
          ? ButaneErrorCode::kNotFound
          : ButaneErrorCode::kOperationFailed;
  if (result.hresult) {
    return MakeButaneError(fallback, result.message, *result.hresult);
  }
  return MakeButaneError(
      fallback, result.message,
      result.status == NativeBondingStatus::kNotFound ? "deviceNotFound"
                                                       : "pairingFailed");
}
}  // namespace

struct WindowsBondingBackend::CallbackState {
  std::mutex mutex;
  bool closed = false;
  std::unordered_set<uint64_t> in_flight;
};

std::shared_ptr<NativeBonding> CreateNativeBonding() {
  return std::make_shared<WinrtNativeBonding>();
}

WindowsBondingBackend::WindowsBondingBackend(
    std::shared_ptr<NativeBonding> native)
    : native_(std::move(native)), state_(std::make_shared<CallbackState>()) {}

WindowsBondingBackend::~WindowsBondingBackend() { Close(); }

void WindowsBondingBackend::Bond(uint64_t address,
                                 PeripheralSession session,
                                 StateCallback on_state,
                                 Completion completion) {
  bool already_in_progress = false;
  {
    const std::scoped_lock lock(state_->mutex);
    if (state_->closed) return;
    already_in_progress = !state_->in_flight.insert(address).second;
  }
  if (already_in_progress) {
    completion(MakeButaneError(ButaneErrorCode::kOperationFailed,
                               "Bluetooth pairing is already in progress.",
                               "pairingInProgress"));
    return;
  }

  on_state(BondSnapshot{session, BondState::kBonding});
  const std::weak_ptr<CallbackState> weak = state_;
  native_->Pair(
      address,
      [weak, address, session = std::move(session),
       on_state = std::move(on_state),
       completion = std::move(completion)](NativeBondingResult result) mutable {
        const auto state = weak.lock();
        if (!state) return;
        {
          const std::scoped_lock lock(state->mutex);
          if (state->closed) return;
          state->in_flight.erase(address);
        }
        const bool paired = result.status == NativeBondingStatus::kPaired;
        on_state(BondSnapshot{std::move(session),
                              paired ? BondState::kBonded
                                     : BondState::kNone});
        if (paired) {
          completion(std::nullopt);
        } else {
          completion(BondingError(result));
        }
      });
}

void WindowsBondingBackend::State(uint64_t address,
                                  StateCompletion completion) {
  bool pairing = false;
  {
    const std::scoped_lock lock(state_->mutex);
    if (state_->closed) return;
    pairing = state_->in_flight.find(address) != state_->in_flight.end();
  }
  if (pairing) {
    completion(BondState::kBonding);
    return;
  }

  const std::weak_ptr<CallbackState> weak = state_;
  native_->State(
      address,
      [weak, completion = std::move(completion)](
          NativeBondingResult result) mutable {
        const auto state = weak.lock();
        if (!state) return;
        {
          const std::scoped_lock lock(state->mutex);
          if (state->closed) return;
        }
        if (result.status == NativeBondingStatus::kPaired) {
          completion(BondState::kBonded);
        } else if (result.status == NativeBondingStatus::kUnpaired) {
          completion(BondState::kNone);
        } else {
          completion(BondingError(result));
        }
      });
}

void WindowsBondingBackend::Close() {
  {
    const std::scoped_lock lock(state_->mutex);
    if (state_->closed) return;
    state_->closed = true;
    state_->in_flight.clear();
  }
  native_->Close();
}

}  // namespace butane_windows
