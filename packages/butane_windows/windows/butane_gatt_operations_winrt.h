#ifndef PACKAGES_BUTANE_WINDOWS_WINDOWS_BUTANE_GATT_OPERATIONS_WINRT_H_
#define PACKAGES_BUTANE_WINDOWS_WINDOWS_BUTANE_GATT_OPERATIONS_WINRT_H_

#include "butane_gatt_operations.h"

#include <memory>

namespace butane_windows {

class NativeGattOperations {
 public:
  using Completion = std::function<void(
      GattOperationStatus, std::optional<uint8_t>)>;
  using ValueCallback = std::function<void(std::vector<uint8_t>)>;
  using MtuCompletion = std::function<void(
      GattOperationStatus, std::optional<uint8_t>, uint16_t)>;
  virtual ~NativeGattOperations() = default;
  virtual void WriteCharacteristic(
      uint64_t address, std::string service_uuid,
      std::string characteristic_uuid, std::vector<uint8_t> value,
      bool without_response, Completion completion) = 0;
  virtual void ObserveCharacteristic(
      bool observe, uint64_t address, std::string service_uuid,
      std::string characteristic_uuid, ValueCallback on_value,
      Completion completion) = 0;
  virtual void WriteDescriptor(
      uint64_t address, std::string service_uuid,
      std::string characteristic_uuid, std::string descriptor_uuid,
      std::vector<uint8_t> value, Completion completion) = 0;
  virtual void ReadMaxPduSize(
      uint64_t address, MtuCompletion completion) = 0;
  virtual void Close() = 0;
};

std::shared_ptr<NativeGattOperations> CreateNativeGattOperations();

class WindowsGattOperationsBackend final : public GattOperationsBackend {
 public:
  explicit WindowsGattOperationsBackend(
      std::shared_ptr<NativeGattOperations> native =
          CreateNativeGattOperations());
  ~WindowsGattOperationsBackend() override;
  void WriteCharacteristic(
      uint64_t address, std::string service_uuid,
      std::string characteristic_uuid, std::vector<uint8_t> value,
      bool without_response, Completion completion) override;
  void ObserveCharacteristic(
      bool observe, uint64_t address, std::string service_uuid,
      std::string characteristic_uuid, ValueCallback on_value,
      Completion completion) override;
  void WriteDescriptor(
      uint64_t address, std::string service_uuid,
      std::string characteristic_uuid, std::string descriptor_uuid,
      std::vector<uint8_t> value, Completion completion) override;
  void RequestMtu(
      uint64_t address, int64_t requested_mtu,
      MtuCompletion completion) override;
  void Close() override;

 private:
  struct CallbackState;
  std::shared_ptr<NativeGattOperations> native_;
  std::shared_ptr<CallbackState> state_;
};

}  // namespace butane_windows
#endif
