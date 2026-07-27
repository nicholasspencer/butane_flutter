#include "butane_conversions.h"

#include <gtest/gtest.h>

#include <chrono>
#include <thread>

namespace butane_windows {
namespace test {

using namespace std::chrono_literals;

// ── CharacteristicPropertyFromMask ──────────────────────────────────────────
// The Windows half of butane_flutter-99s.

TEST(CharacteristicPropertyFromMask, NoneYieldsAllFalse) {
  const auto p = CharacteristicPropertyFromMask(kGattPropertyNone);
  EXPECT_FALSE(p.broadcast);
  EXPECT_FALSE(p.read);
  EXPECT_FALSE(p.write_without_response);
  EXPECT_FALSE(p.write);
  EXPECT_FALSE(p.notify);
  EXPECT_FALSE(p.indicate);
  EXPECT_FALSE(p.authenticated_signed_writes);
  EXPECT_FALSE(p.extended_properties);
}

TEST(CharacteristicPropertyFromMask, DecodesEachFlagIndependently) {
  EXPECT_TRUE(CharacteristicPropertyFromMask(kGattPropertyBroadcast).broadcast);
  EXPECT_TRUE(CharacteristicPropertyFromMask(kGattPropertyRead).read);
  EXPECT_TRUE(CharacteristicPropertyFromMask(kGattPropertyWriteWithoutResponse)
                  .write_without_response);
  EXPECT_TRUE(CharacteristicPropertyFromMask(kGattPropertyWrite).write);
  EXPECT_TRUE(CharacteristicPropertyFromMask(kGattPropertyNotify).notify);
  EXPECT_TRUE(CharacteristicPropertyFromMask(kGattPropertyIndicate).indicate);
  EXPECT_TRUE(
      CharacteristicPropertyFromMask(kGattPropertyAuthenticatedSignedWrites)
          .authenticated_signed_writes);
}

TEST(CharacteristicPropertyFromMask, DecodesCombinations) {
  // The overwhelmingly common NUS-style characteristic: write + notify.
  const auto p =
      CharacteristicPropertyFromMask(kGattPropertyWrite | kGattPropertyNotify);
  EXPECT_TRUE(p.write);
  EXPECT_TRUE(p.notify);
  EXPECT_FALSE(p.read);
  EXPECT_FALSE(p.indicate);
}

TEST(CharacteristicPropertyFromMask, AnyExtendedFlagSetsExtendedProperties) {
  // WinRT splits ATT's Extended Properties bit into three flags; all three
  // must fold onto the single Pigeon field.
  EXPECT_TRUE(CharacteristicPropertyFromMask(kGattPropertyExtendedProperties)
                  .extended_properties);
  EXPECT_TRUE(CharacteristicPropertyFromMask(kGattPropertyReliableWrites)
                  .extended_properties);
  EXPECT_TRUE(CharacteristicPropertyFromMask(kGattPropertyWritableAuxiliaries)
                  .extended_properties);
}

TEST(CharacteristicPropertyFromMask, EncryptionFieldsAreAlwaysFalse) {
  // These are Android/BlueZ concepts with no WinRT analog. Pinned by a test so
  // a future change has to be deliberate rather than accidental.
  const auto all = CharacteristicPropertyFromMask(0xFFFFFFFF);
  EXPECT_FALSE(all.notify_encryption_required);
  EXPECT_FALSE(all.indicate_encryption_required);
}

TEST(CharacteristicPropertyFromMask, IgnoresUnknownBits) {
  const auto p = CharacteristicPropertyFromMask(kGattPropertyRead | 0x80000000);
  EXPECT_TRUE(p.read);
  EXPECT_FALSE(p.write);
}

// ── Bluetooth address ───────────────────────────────────────────────────────

TEST(FormatBluetoothAddress, FormatsMostSignificantOctetFirst) {
  EXPECT_EQ(FormatBluetoothAddress(0x00A1B2C3D4E5ULL), "00:A1:B2:C3:D4:E5");
}

TEST(FormatBluetoothAddress, ZeroIsSixZeroOctets) {
  EXPECT_EQ(FormatBluetoothAddress(0ULL), "00:00:00:00:00:00");
}

TEST(FormatBluetoothAddress, FormatsMaximum48BitValue) {
  EXPECT_EQ(FormatBluetoothAddress(0xFFFFFFFFFFFFULL), "FF:FF:FF:FF:FF:FF");
}

TEST(FormatBluetoothAddress, IgnoresBitsAboveTheLow48) {
  // WinRT's BluetoothAddress is a 48-bit value carried in a uint64.
  EXPECT_EQ(FormatBluetoothAddress(0xDEAD00A1B2C3D4E5ULL), "00:A1:B2:C3:D4:E5");
}

TEST(ParseBluetoothAddress, RoundTripsWithFormat) {
  const uint64_t address = 0x00A1B2C3D4E5ULL;
  const auto parsed = ParseBluetoothAddress(FormatBluetoothAddress(address));
  ASSERT_TRUE(parsed.has_value());
  EXPECT_EQ(*parsed, address);
}

TEST(ParseBluetoothAddress, AcceptsLowercaseAndDashSeparators) {
  const auto colon = ParseBluetoothAddress("00:a1:b2:c3:d4:e5");
  const auto dash = ParseBluetoothAddress("00-A1-B2-C3-D4-E5");
  ASSERT_TRUE(colon.has_value());
  ASSERT_TRUE(dash.has_value());
  EXPECT_EQ(*colon, 0x00A1B2C3D4E5ULL);
  EXPECT_EQ(*dash, *colon);
}

TEST(ParseBluetoothAddress, RejectsMalformedInput) {
  // Fail closed: a malformed identifier must never silently address a
  // different device.
  EXPECT_FALSE(ParseBluetoothAddress("").has_value());
  EXPECT_FALSE(ParseBluetoothAddress("00:A1:B2:C3:D4").has_value());
  EXPECT_FALSE(ParseBluetoothAddress("00:A1:B2:C3:D4:E5:F6").has_value());
  EXPECT_FALSE(ParseBluetoothAddress("00:A1:B2:C3:D4:").has_value());
  EXPECT_FALSE(ParseBluetoothAddress("00:A1:B2:C3:D4:ZZ").has_value());
  EXPECT_FALSE(ParseBluetoothAddress("00A1B2C3D4E5").has_value());
  EXPECT_FALSE(ParseBluetoothAddress("0:A1:B2:C3:D4:E5").has_value());
}

// ── UUIDs ───────────────────────────────────────────────────────────────────

TEST(NormalizeUuid, Expands16BitShorthand) {
  const auto n = NormalizeUuid("180D");
  ASSERT_TRUE(n.has_value());
  EXPECT_EQ(*n, "0000180d-0000-1000-8000-00805f9b34fb");
}

TEST(NormalizeUuid, Expands32BitShorthand) {
  const auto n = NormalizeUuid("0000180D");
  ASSERT_TRUE(n.has_value());
  EXPECT_EQ(*n, "0000180d-0000-1000-8000-00805f9b34fb");
}

TEST(NormalizeUuid, LowercasesCanonicalForm) {
  const auto n = NormalizeUuid("0000180D-0000-1000-8000-00805F9B34FB");
  ASSERT_TRUE(n.has_value());
  EXPECT_EQ(*n, "0000180d-0000-1000-8000-00805f9b34fb");
}

TEST(NormalizeUuid, StripsTheBracesWinRtGuidFormattingEmits) {
  const auto n = NormalizeUuid("{0000180D-0000-1000-8000-00805F9B34FB}");
  ASSERT_TRUE(n.has_value());
  EXPECT_EQ(*n, "0000180d-0000-1000-8000-00805f9b34fb");
}

TEST(NormalizeUuid, RejectsMalformedInput) {
  EXPECT_FALSE(NormalizeUuid("").has_value());
  EXPECT_FALSE(NormalizeUuid("18").has_value());
  EXPECT_FALSE(NormalizeUuid("180G").has_value());
  EXPECT_FALSE(NormalizeUuid("0000180d-0000-1000-8000").has_value());
  EXPECT_FALSE(NormalizeUuid("0000180d00001000800000805f9b34fb").has_value());
  // Hyphens in the wrong places.
  EXPECT_FALSE(NormalizeUuid("0000180d-000-01000-8000-00805f9b34fb").has_value());
}

TEST(UuidEquals, MatchesAcrossCasingAndShorthand) {
  // The regression butane_flutter/cb940b8 fixed: GATT UUIDs are
  // platform-cased, so comparison must not be case-sensitive.
  EXPECT_TRUE(UuidEquals("180D", "0000180D-0000-1000-8000-00805F9B34FB"));
  EXPECT_TRUE(UuidEquals("0000180d-0000-1000-8000-00805f9b34fb",
                         "{0000180D-0000-1000-8000-00805F9B34FB}"));
  EXPECT_TRUE(UuidEquals("180d", "180D"));
}

TEST(UuidEquals, DistinguishesDifferentUuids) {
  EXPECT_FALSE(UuidEquals("180D", "180F"));
}

TEST(UuidEquals, MalformedIsNeverEqual) {
  // Including to another malformed value — otherwise two unparseable strings
  // would compare equal and silently match the wrong characteristic.
  EXPECT_FALSE(UuidEquals("nonsense", "180D"));
  EXPECT_FALSE(UuidEquals("nonsense", "nonsense"));
}

// ── RssiCache ───────────────────────────────────────────────────────────────

TEST(RssiCache, ReturnsAFreshObservation) {
  RssiCache cache;
  const auto t0 = RssiCache::Clock::time_point{};
  cache.Observe(0x1234ULL, -55, t0);
  const auto got = cache.Get(0x1234ULL, t0 + 1s, 30s);
  ASSERT_TRUE(got.has_value());
  EXPECT_EQ(*got, -55);
}

TEST(RssiCache, MissingAddressYieldsNullopt) {
  RssiCache cache;
  const auto t0 = RssiCache::Clock::time_point{};
  EXPECT_FALSE(cache.Get(0xBEEFULL, t0, 30s).has_value());
}

TEST(RssiCache, StaleObservationYieldsNullopt) {
  // Better to report "no RSSI" than to hand back a minutes-old number as if
  // it described the current link.
  RssiCache cache;
  const auto t0 = RssiCache::Clock::time_point{};
  cache.Observe(0x1234ULL, -55, t0);
  EXPECT_FALSE(cache.Get(0x1234ULL, t0 + 31s, 30s).has_value());
}

TEST(RssiCache, MaxAgeBoundaryIsInclusive) {
  RssiCache cache;
  const auto t0 = RssiCache::Clock::time_point{};
  cache.Observe(0x1234ULL, -55, t0);
  EXPECT_TRUE(cache.Get(0x1234ULL, t0 + 30s, 30s).has_value());
  EXPECT_FALSE(cache.Get(0x1234ULL, t0 + 30s + 1ms, 30s).has_value());
}

TEST(RssiCache, LaterObservationReplacesEarlier) {
  RssiCache cache;
  const auto t0 = RssiCache::Clock::time_point{};
  cache.Observe(0x1234ULL, -80, t0);
  cache.Observe(0x1234ULL, -40, t0 + 5s);
  const auto got = cache.Get(0x1234ULL, t0 + 6s, 30s);
  ASSERT_TRUE(got.has_value());
  EXPECT_EQ(*got, -40);
  EXPECT_EQ(cache.Size(), 1u);
}

TEST(RssiCache, TracksAddressesIndependently) {
  RssiCache cache;
  const auto t0 = RssiCache::Clock::time_point{};
  cache.Observe(0x1111ULL, -50, t0);
  cache.Observe(0x2222ULL, -70, t0);
  EXPECT_EQ(*cache.Get(0x1111ULL, t0, 30s), -50);
  EXPECT_EQ(*cache.Get(0x2222ULL, t0, 30s), -70);
  EXPECT_EQ(cache.Size(), 2u);
}

TEST(RssiCache, ForgetRemovesOnlyTheNamedAddress) {
  RssiCache cache;
  const auto t0 = RssiCache::Clock::time_point{};
  cache.Observe(0x1111ULL, -50, t0);
  cache.Observe(0x2222ULL, -70, t0);
  cache.Forget(0x1111ULL);
  EXPECT_FALSE(cache.Get(0x1111ULL, t0, 30s).has_value());
  EXPECT_TRUE(cache.Get(0x2222ULL, t0, 30s).has_value());
  EXPECT_EQ(cache.Size(), 1u);
}

TEST(RssiCache, ClearEmptiesEverything) {
  RssiCache cache;
  const auto t0 = RssiCache::Clock::time_point{};
  cache.Observe(0x1111ULL, -50, t0);
  cache.Observe(0x2222ULL, -70, t0);
  cache.Clear();
  EXPECT_EQ(cache.Size(), 0u);
}
TEST(RssiCache, ConcurrentObserveAndGetIsSafe) {
  RssiCache cache;
  const auto now = RssiCache::Clock::now();
  auto run = [&cache, now](uint64_t address, int16_t final_value) {
    for (int i = 0; i < 1000; ++i)
      cache.Observe(address, static_cast<int16_t>(final_value - 1), now);
    cache.Observe(address, final_value, now);
  };
  std::thread a(run, uint64_t{1}, int16_t{-41});
  std::thread b(run, uint64_t{2}, int16_t{-72});
  a.join();
  b.join();
  EXPECT_EQ(cache.Get(1, now, 30s), -41);
  EXPECT_EQ(cache.Get(2, now, 30s), -72);
}

}  // namespace test
}  // namespace butane_windows
