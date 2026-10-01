# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.0.14] - 2026-10-01

### Added

- `setAudioFormatCallback` on `AudioCaptureManager` to be used by `audio_manager`

### Fixed

- Wrong format in saved recordings in `capture/audiocapturemanager.mm`
- Reading past the buffer in `audio/audioengine.cpp`

## [0.0.13] - 2026-08-25

### Fixed

- Another mismatch in capture permissions

## [0.0.12] - 2026-08-22

### Fixed

- Mismatch in capture permissions causing audio capture to fail

### Added

- `audio_engine` for storing PCM audio data and saving to `.wav` file
- `.wav` file saving via dialog

## [0.0.11] - 2026-07-25

### Changed

- Moved PIMPL idom from `capture` module into `AudioManager` in `app` module

## [0.0.10] - 2026-07-24

### Changed

- Application renamed to Scribe

## [0.0.9] - 2026-07-24

### Removed

- LGPL license from project

## [0.0.8] - 2026-07-22

### Fixed

- `nil` pointer causing `SEGV` in `capture` module in CI workflow

## [0.0.7] - 2026-07-22

### Added

- `AddressSanitizer` build option to CMake setup
- `AddressSanitizer` tests to CI workflow
- `start/stopCapture` plumbing in `AudioPlaybackController`

### Fixed

- Bug with `_audioDataCallback` not being released in `AudioCaptureManager`

## [0.0.6] - 2026-07-10

### Changed

- Moved logging to `util` library and added `os_log` routing for app logs alongside
  ANSI terminal logging in debug builds.

## [0.0.5] - 2026-07-07

### Changed

- Added `startRecording`/`stopRecording` stubs with UI functionality to 
  to `PlaybackControlView`

## [0.0.4] - 2026-06-28

### Changed

- Replaced the Qt6/QML user interface with a native macOS AppKit UI written in
  Objective-C++ (`main.mm`, `AppDelegate`, `MainWindowController`,
  `PlaybackControlView`)
- Replaced Qt Multimedia `MediaPlayer` with an AVFoundation-backed
  `PlaybackEngine` (`AVAudioPlayer`) for audio file playback
- Replaced bundled SVG icons with native SF Symbols
- Rewrote `AudioManager` as a plain Objective-C++ wrapper (no `QObject`),
  marshalling the permission callback to the main queue via Grand Central Dispatch
- Dropped all Qt6 dependencies from the build; `Scribe` now links AppKit,
  AVFoundation, and UniformTypeIdentifiers directly

### Removed

- Qt6/QML UI files, bundled SVG assets, and Qt-based tests

### Added

- `format_to_minutes` time-formatting utility with Catch2 coverage (extracted
  from `PlaybackSeekControl.qml`)

## [0.0.3] - 2026-05-24

### Added

- Permission request when record button pressed in QML UI
- utils library to tests for permission status validation 

## [0.0.2] - 2026-05-23

### Added

- Project description, homepage URL and `SPDX_LICENSE` to CMakeLists.txt
- capture module setup with permissions checking
- Basic QML interface for audio playback

### Fixed

- QML include errors caused by `MACOS_BUNDLE_POST_BUILD` in app/CMakeLists.txt

### Changed

- Application/project name from "appscribe" to "Scribe"
- QML module to `ScribeUI` in scribe_lib for QML testing
- Millisecond formatting to M:SS:mmm in `PlaybackSeekControl`

## [0.0.1] - 2026-05-17

### Added

- Initial project setup
- app, audio, capture, playback, qml, and tests modules
- LGPL v3 license
