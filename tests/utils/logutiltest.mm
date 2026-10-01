#include <catch2/catch_test_macros.hpp>

#include "logutil.h"

// ScribeLog only emits to the unified logging system, so there is no return
// value to assert on. These smoke tests verify it accepts every os_log type and
// the default argument without crashing.
TEST_CASE("ScribeLog emits without crashing for every type", "[logutil]") {
  REQUIRE_NOTHROW(scribe_log("LogUtilTest", "default type message"));
  REQUIRE_NOTHROW(scribe_log("LogUtilTest", "info message", OS_LOG_TYPE_INFO));
  REQUIRE_NOTHROW(
      scribe_log("LogUtilTest", "debug message", OS_LOG_TYPE_DEBUG));
  REQUIRE_NOTHROW(
      scribe_log("LogUtilTest", "error message", OS_LOG_TYPE_ERROR));
  REQUIRE_NOTHROW(
      scribe_log("LogUtilTest", "fault message", OS_LOG_TYPE_FAULT));
}

TEST_CASE("ScribeLog reuses the log object for a repeated component",
          "[logutil]") {
  REQUIRE_NOTHROW(scribe_log("RepeatedComponent", "first message"));
  REQUIRE_NOTHROW(scribe_log("RepeatedComponent", "second message"));
}
