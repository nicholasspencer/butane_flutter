#include <gtest/gtest.h>

#include <memory>
#include <optional>
#include <string>
#include <utility>
#include <vector>

#include "butane_bonding_winrt.h"

namespace butane_windows::test {
namespace {

class FakeNativeBonding final : public NativeBonding {
 public:
  void Pair(uint64_t address, Completion completion) override {
    pair_addresses.push_back(address);
    pair_completion = std::move(completion);
  }
  void State(uint64_t address, Completion completion) override {
    state_addresses.push_back(address);
    state_completion = std::move(completion);
  }
  void Close() override { ++closes; }

  void CompletePair(NativeBondingStatus status,
                    std::string message = "pair result") {
    pair_completion({status, std::move(message), std::nullopt});
  }
  void CompleteState(NativeBondingStatus status,
                     std::string message = "state result") {
    state_completion({status, std::move(message), std::nullopt});
  }

  int closes = 0;
  std::vector<uint64_t> pair_addresses;
  std::vector<uint64_t> state_addresses;
  Completion pair_completion;
  Completion state_completion;
};

constexpr uint64_t kAddress = 0x00A1B2C3D4E5ULL;

TEST(WindowsBondingBackend, BondPublishesBondingThenBonded) {
  auto native = std::make_shared<FakeNativeBonding>();
  WindowsBondingBackend backend(native);
  std::vector<BondState> states;
  bool completed = false;
  backend.Bond(
      kAddress, PeripheralSession("00:A1:B2:C3:D4:E5"),
      [&](BondSnapshot snapshot) { states.push_back(snapshot.state); },
      [&](auto error) {
        EXPECT_FALSE(error);
        completed = true;
      });

  EXPECT_EQ(native->pair_addresses, (std::vector<uint64_t>{kAddress}));
  EXPECT_EQ(states, (std::vector<BondState>{BondState::kBonding}));
  native->CompletePair(NativeBondingStatus::kPaired);
  EXPECT_EQ(states, (std::vector<BondState>{BondState::kBonding,
                                            BondState::kBonded}));
  EXPECT_TRUE(completed);
}

TEST(WindowsBondingBackend, BondFailurePublishesNone) {
  auto native = std::make_shared<FakeNativeBonding>();
  WindowsBondingBackend backend(native);
  std::vector<BondState> states;
  backend.Bond(
      kAddress, PeripheralSession("peripheral"),
      [&](BondSnapshot snapshot) { states.push_back(snapshot.state); },
      [](auto error) {
        ASSERT_TRUE(error);
        EXPECT_EQ(error->code(), "operationFailed");
      });
  native->CompletePair(NativeBondingStatus::kUnpaired);

  EXPECT_EQ(states, (std::vector<BondState>{BondState::kBonding,
                                            BondState::kNone}));
}

TEST(WindowsBondingBackend, MissingDeviceReturnsNotFound) {
  auto native = std::make_shared<FakeNativeBonding>();
  WindowsBondingBackend backend(native);
  backend.Bond(kAddress, PeripheralSession("peripheral"), [](auto) {},
               [](auto error) {
                 ASSERT_TRUE(error);
                 EXPECT_EQ(error->code(), "notFound");
               });
  native->CompletePair(NativeBondingStatus::kNotFound, "missing");
}

TEST(WindowsBondingBackend, StateReportsBondingWhilePairInFlight) {
  auto native = std::make_shared<FakeNativeBonding>();
  WindowsBondingBackend backend(native);
  backend.Bond(kAddress, PeripheralSession("peripheral"), [](auto) {},
               [](auto) {});
  backend.State(kAddress, [](auto result) {
    ASSERT_FALSE(result.has_error());
    EXPECT_EQ(result.value(), BondState::kBonding);
  });
  EXPECT_TRUE(native->state_addresses.empty());

  native->CompletePair(NativeBondingStatus::kPaired);
  backend.State(kAddress, [](auto result) {
    ASSERT_FALSE(result.has_error());
    EXPECT_EQ(result.value(), BondState::kBonded);
  });
  ASSERT_EQ(native->state_addresses.size(), 1u);
  native->CompleteState(NativeBondingStatus::kPaired);
}

TEST(WindowsBondingBackend, StateMapsUnpairedAndErrors) {
  auto native = std::make_shared<FakeNativeBonding>();
  WindowsBondingBackend backend(native);
  backend.State(kAddress, [](auto result) {
    ASSERT_FALSE(result.has_error());
    EXPECT_EQ(result.value(), BondState::kNone);
  });
  native->CompleteState(NativeBondingStatus::kUnpaired);

  backend.State(kAddress, [](auto result) {
    ASSERT_TRUE(result.has_error());
    EXPECT_EQ(result.error().code(), "operationFailed");
  });
  native->CompleteState(NativeBondingStatus::kFailed);
}

TEST(WindowsBondingBackend, CloseSuppressesCallbacks) {
  auto native = std::make_shared<FakeNativeBonding>();
  int callbacks = 0;
  {
    WindowsBondingBackend backend(native);
    backend.Bond(
        kAddress, PeripheralSession("peripheral"),
        [&](auto) { ++callbacks; }, [&](auto) { ++callbacks; });
    EXPECT_EQ(callbacks, 1);
    backend.Close();
    EXPECT_EQ(native->closes, 1);
    native->CompletePair(NativeBondingStatus::kPaired);
  }
  EXPECT_EQ(callbacks, 1);
  EXPECT_EQ(native->closes, 1);
}

}  // namespace
}  // namespace butane_windows::test
