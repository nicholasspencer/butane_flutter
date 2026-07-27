#include <gtest/gtest.h>

#include "butane_gatt_discovery.h"

namespace butane_windows::test {
TEST(GattFilter, NullMeansAll) {
  EXPECT_TRUE(NormalizeGattFilter(nullptr).value().empty());
}
TEST(GattFilter, EmptyMeansNone) {
  flutter::EncodableList values;
  EXPECT_TRUE(NormalizeGattFilter(&values).value().empty());
}
TEST(GattFilter, NormalizesAndRejectsInvalid) {
  flutter::EncodableList values{flutter::EncodableValue("180D")};
  EXPECT_EQ(NormalizeGattFilter(&values).value()[0],
            "0000180d-0000-1000-8000-00805f9b34fb");
  values.emplace_back(int32_t{1});
  EXPECT_EQ(NormalizeGattFilter(&values).error().code(), "invalid_argument");
}
TEST(GattDiscoveryError, MapsEveryFailureStatus) {
  EXPECT_EQ(GattDiscoveryError(GattDiscoveryStatus::kUnreachable, {}).code(),
            "not-connected");
  EXPECT_EQ(GattDiscoveryError(GattDiscoveryStatus::kProtocolError,
                               uint8_t{5}).code(),
            "discovery-failed");
  EXPECT_EQ(GattDiscoveryError(GattDiscoveryStatus::kAccessDenied, {}).code(),
            "unauthorized");
  EXPECT_THROW(GattDiscoveryError(GattDiscoveryStatus::kSuccess, {}),
               std::logic_error);
}
TEST(GattDiscoveryCache, ReplacesSuccessfulServicesAndClearsCharacteristics) {
  GattDiscoveryCache cache;
  cache.ReplaceServices(1, {{"a", true}});
  cache.ReplaceCharacteristics(1, "a", {{"b", 0, {}}});
  cache.ReplaceServices(1, {{"c", true}});
  EXPECT_EQ(cache.Services(1).value()[0].uuid, "c");
  EXPECT_TRUE(cache.Characteristics(1, "a").has_error());
}
TEST(GattDiscoveryCache, FailurePreservesPriorSnapshot) {
  GattDiscoveryCache cache;
  cache.ReplaceServices(1, {{"a", true}});
  EXPECT_EQ(cache.Services(1).value()[0].uuid, "a");
}
TEST(GattDiscoveryCache, IsolatesAddresses) {
  GattDiscoveryCache cache;
  cache.ReplaceServices(1, {{"a", true}});
  cache.ReplaceServices(2, {{"b", true}});
  EXPECT_EQ(cache.Services(1).value()[0].uuid, "a");
  EXPECT_EQ(cache.Services(2).value()[0].uuid, "b");
}
TEST(GattDiscoveryCache, MissingDataReturnsNotFound) {
  GattDiscoveryCache cache;
  EXPECT_EQ(cache.Services(1).error().code(), "not-found");
  cache.ReplaceServices(1, {{"a", true}});
  EXPECT_EQ(cache.Characteristics(1, "a").error().code(), "not-found");
}
}  // namespace butane_windows::test
