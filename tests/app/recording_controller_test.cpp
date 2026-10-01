#include <filesystem>

#include <QUrl>

#include <catch2/catch_test_macros.hpp>

#include "recordingcontroller.h"
#include "timeformatter.h"

namespace fs = std::filesystem;

// startRecording() is not covered: it either needs the interactive permission
// prompt or starts a real capture, which AudioManager's tests already exercise.
TEST_CASE("RecordingController starts idle", "[recording_controller]") {
  RecordingController controller;

  REQUIRE_FALSE(controller.isRecording());
}

TEST_CASE("stopRecording on an idle controller is a no-op",
          "[recording_controller]") {
  RecordingController controller;
  int recordingChanges = 0;
  int saveRequests = 0;
  QObject::connect(&controller, &RecordingController::recordingChanged,
                   [&] { ++recordingChanges; });
  QObject::connect(&controller, &RecordingController::saveRequested,
                   [&] { ++saveRequests; });

  controller.stopRecording();

  REQUIRE_FALSE(controller.isRecording());
  REQUIRE(recordingChanges == 0);
  REQUIRE(saveRequests == 0);
}

TEST_CASE("saveRecording rejects non-local URLs", "[recording_controller]") {
  RecordingController controller;
  QString error;
  QObject::connect(&controller, &RecordingController::errorOccurred,
                   [&](const QString &message) { error = message; });

  REQUIRE_FALSE(
      controller.saveRecording(QUrl("https://example.com/capture.wav")));
  REQUIRE_FALSE(error.isEmpty());
}

TEST_CASE("saveRecording reports write failures", "[recording_controller]") {
  RecordingController controller;
  QString error;
  QObject::connect(&controller, &RecordingController::errorOccurred,
                   [&](const QString &message) { error = message; });

  const fs::path missing =
      fs::temp_directory_path() / "scribe-missing-dir" / "capture.wav";
  REQUIRE_FALSE(fs::exists(missing.parent_path()));

  REQUIRE_FALSE(controller.saveRecording(
      QUrl::fromLocalFile(QString::fromStdString(missing.string()))));
  REQUIRE_FALSE(error.isEmpty());
}

TEST_CASE("TimeFormatter forwards to format_to_minutes", "[time_formatter]") {
  REQUIRE(TimeFormatter::toMinutes(0) == "0:00.000");
  REQUIRE(TimeFormatter::toMinutes(61050) == "1:01.050");
  REQUIRE(TimeFormatter::toMinutes(-5) == "0:00.000");
}
