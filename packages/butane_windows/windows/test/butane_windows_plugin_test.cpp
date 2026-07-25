#include <gtest/gtest.h>

#include <optional>
#include <string>
#include <type_traits>

#include "butane_windows_plugin.h"

namespace butane_windows {
namespace test {

static_assert(std::is_base_of_v<ButaneHostApi, ButaneWindowsPlugin>);
static_assert(std::is_class_v<ButaneFlutterApi>);

TEST(ButaneWindowsPlugin, ValueMethodReturnsUnimplementedError) {
  ButaneWindowsPlugin plugin;
  bool replied = false;
  plugin.State(nullptr, [&replied](ErrorOr<ClientState> reply) {
    replied = true;
    ASSERT_TRUE(reply.has_error());
    EXPECT_EQ(reply.error().code(), "unimplemented");
    EXPECT_EQ(reply.error().message(),
              "state is not implemented on Windows.");
  });
  EXPECT_TRUE(replied);
}

TEST(ButaneWindowsPlugin, VoidMethodReturnsUnimplementedError) {
  ButaneWindowsPlugin plugin;
  bool replied = false;
  plugin.Scan(nullptr, nullptr,
              [&replied](std::optional<FlutterError> reply) {
                replied = true;
                ASSERT_TRUE(reply.has_value());
                EXPECT_EQ(reply->code(), "unimplemented");
                EXPECT_EQ(reply->message(),
                          "scan is not implemented on Windows.");
              });
  EXPECT_TRUE(replied);
}

}  // namespace test
}  // namespace butane_windows
