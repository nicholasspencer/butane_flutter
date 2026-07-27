#include "butane_gatt_discovery.h"

#include "butane_conversions.h"

#include <algorithm>
#include <stdexcept>

namespace butane_windows {
namespace {
FlutterError NotFound() {
  return FlutterError("not-found", "GATT discovery data was not found.");
}
}

FlutterError GattDiscoveryError(GattDiscoveryStatus status,
                                std::optional<uint8_t> protocol_error) {
  switch (status) {
    case GattDiscoveryStatus::kUnreachable:
      return FlutterError("not-connected",
                          "Peripheral is unreachable during GATT discovery.");
    case GattDiscoveryStatus::kProtocolError:
      return FlutterError(
          "discovery-failed",
          "GATT protocol error " +
              std::to_string(static_cast<unsigned>(
                  protocol_error.value_or(uint8_t{0}))) +
              ".");
    case GattDiscoveryStatus::kAccessDenied:
      return FlutterError("unauthorized", "Bluetooth GATT access was denied.");
    case GattDiscoveryStatus::kSuccess:
      throw std::logic_error("success is not a discovery error");
  }
  throw std::logic_error("unknown discovery status");
}

ErrorOr<std::vector<std::string>> NormalizeGattFilter(
    const flutter::EncodableList* values) {
  std::vector<std::string> result;
  if (!values) return result;
  for (const auto& value : *values) {
    const auto* text = std::get_if<std::string>(&value);
    const auto normalized = text ? NormalizeUuid(*text) : std::nullopt;
    if (!normalized) {
      return FlutterError(
          "invalid_argument", "GATT filters must contain valid UUID strings.");
    }
    result.push_back(*normalized);
  }
  return result;
}

void GattDiscoveryCache::ReplaceServices(
    uint64_t address, std::vector<GattServiceData> services) {
  const std::scoped_lock lock(mutex_);
  auto& snapshot = snapshots_[address];
  snapshot.services = std::move(services);
  snapshot.characteristics.clear();
}

ErrorOr<std::vector<GattServiceData>> GattDiscoveryCache::Services(
    uint64_t address) const {
  const std::scoped_lock lock(mutex_);
  const auto found = snapshots_.find(address);
  if (found == snapshots_.end()) return NotFound();
  return found->second.services;
}

bool GattDiscoveryCache::HasService(
    uint64_t address, std::string_view service_uuid) const {
  const std::scoped_lock lock(mutex_);
  const auto found = snapshots_.find(address);
  return found != snapshots_.end() &&
      std::any_of(found->second.services.begin(), found->second.services.end(),
                  [&](const auto& item) { return item.uuid == service_uuid; });
}

void GattDiscoveryCache::ReplaceCharacteristics(
    uint64_t address, std::string service_uuid,
    std::vector<GattCharacteristicData> characteristics) {
  const std::scoped_lock lock(mutex_);
  snapshots_[address].characteristics[std::move(service_uuid)] =
      std::move(characteristics);
}

ErrorOr<std::vector<GattCharacteristicData>>
GattDiscoveryCache::Characteristics(
    uint64_t address, std::string_view service_uuid) const {
  const std::scoped_lock lock(mutex_);
  const auto snapshot = snapshots_.find(address);
  if (snapshot == snapshots_.end()) return NotFound();
  const auto found =
      snapshot->second.characteristics.find(std::string(service_uuid));
  if (found == snapshot->second.characteristics.end()) return NotFound();
  return found->second;
}

}  // namespace butane_windows
