// Pure conversions between WinRT's Bluetooth representations and butane's
// platform-interface shapes.
//
// Everything here is deliberately free of WinRT headers and of any radio: the
// inputs are plain integers and strings, so this compiles and unit-tests on a
// Windows box with no adapter, no paired device, and no GATT session. That is
// the whole point — it is the part of the backend that can be proven by
// `butane_windows_test` rather than by plugging in two radios.
//
// See docs/windows-dev-environment.md for the build target.

#ifndef PACKAGES_BUTANE_WINDOWS_WINDOWS_BUTANE_CONVERSIONS_H_
#define PACKAGES_BUTANE_WINDOWS_WINDOWS_BUTANE_CONVERSIONS_H_

#include <chrono>
#include <cstdint>
#include <optional>
#include <string>
#include <string_view>
#include <unordered_map>

namespace butane_windows {

// The flag values of WinRT's
// Windows.Devices.Bluetooth.GenericAttributeProfile.GattCharacteristicProperties.
// Mirrored as plain constants so this header stays WinRT-free; the values are
// ABI-stable.
enum GattCharacteristicPropertiesFlag : uint32_t {
  kGattPropertyNone = 0x0000,
  kGattPropertyBroadcast = 0x0001,
  kGattPropertyRead = 0x0002,
  kGattPropertyWriteWithoutResponse = 0x0004,
  kGattPropertyWrite = 0x0008,
  kGattPropertyNotify = 0x0010,
  kGattPropertyIndicate = 0x0020,
  kGattPropertyAuthenticatedSignedWrites = 0x0040,
  kGattPropertyExtendedProperties = 0x0080,
  kGattPropertyReliableWrites = 0x0100,
  kGattPropertyWritableAuxiliaries = 0x0200,
};

// Mirrors the Pigeon `CharacteristicProperty` class (10 bools).
//
// Two fields have NO WinRT analog and are therefore always false here:
// `notify_encryption_required` and `indicate_encryption_required` are
// Android/BlueZ concepts. WinRT expresses encryption requirements through the
// pairing/protection level on the session, not through characteristic
// property flags.
struct CharacteristicProperty {
  bool broadcast = false;
  bool read = false;
  bool write_without_response = false;
  bool write = false;
  bool notify = false;
  bool indicate = false;
  bool authenticated_signed_writes = false;
  bool extended_properties = false;
  bool notify_encryption_required = false;
  bool indicate_encryption_required = false;
};

// Decodes a GattCharacteristicProperties bitmask.
//
// This is the Windows half of butane_flutter-99s: iOS/macOS never populated
// the property list, so Dart callers had to trial-and-error every operation
// and catch the failure. Windows populates it from the first commit.
CharacteristicProperty CharacteristicPropertyFromMask(uint32_t mask);

// Formats a WinRT `BluetoothAddress` (a 48-bit value in a uint64) as the
// conventional colon-separated uppercase MAC string, most-significant octet
// first: 0x00A1B2C3D4E5 -> "00:A1:B2:C3:D4:E5".
std::string FormatBluetoothAddress(uint64_t address);

// Inverse of FormatBluetoothAddress. Accepts either case and either ':' or '-'
// as the separator. Returns nullopt when the input is not exactly six valid
// hex octets, so a malformed identifier fails closed rather than silently
// addressing the wrong device.
std::optional<uint64_t> ParseBluetoothAddress(std::string_view text);

// Canonicalises a Bluetooth UUID to the lowercase 128-bit form.
//
// GATT UUIDs are platform-cased — CoreBluetooth yields uppercase, BlueZ
// lowercase, WinRT mixed — and 16-/32-bit shorthand is common in
// advertisements. butane_flutter/cb940b8 fixed a real burn failure caused by
// case-sensitive comparison. Expands shorthand against the Bluetooth Base
// UUID (0000xxxx-0000-1000-8000-00805f9b34fb). Braces are tolerated and
// stripped (WinRT's GUID formatting emits them).
//
// Returns nullopt if the input is not a 16-, 32-, or 128-bit UUID.
std::optional<std::string> NormalizeUuid(std::string_view uuid);

// Case- and format-insensitive UUID comparison. "180D", "0000180d-0000-1000-
// 8000-00805F9B34FB" and "{0000180D-0000-1000-8000-00805F9B34FB}" are all
// equal. Malformed inputs are never equal to anything, including each other.
bool UuidEquals(std::string_view a, std::string_view b);

// Last-seen RSSI per device address.
//
// WinRT exposes RSSI only on advertisement receipt — there is no per-connection
// read as CoreBluetooth and BlueZ provide. The backend therefore records what
// the advertisement watcher saw and answers `readRssi` from here, which is the
// ruling recorded on the Windows epic.
//
// Time is passed IN rather than read from a clock inside, so staleness is
// testable without sleeping.
class RssiCache {
 public:
  using Clock = std::chrono::steady_clock;

  // Records an observation, replacing any previous one for that address.
  void Observe(uint64_t address, int16_t rssi, Clock::time_point at);

  // Returns the observation if one exists and is younger than `max_age`.
  // A stale or missing entry yields nullopt — callers surface that as "no
  // RSSI available" rather than inventing a number.
  std::optional<int16_t> Get(uint64_t address,
                             Clock::time_point now,
                             std::chrono::milliseconds max_age) const;

  // Drops an address (on disconnect, or when the watcher stops).
  void Forget(uint64_t address);

  void Clear();
  size_t Size() const;

 private:
  struct Entry {
    int16_t rssi;
    Clock::time_point at;
  };
  std::unordered_map<uint64_t, Entry> entries_;
};

}  // namespace butane_windows

#endif  // PACKAGES_BUTANE_WINDOWS_WINDOWS_BUTANE_CONVERSIONS_H_
