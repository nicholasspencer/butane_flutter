#include "butane_gatt_discovery_winrt.h"

#include "butane_conversions.h"

#include <winrt/Windows.Devices.Bluetooth.h>
#include <winrt/Windows.Devices.Bluetooth.GenericAttributeProfile.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/base.h>

#include <algorithm>

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
  void GetServices(uint64_t address, ServicesCallback callback) override {
    RunServices(shared_from_this(), address, std::move(callback));
  }

  void GetCharacteristics(uint64_t address, std::string service_uuid,
                          CharacteristicsCallback callback) override {
    auto state = std::make_shared<CharacteristicsState>();
    state->owner = shared_from_this();
    state->address = address;
    state->service_uuid = std::move(service_uuid);
    state->callback = std::move(callback);
    OpenDevice(std::move(state));
  }

 private:
  struct CharacteristicsState {
    std::shared_ptr<WinrtNativeGattDiscovery> owner;
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
  };

  static void Complete(
      const std::shared_ptr<CharacteristicsState>& state,
      GattDiscoveryStatus status, std::optional<uint8_t> protocol_error) {
    state->characteristic = nullptr;
    state->descriptors = nullptr;
    state->characteristic_values = nullptr;
    state->characteristics = nullptr;
    state->selected = nullptr;
    state->services = nullptr;
    state->device = nullptr;
    auto callback = std::move(state->callback);
    callback(status, protocol_error,
             status == GattDiscoveryStatus::kSuccess
                 ? std::move(state->data)
                 : std::vector<GattCharacteristicData>{});
  }

  static winrt::fire_and_forget RunServices(
      std::shared_ptr<WinrtNativeGattDiscovery> self, uint64_t address,
      ServicesCallback callback) {
    (void)self;
    try {
      auto device = co_await BluetoothLEDevice::FromBluetoothAddressAsync(address);
      if (!device) {
        callback(GattDiscoveryStatus::kUnreachable, std::nullopt, {});
        co_return;
      }
      auto result =
          co_await device.GetGattServicesAsync(BluetoothCacheMode::Uncached);
      const auto status = ConvertStatus(result.Status());
      if (status != GattDiscoveryStatus::kSuccess) {
        callback(status, ProtocolError(result), {});
        co_return;
      }
      std::vector<GattServiceData> services;
      for (const auto& service : result.Services()) {
        const auto uuid = NormalizeUuid(GuidString(service.Uuid()));
        if (uuid) services.push_back({*uuid, true});
      }
      result = nullptr;
      device = nullptr;
      callback(GattDiscoveryStatus::kSuccess, std::nullopt,
               std::move(services));
    } catch (const winrt::hresult_error&) {
      callback(GattDiscoveryStatus::kUnreachable, std::nullopt, {});
    }
  }

  static winrt::fire_and_forget OpenDevice(
      std::shared_ptr<CharacteristicsState> state) {
    try {
      state->device = co_await BluetoothLEDevice::FromBluetoothAddressAsync(
          state->address);
      if (!state->device) {
        Complete(state, GattDiscoveryStatus::kUnreachable, std::nullopt);
        co_return;
      }
      LoadServices(std::move(state));
    } catch (const winrt::hresult_error&) {
      Complete(state, GattDiscoveryStatus::kUnreachable, std::nullopt);
    }
  }

  static winrt::fire_and_forget LoadServices(
      std::shared_ptr<CharacteristicsState> state) {
    try {
      state->services = co_await state->device.GetGattServicesAsync(
          BluetoothCacheMode::Uncached);
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
};

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

std::shared_ptr<NativeGattDiscovery> CreateNativeGattDiscovery() {
  return std::make_shared<WinrtNativeGattDiscovery>();
}

WindowsGattDiscoveryBackend::WindowsGattDiscoveryBackend(
    std::shared_ptr<NativeGattDiscovery> native)
    : native_(std::move(native)) {}

void WindowsGattDiscoveryBackend::DiscoverServices(
    uint64_t address, std::vector<std::string> uuids, bool explicit_empty,
    Completion completion) {
  if (explicit_empty) {
    cache_.ReplaceServices(address, {});
    completion(std::nullopt);
    return;
  }
  native_->GetServices(
      address, [this, address, uuids = std::move(uuids),
                completion = std::move(completion)](
                   GattDiscoveryStatus status, std::optional<uint8_t> error,
                   std::vector<GattServiceData> values) mutable {
        if (status != GattDiscoveryStatus::kSuccess) {
          completion(GattDiscoveryError(status, error));
          return;
        }
        Filter(values, uuids);
        cache_.ReplaceServices(address, std::move(values));
        completion(std::nullopt);
      });
}

ErrorOr<std::vector<GattServiceData>> WindowsGattDiscoveryBackend::Services(
    uint64_t address) const {
  return cache_.Services(address);
}

void WindowsGattDiscoveryBackend::DiscoverCharacteristics(
    uint64_t address, std::string service_uuid,
    std::vector<std::string> uuids, bool explicit_empty,
    Completion completion) {
  if (!cache_.HasService(address, service_uuid)) {
    completion(FlutterError("not-found",
                            "GATT discovery data was not found."));
    return;
  }
  if (explicit_empty) {
    cache_.ReplaceCharacteristics(address, std::move(service_uuid), {});
    completion(std::nullopt);
    return;
  }
  native_->GetCharacteristics(
      address, service_uuid,
      [this, address, service_uuid = std::move(service_uuid),
       uuids = std::move(uuids), completion = std::move(completion)](
          GattDiscoveryStatus status, std::optional<uint8_t> error,
          std::vector<GattCharacteristicData> values) mutable {
        if (status != GattDiscoveryStatus::kSuccess) {
          completion(GattDiscoveryError(status, error));
          return;
        }
        Filter(values, uuids);
        cache_.ReplaceCharacteristics(address, std::move(service_uuid),
                                      std::move(values));
        completion(std::nullopt);
      });
}

ErrorOr<std::vector<GattCharacteristicData>>
WindowsGattDiscoveryBackend::Characteristics(
    uint64_t address, std::string_view service_uuid) const {
  return cache_.Characteristics(address, service_uuid);
}

}  // namespace butane_windows
