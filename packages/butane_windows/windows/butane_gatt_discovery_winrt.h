#ifndef PACKAGES_BUTANE_WINDOWS_WINDOWS_BUTANE_GATT_DISCOVERY_WINRT_H_
#define PACKAGES_BUTANE_WINDOWS_WINDOWS_BUTANE_GATT_DISCOVERY_WINRT_H_

#include "butane_gatt_discovery.h"

#include <atomic>
#include <memory>

namespace butane_windows {

class NativeGattDiscovery {
 public:
  using ServicesCallback = std::function<void(
      GattDiscoveryStatus, std::optional<uint8_t>,
      std::vector<GattServiceData>)>;
  using CharacteristicsCallback = std::function<void(
      GattDiscoveryStatus, std::optional<uint8_t>,
      std::vector<GattCharacteristicData>)>;
  virtual ~NativeGattDiscovery() = default;
  virtual void Close() = 0;
  virtual void GetServices(uint64_t address, ServicesCallback callback) = 0;
  virtual void GetCharacteristics(
      uint64_t address, std::string service_uuid,
      CharacteristicsCallback callback) = 0;
};

std::shared_ptr<NativeGattDiscovery> CreateNativeGattDiscovery();

class WindowsGattDiscoveryBackend final : public GattDiscoveryBackend {
 public:
  explicit WindowsGattDiscoveryBackend(
      std::shared_ptr<NativeGattDiscovery> native =
          CreateNativeGattDiscovery());
  ~WindowsGattDiscoveryBackend() override;
  void DiscoverServices(uint64_t address,
                        std::vector<std::string> service_uuids,
                        bool explicit_empty,
                        Completion completion) override;
  ErrorOr<std::vector<GattServiceData>> Services(
      uint64_t address) const override;
  void DiscoverCharacteristics(
      uint64_t address, std::string service_uuid,
      std::vector<std::string> characteristic_uuids,
      bool explicit_empty, Completion completion) override;
  ErrorOr<std::vector<GattCharacteristicData>> Characteristics(
      uint64_t address, std::string_view service_uuid) const override;

 private:
  struct CallbackState;
  std::shared_ptr<NativeGattDiscovery> native_;
  std::shared_ptr<CallbackState> state_;
};

}  // namespace butane_windows
#endif
