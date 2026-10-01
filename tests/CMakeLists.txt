# Catch2 tests
include(FetchContent)

FetchContent_Declare(
  Catch2
  GIT_REPOSITORY https://github.com/catchorg/Catch2.git
  GIT_TAG        6ee0826dcae55ed1e06b2c5701981221e979e1e6 # v3.15.0
  FIND_PACKAGE_ARGS
)

FetchContent_MakeAvailable(Catch2)
list(APPEND CMAKE_MODULE_PATH ${catch2_SOURCE_DIR}/extras)
include(Catch)

add_executable(logutil_test utils/logutiltest.mm)
target_link_libraries(logutil_test Catch2::Catch2WithMain utils)
catch_discover_tests(logutil_test)

add_executable(time_format_test utils/time_format_test.cpp)
target_link_libraries(time_format_test Catch2::Catch2WithMain utils)
catch_discover_tests(time_format_test)

add_executable(audio_test audio/audiotest.cpp)
target_link_libraries(audio_test Catch2::Catch2WithMain audio)
catch_discover_tests(audio_test)

add_executable(audio_capture_manager_test capture/audiocapturemanagertest.mm)
target_link_libraries(audio_capture_manager_test Catch2::Catch2WithMain capture)
catch_discover_tests(audio_capture_manager_test)

add_executable(playback_test playback/playbacktest.cpp)
target_link_libraries(playback_test Catch2::Catch2WithMain playback)
catch_discover_tests(playback_test)

# App (QML UI) tests
add_executable(audio_manager_test app/audio_manager_test.cpp)
target_link_libraries(audio_manager_test Catch2::Catch2WithMain scribe_lib)
catch_discover_tests(audio_manager_test)

add_executable(recording_controller_test app/recording_controller_test.cpp)
target_link_libraries(recording_controller_test Catch2::Catch2WithMain scribe_lib)
catch_discover_tests(recording_controller_test)

# Loads the full ScribeUI module offscreen to catch QML errors at test time.
add_executable(qml_load_test app/qml_load_test.cpp)
target_link_libraries(qml_load_test
    Catch2::Catch2WithMain
    scribe_lib
    scribe_libplugin
    Qt6::Gui
    Qt6::Quick
    Qt6::QuickControls2
    Qt6::Svg
    Qt6::Multimedia
)
catch_discover_tests(qml_load_test
    PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_MEDIA_BACKEND=darwin"
)
