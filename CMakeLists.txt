cmake_minimum_required(VERSION 3.24)
project(Scribe 
    VERSION 0.0.15
    DESCRIPTION "Audio loopback and replay application for transcription"
    HOMEPAGE_URL "https://github.com/GrahamStrickland/scribe"
    LANGUAGES CXX OBJCXX
)

set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

option(SCRIBE_ENABLE_ASAN "Build with AddressSanitizer instrumentation" OFF)

if(SCRIBE_ENABLE_ASAN)
    if(NOT CMAKE_CXX_COMPILER_ID MATCHES "Clang|GNU")
        message(FATAL_ERROR
            "SCRIBE_ENABLE_ASAN requires Clang or GCC, but the compiler is "
            "${CMAKE_CXX_COMPILER_ID}.")
    endif()
    message(STATUS "AddressSanitizer instrumentation enabled")
    add_compile_options(-fsanitize=address -fno-omit-frame-pointer -g)
    add_link_options(-fsanitize=address)
endif()

include(CTest)

# Qt is found here so its imported targets are visible to both app/ and tests/.
find_package(Qt6 6.12 REQUIRED COMPONENTS
    Core
    Gui
    Qml
    Quick
    QuickControls2
    Svg
    Multimedia
)
qt_standard_project_setup(REQUIRES 6.12)

# Libraries
add_subdirectory(utils)
add_subdirectory(audio)
add_subdirectory(capture)
add_subdirectory(playback)

# Executable
add_subdirectory(app)

# Tests
if(BUILD_TESTING)
    add_subdirectory(tests)
endif()
