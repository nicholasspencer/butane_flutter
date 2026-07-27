#include "butane_gatt_operations.h"

#include <gtest/gtest.h>

#include <optional>
#include <stdexcept>
#include <string>

namespace butane_windows {
namespace {

struct ErrorCase {
  GattOperationStatus status;
  const char* code;
};

class GattOperationErrorTest
    : public testing::TestWithParam<ErrorCase> {};

TEST_P(GattOperationErrorTest, MapsStatus) {
  const auto error =
      GattOperationError("write characteristic", GetParam().status);
  EXPECT_EQ(error.code(), GetParam().code);
  EXPECT_NE(error.message().find("write characteristic"), std::string::npos);
}

INSTANTIATE_TEST_SUITE_P(
    Statuses, GattOperationErrorTest,
    testing::Values(
        ErrorCase{GattOperationStatus::kUnreachable, "not-connected"},
        ErrorCase{GattOperationStatus::kAccessDenied, "unauthorized"},
        ErrorCase{GattOperationStatus::kNotFound, "not-found"},
        ErrorCase{GattOperationStatus::kUnsupported, "unsupported"}));

TEST(GattOperationErrorTest, MapsProtocolErrorWithOperationAndByte) {
  const auto error = GattOperationError(
      "write descriptor", GattOperationStatus::kProtocolError, uint8_t{42});
  EXPECT_EQ(error.code(), "gatt-operation-failed");
  EXPECT_NE(error.message().find("write descriptor"), std::string::npos);
  EXPECT_NE(error.message().find("42"), std::string::npos);
}

TEST(GattOperationErrorTest, RejectsSuccess) {
  EXPECT_THROW(
      GattOperationError("observe characteristic",
                         GattOperationStatus::kSuccess),
      std::logic_error);
}

}  // namespace
}  // namespace butane_windows
