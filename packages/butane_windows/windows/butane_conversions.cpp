#include "butane_conversions.h"

#include <algorithm>
#include <cctype>

namespace butane_windows {
namespace {

// The Bluetooth Base UUID, against which 16- and 32-bit shorthand expands.
constexpr std::string_view kBaseUuidSuffix = "-0000-1000-8000-00805f9b34fb";

bool IsHexDigit(char c) {
  return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') ||
         (c >= 'A' && c <= 'F');
}

int HexValue(char c) {
  if (c >= '0' && c <= '9') return c - '0';
  if (c >= 'a' && c <= 'f') return c - 'a' + 10;
  return c - 'A' + 10;
}

char ToLowerAscii(char c) {
  return (c >= 'A' && c <= 'Z') ? static_cast<char>(c - 'A' + 'a') : c;
}

std::string ToLowerAscii(std::string_view text) {
  std::string out;
  out.reserve(text.size());
  for (char c : text) out.push_back(ToLowerAscii(c));
  return out;
}

// Strips the braces WinRT's GUID formatting emits, plus surrounding spaces.
std::string_view StripBracesAndSpace(std::string_view text) {
  while (!text.empty() && (text.front() == ' ' || text.front() == '\t')) {
    text.remove_prefix(1);
  }
  while (!text.empty() && (text.back() == ' ' || text.back() == '\t')) {
    text.remove_suffix(1);
  }
  if (text.size() >= 2 && text.front() == '{' && text.back() == '}') {
    text.remove_prefix(1);
    text.remove_suffix(1);
  }
  return text;
}

bool IsCanonical128(std::string_view text) {
  // 8-4-4-4-12 with hyphens at 8, 13, 18, 23.
  if (text.size() != 36) return false;
  for (size_t i = 0; i < text.size(); ++i) {
    const bool hyphen_position = (i == 8 || i == 13 || i == 18 || i == 23);
    if (hyphen_position) {
      if (text[i] != '-') return false;
    } else if (!IsHexDigit(text[i])) {
      return false;
    }
  }
  return true;
}

bool IsAllHex(std::string_view text) {
  if (text.empty()) return false;
  return std::all_of(text.begin(), text.end(),
                     [](char c) { return IsHexDigit(c); });
}

}  // namespace

CharacteristicProperty CharacteristicPropertyFromMask(uint32_t mask) {
  CharacteristicProperty property;
  property.broadcast = (mask & kGattPropertyBroadcast) != 0;
  property.read = (mask & kGattPropertyRead) != 0;
  property.write_without_response =
      (mask & kGattPropertyWriteWithoutResponse) != 0;
  property.write = (mask & kGattPropertyWrite) != 0;
  property.notify = (mask & kGattPropertyNotify) != 0;
  property.indicate = (mask & kGattPropertyIndicate) != 0;
  property.authenticated_signed_writes =
      (mask & kGattPropertyAuthenticatedSignedWrites) != 0;
  // WinRT splits "extended properties" into the descriptor-backed
  // ReliableWrites / WritableAuxiliaries flags. Either implies the ATT
  // Extended Properties bit is set, so fold all three together.
  property.extended_properties =
      (mask & (kGattPropertyExtendedProperties | kGattPropertyReliableWrites |
               kGattPropertyWritableAuxiliaries)) != 0;
  // No WinRT analog — see the header.
  property.notify_encryption_required = false;
  property.indicate_encryption_required = false;
  return property;
}

std::string FormatBluetoothAddress(uint64_t address) {
  static constexpr char kHex[] = "0123456789ABCDEF";
  std::string out;
  out.reserve(17);  // 6 octets * 2 + 5 separators
  for (int shift = 40; shift >= 0; shift -= 8) {
    const auto octet = static_cast<uint8_t>((address >> shift) & 0xFF);
    if (!out.empty()) out.push_back(':');
    out.push_back(kHex[(octet >> 4) & 0x0F]);
    out.push_back(kHex[octet & 0x0F]);
  }
  return out;
}

std::optional<uint64_t> ParseBluetoothAddress(std::string_view text) {
  uint64_t value = 0;
  int octets = 0;
  size_t i = 0;
  while (i < text.size()) {
    if (octets > 0) {
      // Require exactly one separator between octets.
      if (text[i] != ':' && text[i] != '-') return std::nullopt;
      ++i;
    }
    if (i + 1 >= text.size()) return std::nullopt;
    if (!IsHexDigit(text[i]) || !IsHexDigit(text[i + 1])) return std::nullopt;
    value = (value << 8) |
            static_cast<uint64_t>(HexValue(text[i]) * 16 + HexValue(text[i + 1]));
    i += 2;
    ++octets;
    if (octets > 6) return std::nullopt;
  }
  if (octets != 6 || i != text.size()) return std::nullopt;
  return value;
}

std::optional<std::string> NormalizeUuid(std::string_view uuid) {
  const std::string_view trimmed = StripBracesAndSpace(uuid);
  if (trimmed.empty()) return std::nullopt;

  // 128-bit canonical form.
  if (IsCanonical128(trimmed)) return ToLowerAscii(trimmed);

  // 16-bit ("180D") or 32-bit ("0000180D") shorthand.
  if ((trimmed.size() == 4 || trimmed.size() == 8) && IsAllHex(trimmed)) {
    std::string prefix = ToLowerAscii(trimmed);
    if (prefix.size() == 4) prefix = "0000" + prefix;
    return prefix + std::string(kBaseUuidSuffix);
  }

  return std::nullopt;
}

bool UuidEquals(std::string_view a, std::string_view b) {
  const auto left = NormalizeUuid(a);
  const auto right = NormalizeUuid(b);
  if (!left.has_value() || !right.has_value()) return false;
  return *left == *right;
}

void RssiCache::Observe(uint64_t address, int16_t rssi, Clock::time_point at) {
  const std::scoped_lock lock(mutex_);
  entries_[address] = Entry{rssi, at};
}

std::optional<int16_t> RssiCache::Get(
    uint64_t address,
    Clock::time_point now,
    std::chrono::milliseconds max_age) const {
  const std::scoped_lock lock(mutex_);
  const auto it = entries_.find(address);
  if (it == entries_.end()) return std::nullopt;
  const auto age =
      std::chrono::duration_cast<std::chrono::milliseconds>(now - it->second.at);
  if (age > max_age) return std::nullopt;
  return it->second.rssi;
}

void RssiCache::Forget(uint64_t address) {
  const std::scoped_lock lock(mutex_);
  entries_.erase(address);
}

void RssiCache::Clear() {
  const std::scoped_lock lock(mutex_);
  entries_.clear();
}

size_t RssiCache::Size() const {
  const std::scoped_lock lock(mutex_);
  return entries_.size();
}

}  // namespace butane_windows
