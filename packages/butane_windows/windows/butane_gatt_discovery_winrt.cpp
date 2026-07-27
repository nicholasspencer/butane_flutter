#include "butane_gatt_discovery_winrt.h"

#include "butane_conversions.h"

#include <winrt/Windows.Devices.Bluetooth.h>
#include <winrt/Windows.Devices.Bluetooth.GenericAttributeProfile.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/base.h>

#include <algorithm>
#include <mutex>
#include <utility>
#include <vector>

namespace butane_windows {
namespace {
using namespace winrt::Windows::Devices::Bluetooth;
using namespace winrt::Windows::Devices::Bluetooth::GenericAttributeProfile;

GattDiscoveryStatus ConvertStatus(GattCommunicationStatus status) {
  switch (status) {
    case GattCommunicationStatus::Success:
      return GattDiscoveryStatus::kSuccess;
    case GattCommunicationStatus::Unreachable:
      return GattDiscoveryStatus::kUnreachable;
    case GattCommunicationStatus::ProtocolError:
      return GattDiscoveryStatus::kProtocolError;
    case GattCommunicationStatus::AccessDenied:
      return GattDiscoveryStatus::kAccessDenied;
  }
  return GattDiscoveryStatus::kUnreachable;
}

template <typename Result>
std::optional<uint8_t> ProtocolError(const Result& result) {
  const auto value = result.ProtocolError();
  return value ? std::optional<uint8_t>(
                     static_cast<uint8_t>(value.Value()))
               : std::nullopt;
}

std::string GuidString(const winrt::guid& value) {
  return winrt::to_string(winrt::to_hstring(value));
}

class WinrtNativeGattDiscovery final
    : public NativeGattDiscovery,
      public std::enable_shared_from_this<WinrtNativeGattDiscovery> {
 public:
  void Close() override;

  void GetServices(uint64_t address, ServicesCallback callback) override {
    auto state = std::make_shared<ServicesState>();
    state->owner = shared_from_this();
    state->address = address;
    state->callback = std::move(callback);
    if (!Register(state, service_requests_)) return;
    RunServices(std::move(state));
  }

  void GetCharacteristics(uint64_t address, std::string service_uuid,
                          CharacteristicsCallback callback) override {
    auto state = std::make_shared<CharacteristicsState>();
    state->owner = shared_from_this();
    state->address = address;
    state->service_uuid = std::move(service_uuid);
    state->callback = std::move(callback);
    if (!Register(state, characteristic_requests_)) return;
    OpenDevice(std::move(state));
  }

 private:
  struct ServicesState {
    std::weak_ptr<WinrtNativeGattDiscovery> owner;
    uint64_t address = 0;
    ServicesCallback callback;
    BluetoothLEDevice device{nullptr};
    GattDeviceServicesResult services{nullptr};

    void CancelAndClose() {
      callback = {};
      CloseServices(services);
      services = nullptr;
      CloseDevice(device);
      device = nullptr;
    }
  };

  struct CharacteristicsState {
    std::weak_ptr<WinrtNativeGattDiscovery> owner;
    uint64_t address = 0;
    std::string service_uuid;
    CharacteristicsCallback callback;
    BluetoothLEDevice device{nullptr};
    GattDeviceServicesResult services{nullptr};
    GattDeviceService selected{nullptr};
    GattCharacteristicsResult characteristics{nullptr};
    winrt::Windows::Foundation::Collections::IVectorView<GattCharacteristic>
        characteristic_values{nullptr};
    uint32_t characteristic_index = 0;
    GattCharacteristic characteristic{nullptr};
    GattDescriptorsResult descriptors{nullptr};
    std::optional<GattCharacteristicData> current;
    std::vector<GattCharacteristicData> data;

    void CancelAndClose() {
      callback = {};
      characteristic = nullptr;
      descriptors = nullptr;
      characteristic_values = nullptr;
      characteristics = nullptr;
      CloseServices(services);
      services = nullptr;
      CloseService(selected);
      selected = nullptr;
      CloseDevice(device);
      device = nullptr;
    }
  };

  static void CloseDevice(BluetoothLEDevice& device) {
    if (!device) return;
    try {
      device.Close();
    } catch (const winrt::hresult_error&) {
    }
  }

  static void CloseService(GattDeviceService& service) {
    if (!service) return;
    try {
      service.Close();
    } catch (const winrt::hresult_error&) {
    }
  }

  static void CloseServices(GattDeviceServicesResult& result) {
    if (!result) return;
    try {
      for (auto service : result.Services()) CloseService(service);
    } catch (const winrt::hresult_error&) {
    }
  }

  template <typename State>
  bool Register(const std::shared_ptr<State>& state,
                std::vector<std::weak_ptr<State>>& requests) {
    const std::scoped_lock lock(mutex_);
    if (closed_) {
      state->callback = {};
      return false;
    }
    requests.push_back(state);
    return true;
  }

  template <typename State>
  void Unregister(const std::shared_ptr<State>& state,
                  std::vector<std::weak_ptr<State>>& requests) {
    const std::scoped_lock lock(mutex_);
    requests.erase(
        std::remove_if(requests.begin(), requests.end(),
                       [&](const auto& weak) {
                         const auto value = weak.lock();
                         return !value || value == state;
                       }),
        requests.end());
  }

  bool IsClosed() const {
    const std::scoped_lock lock(mutex_);
    return closed_;
  }

  static bool IsRequestClosed(
      const std::weak_ptr<WinrtNativeGattDiscovery>& owner) {
    const auto value = owner.lock();
    return !value || value->IsClosed();
  }

  static void Complete(const std::shared_ptr<ServicesState>& state,
                       GattDiscoveryStatus status,
                       std::optional<uint8_t> protocol_error,
                       std::vector<GattServiceData> data = {}) {
    const auto owner = state->owner.lock();
    if (!owner || owner->IsClosed()) {
      state->CancelAndClose();
      return;
    }
    owner->Unregister(state, owner->service_requests_);
    CloseServices(state->services);
    state->services = nullptr;
    CloseDevice(state->device);
    state->device = nullptr;
    auto callback = std::move(state->callback);
    if (callback) {
      callback(status, protocol_error,
               status == GattDiscoveryStatus::kSuccess
                   ? std::move(data)
                   : std::vector<GattServiceData>{});
    }
  }

  static void Complete(
      const std::shared_ptr<CharacteristicsState>& state,
      GattDiscoveryStatus status, std::optional<uint8_t> protocol_error) {
    const auto owner = state->owner.lock();
    if (!owner || owner->IsClosed()) {
      state->CancelAndClose();
      return;
    }
    owner->Unregister(state, owner->characteristic_requests_);
    auto callback = std::move(state->callback);
    state->CancelAndClose();
    if (callback) {
      callback(status, protocol_error,
               status == GattDiscoveryStatus::kSuccess
                   ? std::move(state->data)
                   : std::vector<GattCharacteristicData>{});
    }
  }

  static winrt::fire_and_forget RunServices(
      std::shared_ptr<ServicesState> state) {
    try {
      state->device =
          co_await BluetoothLEDevice::FromBluetoothAddressAsync(state->address);
      if (IsRequestClosed(state->owner)) {
        state->CancelAndClose();
        co_return;
      }
      if (!state->device) {
        Complete(state, GattDiscoveryStatus::kUnreachable, std::nullopt);
        co_return;
      }
      state->services = co_await state->device.GetGattServicesAsync(
          BluetoothCacheMode::Uncached);
      if (IsRequestClosed(state->owner)) {
        state->CancelAndClose();
        co_return;
      }
      const auto status = ConvertStatus(state->services.Status());
      if (status != GattDiscoveryStatus::kSuccess) {
        Complete(state, status, ProtocolError(state->services));
        co_return;
      }
      std::vector<GattServiceData> services;
      for (const auto& service : state->services.Services()) {
        const auto uuid = NormalizeUuid(GuidString(service.Uuid()));
        if (uuid) services.push_back({*uuid, true});
      }
      Complete(state, GattDiscoveryStatus::kSuccess, std::nullopt,
               std::move(services));
    } catch (const winrt::hresult_error&) {
      if (!IsRequestClosed(state->owner)) {
        Complete(state, GattDiscoveryStatus::kUnreachable, std::nullopt);
      } else {
        state->CancelAndClose();
      }
    }
  }

  static winrt::fire_and_forget OpenDevice(
      std::shared_ptr<CharacteristicsState> state) {
    try {
      state->device = co_await BluetoothLEDevice::FromBluetoothAddressAsync(
          state->address);
      if (IsRequestClosed(state->owner)) {
        state->CancelAndClose();
        co_return;
      }
      if (!state->device) {
        Complete(state, GattDiscoveryStatus::kUnreachable, std::nullopt);
        co_return;
      }
      LoadServices(std::move(state));
    } catch (const winrt::hresult_error&) {
      if (!IsRequestClosed(state->owner)) {
        Complete(state, GattDiscoveryStatus::kUnreachable, std::nullopt);
      }
    }
  }

  static winrt::fire_and_forget LoadServices(
      std::shared_ptr<CharacteristicsState> state) {
    try {
      state->services = co_await state->device.GetGattServicesAsync(
          BluetoothCacheMode::Uncached);
      if (IsRequestClosed(state->owner)) {
        state->CancelAndClose();
        co_return;
      }
      const auto status = ConvertStatus(state->services.Status());
      if (status != GattDiscoveryStatus::kSuccess) {
        Complete(state, status, ProtocolError(state->services));
        co_return;
      }
      for (const auto& service : state->services.Services()) {
        const auto uuid = NormalizeUuid(GuidString(service.Uuid()));
        if (uuid && *uuid == state->service_uuid) {
          state->selected = service;
          break;
        }
      }
      if (!state->selected) {
        Complete(state, GattDiscoveryStatus::kSuccess, std::nullopt);
        co_return;
      }
      LoadCharacteristics(std::move(state));
    } catch (const winrt::hresult_error&) {
      Complete(state, GattDiscoveryStatus::kUnreachable, std::nullopt);
    }
  }

  static winrt::fire_and_forget LoadCharacteristics(
      std::shared_ptr<CharacteristicsState> state) {
    try {
      state->characteristics =
          co_await state->selected.GetCharacteristicsAsync(
          BluetoothCacheMode::Uncached);
      if (IsRequestClosed(state->owner)) {
        state->CancelAndClose();
        co_return;
      }
      const auto status = ConvertStatus(state->characteristics.Status());
      if (status != GattDiscoveryStatus::kSuccess) {
        Complete(state, status, ProtocolError(state->characteristics));
        co_return;
      }
      state->characteristic_values =
          state->characteristics.Characteristics();
      LoadNextDescriptors(std::move(state));
    } catch (const winrt::hresult_error&) {
      Complete(state, GattDiscoveryStatus::kUnreachable, std::nullopt);
    }
  }

  static winrt::fire_and_forget LoadNextDescriptors(
      std::shared_ptr<CharacteristicsState> state) {
    try {
      while (!state->current && state->characteristic_index <
                                  state->characteristic_values.Size()) {
        state->characteristic = state->characteristic_values.GetAt(
            state->characteristic_index++);
        const auto uuid = NormalizeUuid(
            GuidString(state->characteristic.Uuid()));
        if (!uuid) continue;
        state->current.emplace(GattCharacteristicData{
            *uuid,
            static_cast<uint32_t>(
                state->characteristic.CharacteristicProperties()),
            {}});
      }
      if (!state->current) {
        Complete(state, GattDiscoveryStatus::kSuccess, std::nullopt);
        co_return;
      }
      state->descriptors =
          co_await state->characteristic.GetDescriptorsAsync(
            BluetoothCacheMode::Uncached);
      if (IsRequestClosed(state->owner)) {
        state->CancelAndClose();
        co_return;
      }
      const auto status = ConvertStatus(state->descriptors.Status());
      if (status != GattDiscoveryStatus::kSuccess) {
        Complete(state, status, ProtocolError(state->descriptors));
        co_return;
      }
      const auto descriptor_values = state->descriptors.Descriptors();
      for (uint32_t descriptor_index = 0;
           descriptor_index < descriptor_values.Size(); ++descriptor_index) {
        const auto descriptor = descriptor_values.GetAt(descriptor_index);
        const auto descriptor_uuid =
            NormalizeUuid(GuidString(descriptor.Uuid()));
        if (descriptor_uuid) {
          state->current->descriptors.push_back({*descriptor_uuid});
        }
      }
      state->data.push_back(std::move(*state->current));
      state->current.reset();
      state->descriptors = nullptr;
      state->characteristic = nullptr;
      LoadNextDescriptors(std::move(state));
    } catch (const winrt::hresult_error&) {
      Complete(state, GattDiscoveryStatus::kUnreachable, std::nullopt);
    }
  }

  mutable std::mutex mutex_;
  bool closed_ = false;
  std::vector<std::weak_ptr<ServicesState>> service_requests_;
  std::vector<std::weak_ptr<CharacteristicsState>> characteristic_requests_;
};

void WinrtNativeGattDiscovery::Close() {
  std::vector<std::shared_ptr<ServicesState>> services;
  std::vector<std::shared_ptr<CharacteristicsState>> characteristics;
  {
    const std::scoped_lock lock(mutex_);
    if (closed_) return;
    closed_ = true;
    for (const auto& weak : service_requests_) {
      if (auto state = weak.lock()) services.push_back(std::move(state));
    }
    for (const auto& weak : characteristic_requests_) {
      if (auto state = weak.lock()) {
        characteristics.push_back(std::move(state));
      }
    }
    service_requests_.clear();
    characteristic_requests_.clear();
  }
  for (const auto& state : services) state->CancelAndClose();
  for (const auto& state : characteristics) state->CancelAndClose();
}

template <typename T>
void Filter(std::vector<T>& values, const std::vector<std::string>& uuids) {
  if (uuids.empty()) return;
  values.erase(
      std::remove_if(values.begin(), values.end(), [&](const auto& item) {
        return std::find(uuids.begin(), uuids.end(), item.uuid) == uuids.end();
      }),
      values.end());
}
}  // namespace

struct WindowsGattDiscoveryBackend::CallbackState {
  std::atomic<bool> closed{false};
  GattDiscoveryCache cache;
};

std::shared_ptr<NativeGattDiscovery> CreateNativeGattDiscovery() {
  return std::make_shared<WinrtNativeGattDiscovery>();
}

WindowsGattDiscoveryBackend::WindowsGattDiscoveryBackend(
    std::shared_ptr<NativeGattDiscovery> native)
    : native_(std::move(native)), state_(std::make_shared<CallbackState>()) {}

WindowsGattDiscoveryBackend::~WindowsGattDiscoveryBackend() {
  state_->closed.store(true);
  state_.reset();
  auto native = std::move(native_);
  if (native) native->Close();
}

void WindowsGattDiscoveryBackend::DiscoverServices(
    uint64_t address, std::vector<std::string> uuids, bool explicit_empty,
    Completion completion) {
  if (explicit_empty) {
    state_->cache.ReplaceServices(address, {});
    completion(std::nullopt);
    return;
  }
  std::weak_ptr<CallbackState> weak = state_;
  native_->GetServices(
      address, [weak, address, uuids = std::move(uuids),
                completion = std::move(completion)](
                   GattDiscoveryStatus status, std::optional<uint8_t> error,
                   std::vector<GattServiceData> values) mutable {
        const auto state = weak.lock();
        if (!state || state->closed.load()) return;
        if (status != GattDiscoveryStatus::kSuccess) {
          completion(GattDiscoveryError(status, error));
          return;
        }
        Filter(values, uuids);
        state->cache.ReplaceServices(address, std::move(values));
        completion(std::nullopt);
      });
}

ErrorOr<std::vector<GattServiceData>> WindowsGattDiscoveryBackend::Services(
    uint64_t address) const {
  return state_->cache.Services(address);
}

void WindowsGattDiscoveryBackend::DiscoverCharacteristics(
    uint64_t address, std::string service_uuid,
    std::vector<std::string> uuids, bool explicit_empty,
    Completion completion) {
  if (!state_->cache.HasService(address, service_uuid)) {
    completion(FlutterError("not-found",
                            "GATT discovery data was not found."));
    return;
  }
  if (explicit_empty) {
    state_->cache.ReplaceCharacteristics(address, std::move(service_uuid), {});
    completion(std::nullopt);
    return;
  }
  std::weak_ptr<CallbackState> weak = state_;
  native_->GetCharacteristics(
      address, service_uuid,
      [weak, address, service_uuid = std::move(service_uuid),
       uuids = std::move(uuids), completion = std::move(completion)](
          GattDiscoveryStatus status, std::optional<uint8_t> error,
          std::vector<GattCharacteristicData> values) mutable {
        const auto state = weak.lock();
        if (!state || state->closed.load()) return;
        if (status != GattDiscoveryStatus::kSuccess) {
          completion(GattDiscoveryError(status, error));
          return;
        }
        Filter(values, uuids);
        state->cache.ReplaceCharacteristics(address, std::move(service_uuid),
                                            std::move(values));
        completion(std::nullopt);
      });
}

ErrorOr<std::vector<GattCharacteristicData>>
WindowsGattDiscoveryBackend::Characteristics(
    uint64_t address, std::string_view service_uuid) const {
  return state_->cache.Characteristics(address, service_uuid);
}

}  // namespace butane_windows
