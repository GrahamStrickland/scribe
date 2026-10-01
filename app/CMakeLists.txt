include(GNUInstallDirs)

# UI-facing wrapper around the capture library plus the ScribeUI QML module.
# Built separately so the test suite can link it without the executable.
add_library(scribe_lib STATIC
    ${CMAKE_CURRENT_SOURCE_DIR}/audiomanager.mm
    ${CMAKE_CURRENT_SOURCE_DIR}/recordingcontroller.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/include/audiomanager.h
    ${CMAKE_CURRENT_SOURCE_DIR}/include/recordingcontroller.h
    ${CMAKE_CURRENT_SOURCE_DIR}/include/timeformatter.h
)
target_include_directories(scribe_lib PUBLIC include)
target_link_libraries(scribe_lib
    PUBLIC audio capture utils Qt6::Core Qt6::Qml
    PRIVATE "-framework AVFoundation"
)
target_compile_options(scribe_lib PRIVATE
    $<$<COMPILE_LANGUAGE:OBJCXX>:-fobjc-arc>
)

qt_add_qml_module(scribe_lib
    URI ScribeUI
    OUTPUT_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/ScribeUI
    QML_FILES
        Main.qml
        controls/AudioControl.qml
        controls/PlaybackControl.qml
        controls/PlaybackSeekControl.qml
    RESOURCES
        images/angle-double-small-left.svg
        images/angle-double-small-right.svg
        images/dot-circle.svg
        images/folder-open.svg
        images/pause-circle.svg
        images/play-circle.svg
        images/stop-circle.svg
        images/volume-slash.svg
        images/volume.svg
)

qt_add_executable(Scribe MACOSX_BUNDLE
    ${CMAKE_CURRENT_SOURCE_DIR}/main.cpp
)
target_compile_definitions(Scribe PRIVATE
    APP_VERSION="${PROJECT_VERSION}"
)
target_link_libraries(Scribe PRIVATE
    scribe_lib
    scribe_libplugin
    Qt6::Gui
    Qt6::Quick
    Qt6::QuickControls2
    Qt6::Svg
    Qt6::Multimedia
)

set_target_properties(Scribe PROPERTIES
    MACOSX_BUNDLE TRUE
    MACOSX_BUNDLE_INFO_PLIST ${CMAKE_CURRENT_SOURCE_DIR}/Info.plist.in
    MACOSX_BUNDLE_BUNDLE_NAME "Scribe"
    MACOSX_BUNDLE_GUI_IDENTIFIER "com.grahamstrickland.scribe"
    MACOSX_BUNDLE_BUNDLE_VERSION "${PROJECT_VERSION}"
    MACOSX_BUNDLE_SHORT_VERSION_STRING "${PROJECT_VERSION}"
)

install(TARGETS Scribe
    BUNDLE DESTINATION .
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
    LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
)

qt_generate_deploy_qml_app_script(
    TARGET Scribe
    OUTPUT_SCRIPT deploy_script
)
install(SCRIPT ${deploy_script})
