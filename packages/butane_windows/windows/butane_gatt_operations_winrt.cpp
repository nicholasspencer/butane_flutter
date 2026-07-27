#include "butane_gatt_operations_winrt.h"

#include <winrt/Windows.Devices.Bluetooth.GenericAttributeProfile.h>
#include <winrt/Windows.Devices.Bluetooth.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Storage.Streams.h>
#include <winrt/base.h>

#include <atomic>
#include <map>
#include <mutex>
#include <tuple>
#include <utility>

namespace butane_windows {
namespace {
using namespace winrt::Windows::Devices::Bluetooth;
using namespace winrt::Windows::Devices::Bluetooth::GenericAttributeProfile;
using namespace winrt::Windows::Storage::Streams;

GattOperationStatus ConvertStatus(GattCommunicationStatus status) {
  switch (status) {
    case GattCommunicationStatus::Success:
      return GattOperationStatus::kSuccess;
    case GattCommunicationStatus::Unreachable:
      return GattOperationStatus::kUnreachable;
    case GattCommunicationStatus::ProtocolError:
      return GattOperationStatus::kProtocolError;
    case GattCommunicationStatus::AccessDenied:
      return GattOperationStatus::kAccessDenied;
  }
  return GattOperationStatus::kUnreachable;
}

template <typename Result>
std::optional<uint8_t> ProtocolError(const Result& result) {
  const auto error = result.ProtocolError();
  return error ? std::optional<uint8_t>(
                     static_cast<uint8_t>(error.Value()))
               : std::nullopt;
}

IBuffer BufferFromBytes(const std::vector<uint8_t>& value) {
  DataWriter writer;
  writer.WriteBytes(value);
  return writer.DetachBuffer();
}

std::vector<uint8_t> BytesFromBuffer(const IBuffer& buffer) {
  DataReader reader = DataReader::FromBuffer(buffer);
  std::vector<uint8_t> value(reader.UnconsumedBufferLength());
  if (!value.empty()) reader.ReadBytes(value);
  return value;
}

winrt::guid ParseGuid(const std::string& value) {
  winrt::guid guid{};
  const auto text = winrt::to_hstring(value);
  winrt::check_hresult(
      IIDFromString(text.c_str(), reinterpret_cast<GUID*>(&guid)));
  return guid;
}

class WinrtNativeGattOperations final
    : public NativeGattOperations,
      public std::enable_shared_from_this<WinrtNativeGattOperations> {
 public:
  void WriteCharacteristic(
      uint64_t address, std::string service_uuid,
      std::string characteristic_uuid, std::vector<uint8_t> value,
      bool without_response, Completion completion) override {
    RunCharacteristicWrite(shared_from_this(), address,
                           std::move(service_uuid),
                           std::move(characteristic_uuid),
                           std::move(value), without_response,
                           std::move(completion));
  }

  void ObserveCharacteristic(
      bool observe, uint64_t address, std::string service_uuid,
      std::string characteristic_uuid, ValueCallback on_value,
      Completion completion) override {
    const Key key{address, service_uuid, characteristic_uuid};
    if (!observe) {
      std::optional<Subscription> subscription;
      {
        const std::scoped_lock lock(mutex_);
        if (closed_) return;
        const auto found = subscriptions_.find(key);
        if (found == subscriptions_.end()) {
          completion(GattOperationStatus::kSuccess, std::nullopt);
          return;
        }
        subscription.emplace(std::move(found->second));
        subscriptions_.erase(found);
      }
      DisableSubscription(shared_from_this(), std::move(*subscription),
                          std::move(completion));
      return;
    }
    RunObserve(shared_from_this(), key, std::move(on_value),
               std::move(completion));
  }

  void WriteDescriptor(
      uint64_t address, std::string service_uuid,
      std::string characteristic_uuid, std::string descriptor_uuid,
      std::vector<uint8_t> value, Completion completion) override {
    RunDescriptorWrite(shared_from_this(), address, std::move(service_uuid),
                       std::move(characteristic_uuid),
                       std::move(descriptor_uuid), std::move(value),
                       std::move(completion));
  }

  void ReadMaxPduSize(
      uint64_t address, MtuCompletion completion) override {
    RunReadMtu(shared_from_this(), address, std::move(completion));
  }

  void Close() override {
    std::map<Key, Subscription> subscriptions;
    {
      const std::scoped_lock lock(mutex_);
      if (closed_) return;
      closed_ = true;
      subscriptions.swap(subscriptions_);
    }
    for (auto& entry : subscriptions) RevokeAndClose(entry.second);
  }

 private:
  using Key = std::tuple<uint64_t, std::string, std::string>;
  struct Resolved {
    BluetoothLEDevice device{nullptr};
    GattDeviceService service{nullptr};
    GattCharacteristic characteristic{nullptr};
    GattOperationStatus status = GattOperationStatus::kNotFound;
    std::optional<uint8_t> protocol;
  };
  struct Subscription {
    BluetoothLEDevice device{nullptr};
    GattDeviceService service{nullptr};
    GattCharacteristic characteristic{nullptr};
    winrt::event_token token{};
    ValueCallback callback;
  };

  bool IsClosed() const {
    const std::scoped_lock lock(mutex_);
    return closed_;
  }

  static void CloseResolved(Resolved& value) {
    if (value.service) {
      try {
        value.service.Close();
      } catch (const winrt::hresult_error&) {
      }
    }
    if (value.device) {
      try {
        value.device.Close();
      } catch (const winrt::hresult_error&) {
      }
    }
  }

  static void RevokeAndClose(Subscription& value) {
    value.callback = {};
    if (value.characteristic) {
      try {
        value.characteristic.ValueChanged(value.token);
      } catch (const winrt::hresult_error&) {
      }
    }
    if (value.service) {
      try {
        value.service.Close();
      } catch (const winrt::hresult_error&) {
      }
    }
    if (value.device) {
      try {
        value.device.Close();
      } catch (const winrt::hresult_error&) {
      }
    }
  }

  static void CompleteError(const Completion& completion,
                            GattOperationStatus status,
                            std::optional<uint8_t> protocol = std::nullopt) {
    if (completion) completion(status, protocol);
  }

  template <typename CompletionType>
  static void Catch(const std::shared_ptr<WinrtNativeGattOperations>& owner,
                    CompletionType& completion) {
    if (owner->IsClosed() || !completion) return;
    try {
      throw;
    } catch (const winrt::hresult_access_denied&) {
      completion(GattOperationStatus::kAccessDenied, std::nullopt);
    } catch (const winrt::hresult_error&) {
      completion(GattOperationStatus::kUnreachable, std::nullopt);
    }
  }

  static winrt::Windows::Foundation::IAsyncAction
  Resolve(std::shared_ptr<WinrtNativeGattOperations> owner, uint64_t address,
          const std::string& service_uuid,
          const std::string& characteristic_uuid, Resolved& resolved) {
    resolved.device =
        co_await BluetoothLEDevice::FromBluetoothAddressAsync(address);
    if (owner->IsClosed() || !resolved.device) co_return;
    auto services = co_await resolved.device.GetGattServicesForUuidAsync(
        ParseGuid(service_uuid),
        BluetoothCacheMode::Uncached);
    if (owner->IsClosed() ||
        services.Status() != GattCommunicationStatus::Success) {
      resolved.status = ConvertStatus(services.Status());
      resolved.protocol = ProtocolError(services);
      co_return;
    }
    if (services.Services().Size() != 1) {
      co_return;
    }
    resolved.service = services.Services().GetAt(0);
    auto characteristics =
        co_await resolved.service.GetCharacteristicsForUuidAsync(
            ParseGuid(characteristic_uuid),
            BluetoothCacheMode::Uncached);
    if (owner->IsClosed() ||
        characteristics.Status() != GattCommunicationStatus::Success) {
      resolved.status = ConvertStatus(characteristics.Status());
      resolved.protocol = ProtocolError(characteristics);
      resolved.service = nullptr;
      co_return;
    }
    if (characteristics.Characteristics().Size() != 1) {
      resolved.service = nullptr;
      co_return;
    }
    resolved.characteristic = characteristics.Characteristics().GetAt(0);
    resolved.status = GattOperationStatus::kSuccess;
    co_return;
  }

  static winrt::fire_and_forget RunCharacteristicWrite(
      std::shared_ptr<WinrtNativeGattOperations> owner, uint64_t address,
      std::string service_uuid, std::string characteristic_uuid,
      std::vector<uint8_t> value, bool without_response,
      Completion completion) {
    Resolved resolved;
    try {
      co_await Resolve(owner, address, service_uuid,
                       characteristic_uuid, resolved);
      if (owner->IsClosed()) co_return;
      if (!resolved.characteristic) {
        CloseResolved(resolved);
        CompleteError(completion, resolved.status, resolved.protocol);
        co_return;
      }
      auto result = co_await resolved.characteristic.WriteValueWithResultAsync(
          BufferFromBytes(value),
          without_response ? GattWriteOption::WriteWithoutResponse
                           : GattWriteOption::WriteWithResponse);
      if (owner->IsClosed()) {
        CloseResolved(resolved);
        co_return;
      }
      const auto status = ConvertStatus(result.Status());
      const auto protocol = ProtocolError(result);
      CloseResolved(resolved);
      CompleteError(completion, status, protocol);
    } catch (...) {
      CloseResolved(resolved);
      Catch(owner, completion);
    }
  }

  static winrt::fire_and_forget RunDescriptorWrite(
      std::shared_ptr<WinrtNativeGattOperations> owner, uint64_t address,
      std::string service_uuid, std::string characteristic_uuid,
      std::string descriptor_uuid, std::vector<uint8_t> value,
      Completion completion) {
    Resolved resolved;
    try {
      co_await Resolve(owner, address, service_uuid,
                       characteristic_uuid, resolved);
      if (owner->IsClosed()) co_return;
      if (!resolved.characteristic) {
        CloseResolved(resolved);
        CompleteError(completion, resolved.status, resolved.protocol);
        co_return;
      }
      auto descriptors =
          co_await resolved.characteristic.GetDescriptorsForUuidAsync(
              ParseGuid(descriptor_uuid),
              BluetoothCacheMode::Uncached);
      if (owner->IsClosed()) {
        CloseResolved(resolved);
        co_return;
      }
      if (descriptors.Status() != GattCommunicationStatus::Success) {
        const auto status = ConvertStatus(descriptors.Status());
        const auto protocol = ProtocolError(descriptors);
        CloseResolved(resolved);
        CompleteError(completion, status, protocol);
        co_return;
      }
      if (descriptors.Descriptors().Size() != 1) {
        CloseResolved(resolved);
        CompleteError(completion, resolved.status, resolved.protocol);
        co_return;
      }
      auto result = co_await descriptors.Descriptors().GetAt(0).WriteValueWithResultAsync(
          BufferFromBytes(value));
      if (owner->IsClosed()) {
        CloseResolved(resolved);
        co_return;
      }
      const auto status = ConvertStatus(result.Status());
      const auto protocol = ProtocolError(result);
      CloseResolved(resolved);
      CompleteError(completion, status, protocol);
    } catch (...) {
      CloseResolved(resolved);
      Catch(owner, completion);
    }
  }

  static winrt::fire_and_forget RunObserve(
      std::shared_ptr<WinrtNativeGattOperations> owner, Key key,
      ValueCallback on_value, Completion completion) {
    Resolved resolved;
    try {
      co_await Resolve(owner, std::get<0>(key), std::get<1>(key),
                       std::get<2>(key), resolved);
      if (owner->IsClosed()) co_return;
      if (!resolved.characteristic) {
        CloseResolved(resolved);
        CompleteError(completion, GattOperationStatus::kNotFound);
        co_return;
      }
      const auto properties = resolved.characteristic.CharacteristicProperties();
      GattClientCharacteristicConfigurationDescriptorValue configuration;
      if ((properties & GattCharacteristicProperties::Notify) ==
          GattCharacteristicProperties::Notify) {
        configuration =
            GattClientCharacteristicConfigurationDescriptorValue::Notify;
      } else if ((properties & GattCharacteristicProperties::Indicate) ==
                 GattCharacteristicProperties::Indicate) {
        configuration =
            GattClientCharacteristicConfigurationDescriptorValue::Indicate;
      } else {
        CloseResolved(resolved);
        CompleteError(completion, GattOperationStatus::kUnsupported);
        co_return;
      }
      Subscription subscription;
      subscription.device = resolved.device;
      subscription.service = resolved.service;
      subscription.characteristic = resolved.characteristic;
      subscription.callback = std::move(on_value);
      std::weak_ptr<WinrtNativeGattOperations> weak_owner = owner;
      subscription.token = subscription.characteristic.ValueChanged(
          [weak_owner, key](const GattCharacteristic&,
                            const GattValueChangedEventArgs& args) {
            const auto strong = weak_owner.lock();
            if (!strong) return;
            ValueCallback callback;
            {
              const std::scoped_lock lock(strong->mutex_);
              if (strong->closed_) return;
              const auto found = strong->subscriptions_.find(key);
              if (found == strong->subscriptions_.end()) return;
              callback = found->second.callback;
            }
            if (callback) callback(BytesFromBuffer(args.CharacteristicValue()));
          });
      auto result = co_await subscription.characteristic
                        .WriteClientCharacteristicConfigurationDescriptorWithResultAsync(
                            configuration);
      if (owner->IsClosed()) {
        RevokeAndClose(subscription);
        co_return;
      }
      const auto status = ConvertStatus(result.Status());
      if (status != GattOperationStatus::kSuccess) {
        const auto protocol = ProtocolError(result);
        RevokeAndClose(subscription);
        CompleteError(completion, status, protocol);
        co_return;
      }
      {
        const std::scoped_lock lock(owner->mutex_);
        if (owner->closed_) {
          RevokeAndClose(subscription);
          co_return;
        }
        auto old = owner->subscriptions_.find(key);
        if (old != owner->subscriptions_.end()) {
          RevokeAndClose(old->second);
          owner->subscriptions_.erase(old);
        }
        owner->subscriptions_.emplace(std::move(key), std::move(subscription));
      }
      CompleteError(completion, GattOperationStatus::kSuccess);
    } catch (...) {
      CloseResolved(resolved);
      Catch(owner, completion);
    }
  }

  static winrt::fire_and_forget DisableSubscription(
      std::shared_ptr<WinrtNativeGattOperations> owner,
      Subscription subscription, Completion completion) {
    try {
      auto result = co_await subscription.characteristic
                        .WriteClientCharacteristicConfigurationDescriptorWithResultAsync(
                            GattClientCharacteristicConfigurationDescriptorValue::None);
      if (owner->IsClosed()) {
        RevokeAndClose(subscription);
        co_return;
      }
      const auto status = ConvertStatus(result.Status());
      const auto protocol = ProtocolError(result);
      RevokeAndClose(subscription);
      CompleteError(completion, status, protocol);
    } catch (...) {
      RevokeAndClose(subscription);
      Catch(owner, completion);
    }
  }

  static winrt::fire_and_forget RunReadMtu(
      std::shared_ptr<WinrtNativeGattOperations> owner, uint64_t address,
      MtuCompletion completion) {
    BluetoothLEDevice device{nullptr};
    GattSession session{nullptr};
    try {
      device =
          co_await BluetoothLEDevice::FromBluetoothAddressAsync(address);
      if (owner->IsClosed()) co_return;
      if (!device) {
        completion(GattOperationStatus::kUnreachable, std::nullopt, 0);
        co_return;
      }
      session = co_await GattSession::FromDeviceIdAsync(
          device.BluetoothDeviceId());
      if (owner->IsClosed()) co_return;
      if (!session) {
        device.Close();
        completion(GattOperationStatus::kUnreachable, std::nullopt, 0);
        co_return;
      }
      const auto mtu = session.MaxPduSize();
      session.Close();
      device.Close();
      completion(GattOperationStatus::kSuccess, std::nullopt, mtu);
    } catch (const winrt::hresult_access_denied&) {
      if (!owner->IsClosed())
        completion(GattOperationStatus::kAccessDenied, std::nullopt, 0);
    } catch (const winrt::hresult_error&) {
      if (!owner->IsClosed())
        completion(GattOperationStatus::kUnreachable, std::nullopt, 0);
    }
  }

  mutable std::mutex mutex_;
  bool closed_ = false;
  std::map<Key, Subscription> subscriptions_;
};
}  // namespace

std::shared_ptr<NativeGattOperations> CreateNativeGattOperations() {
  return std::make_shared<WinrtNativeGattOperations>();
}

struct WindowsGattOperationsBackend::CallbackState {
  std::atomic<bool> closed{false};
};

WindowsGattOperationsBackend::WindowsGattOperationsBackend(
    std::shared_ptr<NativeGattOperations> native)
    : native_(std::move(native)), state_(std::make_shared<CallbackState>()) {}

WindowsGattOperationsBackend::~WindowsGattOperationsBackend() { Close(); }

void WindowsGattOperationsBackend::WriteCharacteristic(
    uint64_t address, std::string service_uuid,
    std::string characteristic_uuid, std::vector<uint8_t> value,
    bool without_response, Completion completion) {
  std::weak_ptr<CallbackState> state = state_;
  native_->WriteCharacteristic(
      address, std::move(service_uuid), std::move(characteristic_uuid),
      std::move(value), without_response,
      [state, completion = std::move(completion)](
          GattOperationStatus status, std::optional<uint8_t> protocol) {
        const auto strong = state.lock();
        if (!strong || strong->closed) return;
        completion(status == GattOperationStatus::kSuccess
                       ? std::nullopt
                       : std::optional<FlutterError>(
                             GattOperationError("writeCharacteristic", status,
                                                protocol)));
      });
}

void WindowsGattOperationsBackend::ObserveCharacteristic(
    bool observe, uint64_t address, std::string service_uuid,
    std::string characteristic_uuid, ValueCallback on_value,
    Completion completion) {
  std::weak_ptr<CallbackState> state = state_;
  const auto event_address = address;
  const auto event_service = service_uuid;
  const auto event_characteristic = characteristic_uuid;
  native_->ObserveCharacteristic(
      observe, address, std::move(service_uuid),
      std::move(characteristic_uuid),
      [state, on_value = std::move(on_value), event_address, event_service,
       event_characteristic](std::vector<uint8_t> value) mutable {
        const auto strong = state.lock();
        if (!strong || strong->closed) return;
        on_value({event_address, event_service, event_characteristic,
                  std::move(value)});
      },
      [state, completion = std::move(completion)](
          GattOperationStatus status, std::optional<uint8_t> protocol) {
        const auto strong = state.lock();
        if (!strong || strong->closed) return;
        completion(status == GattOperationStatus::kSuccess
                       ? std::nullopt
                       : std::optional<FlutterError>(
                             GattOperationError("observeCharacteristic", status,
                                                protocol)));
      });
}

void WindowsGattOperationsBackend::WriteDescriptor(
    uint64_t address, std::string service_uuid,
    std::string characteristic_uuid, std::string descriptor_uuid,
    std::vector<uint8_t> value, Completion completion) {
  std::weak_ptr<CallbackState> state = state_;
  native_->WriteDescriptor(
      address, std::move(service_uuid), std::move(characteristic_uuid),
      std::move(descriptor_uuid), std::move(value),
      [state, completion = std::move(completion)](
          GattOperationStatus status, std::optional<uint8_t> protocol) {
        const auto strong = state.lock();
        if (!strong || strong->closed) return;
        completion(status == GattOperationStatus::kSuccess
                       ? std::nullopt
                       : std::optional<FlutterError>(
                             GattOperationError("writeDescriptor", status,
                                                protocol)));
      });
}

void WindowsGattOperationsBackend::RequestMtu(
    uint64_t address, int64_t, MtuCompletion completion) {
  std::weak_ptr<CallbackState> state = state_;
  native_->ReadMaxPduSize(
      address,
      [state, completion = std::move(completion)](
          GattOperationStatus status, std::optional<uint8_t> protocol,
          uint16_t mtu) {
        const auto strong = state.lock();
        if (!strong || strong->closed) return;
        if (status == GattOperationStatus::kSuccess) {
          completion(static_cast<int64_t>(mtu));
        } else {
          completion(GattOperationError("requestMtu", status, protocol));
        }
      });
}

void WindowsGattOperationsBackend::Close() {
  if (!state_ || state_->closed.exchange(true)) return;
  if (native_) native_->Close();
}

}  // namespace butane_windows
