#include "butane_central_winrt.h"
#include <windows.h>
#define CharacteristicProperty ButaneConversionCharacteristicProperty
#include "butane_conversions.h"
#undef CharacteristicProperty
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Storage.Streams.h>
#include <iomanip>
#include <sstream>
namespace butane_windows {
namespace {
using namespace winrt::Windows::Devices::Bluetooth;
using namespace winrt::Windows::Devices::Bluetooth::Advertisement;
using namespace winrt::Windows::Devices::Radios;
using namespace winrt::Windows::Storage::Streams;
std::vector<uint8_t> CopyBuffer(const IBuffer& buffer) {
  std::vector<uint8_t> bytes(buffer.Length());
  if (!bytes.empty()) DataReader::FromBuffer(buffer).ReadBytes(bytes);
  return bytes;
}
std::string HexUuid(const uint8_t* bytes, size_t count) {
  std::ostringstream out;
  out << std::hex << std::setfill('0');
  if (count == 2) {
    out << std::setw(2) << int(bytes[1]) << std::setw(2) << int(bytes[0]);
  } else if (count == 4) {
    for (int i = 3; i >= 0; --i) out << std::setw(2) << int(bytes[i]);
  } else {
    for (int i = 15; i >= 0; --i) {
      out << std::setw(2) << int(bytes[i]);
      const int n = 16 - i;
      if (n == 4 || n == 6 || n == 8 || n == 10) out << '-';
    }
  }
  return out.str();
}
std::optional<bool> IsConnectable(BluetoothLEAdvertisementType type) {
  switch (type) {
    case BluetoothLEAdvertisementType::ConnectableUndirected:
    case BluetoothLEAdvertisementType::ConnectableDirected: return true;
    case BluetoothLEAdvertisementType::ScannableUndirected:
    case BluetoothLEAdvertisementType::NonConnectableUndirected:
    case BluetoothLEAdvertisementType::ScanResponse: return false;
    default: return std::nullopt;
  }
}
}  // namespace
WindowsCentralBackend::WindowsCentralBackend(RssiCache& cache)
    : rssi_cache_(cache) {}
WindowsCentralBackend::~WindowsCentralBackend() {
  state_revoker_.revoke();
  StopScan();
}
NativeRadioState WindowsCentralBackend::ToNativeRadioState(RadioState state) {
  switch (state) {
    case RadioState::On: return NativeRadioState::kOn;
    case RadioState::Off: return NativeRadioState::kOff;
    case RadioState::Disabled: return NativeRadioState::kDisabled;
    default: return NativeRadioState::kUnknown;
  }
}
void WindowsCentralBackend::QueryState(StateCallback callback) {
  QueryStateAsync(std::move(callback));
}
winrt::fire_and_forget WindowsCentralBackend::QueryStateAsync(
    StateCallback callback) {
  state_callback_ = std::move(callback);
  try {
    adapter_ = co_await BluetoothAdapter::GetDefaultAsync();
    if (!adapter_) {
      state_callback_(MapClientState(false, false, NativeRadioState::kUnknown));
      co_return;
    }
    if (co_await Radio::RequestAccessAsync() != RadioAccessStatus::Allowed) {
      state_callback_(MapClientState(true, true, NativeRadioState::kUnknown));
      co_return;
    }
    radio_ = co_await adapter_.GetRadioAsync();
    if (!radio_) {
      state_callback_(MapClientState(true, false, NativeRadioState::kUnknown));
      co_return;
    }
    state_revoker_ = radio_.StateChanged(
        winrt::auto_revoke, [this](const Radio& sender, const auto&) {
          if (state_callback_) state_callback_(MapClientState(
              true, false, ToNativeRadioState(sender.State())));
        });
    state_callback_(MapClientState(
        true, false, ToNativeRadioState(radio_.State())));
  } catch (const winrt::hresult_error&) {
    state_callback_(MapClientState(true, false, NativeRadioState::kUnknown));
  }
}
std::optional<FlutterError> WindowsCentralBackend::StartScan(
    const std::vector<std::string>& service_uuids,
    AdvertisementCallback callback) {
  if (watcher_) return FlutterError(
      "scan_in_progress", "A Windows BLE scan is already active.");
  try {
    watcher_ = BluetoothLEAdvertisementWatcher();
    // TODO(butane_flutter-4um): map ScanOptions ScanningMode Active/Passive when the Pigeon field lands.
    watcher_.ScanningMode(BluetoothLEScanningMode::Active);
    auto filters = watcher_.AdvertisementFilter().Advertisement().ServiceUuids();
    for (const auto& uuid : service_uuids) {
      GUID value{};
      const auto text = winrt::to_hstring(uuid);
      if (FAILED(::CLSIDFromString(text.c_str(), &value))) {
        StopScan();
        return FlutterError("invalid_argument",
                            "Service filter contains an invalid UUID.");
      }
      filters.Append(winrt::guid(
          value.Data1, value.Data2, value.Data3,
          {value.Data4[0], value.Data4[1], value.Data4[2], value.Data4[3],
           value.Data4[4], value.Data4[5], value.Data4[6], value.Data4[7]}));
    }
    advertisement_callback_ = std::move(callback);
    received_revoker_ = watcher_.Received(
        winrt::auto_revoke, [this](const auto&, const auto& args) {
          const uint64_t address = args.BluetoothAddress();
          const int16_t rssi = args.RawSignalStrengthInDBm();
          rssi_cache_.Observe(address, rssi, RssiCache::Clock::now());
          AdvertisementEvent event = CopyAdvertisement(args);
          if (advertisement_callback_) advertisement_callback_(std::move(event));
        });
    watcher_.Start();
    return std::nullopt;
  } catch (const winrt::hresult_error& error) {
    StopScan();
    return FlutterError("scan_failed", winrt::to_string(error.message()));
  }
}
void WindowsCentralBackend::StopScan() {
  received_revoker_.revoke();
  if (watcher_) {
    auto status = watcher_.Status();
    if (status != BluetoothLEAdvertisementWatcherStatus::Stopped &&
        status != BluetoothLEAdvertisementWatcherStatus::Aborted)
      watcher_.Stop();
  }
  watcher_ = nullptr;
  advertisement_callback_ = nullptr;
}
AdvertisementEvent WindowsCentralBackend::CopyAdvertisement(
    const BluetoothLEAdvertisementReceivedEventArgs& args) {
  auto advertisement = args.Advertisement();
  AdvertisementEvent event{args.BluetoothAddress(),
      args.RawSignalStrengthInDBm(), std::nullopt, std::nullopt, {}, {}, {},
      std::nullopt, IsConnectable(args.AdvertisementType())};
  auto local_name = advertisement.LocalName();
  if (!local_name.empty()) {
    event.local_name = winrt::to_string(local_name);
    event.peripheral_name = event.local_name;
  }
  for (const auto& section : advertisement.ManufacturerData())
    event.manufacturer_data.push_back(
        {section.CompanyId(), CopyBuffer(section.Data())});
  for (const auto& uuid : advertisement.ServiceUuids())
    event.service_uuids.push_back(winrt::to_string(winrt::to_hstring(uuid)));
  for (const auto& section : advertisement.DataSections()) {
    const uint8_t type = section.DataType();
    if (type == 0x0A) {
      const auto bytes = CopyBuffer(section.Data());
      if (!bytes.empty()) event.tx_power = static_cast<int8_t>(bytes[0]);
      continue;
    }
    const size_t size = type == 0x16 ? 2 : (type == 0x20 ? 4 : (type == 0x21 ? 16 : 0));
    if (!size) continue;
    auto bytes = CopyBuffer(section.Data());
    if (bytes.size() < size) continue;
    auto uuid = NormalizeUuid(HexUuid(bytes.data(), size));
    if (uuid) event.service_data[*uuid] =
        std::vector<uint8_t>(bytes.begin() + size, bytes.end());
  }
  return event;
}
}  // namespace butane_windows
