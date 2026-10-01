# scribe

Scribe is a native macOS audio loopback and replay application for audio transcription purposes. 
It is designed purely for personal use and makes use of the 
[macOS Core Audio framework](https://developer.apple.com/documentation/coreaudio) to capture 
system audio with Core Audio taps. The user interface is built with 
[Qt Quick (QML)](https://doc.qt.io/qt-6/qtquick-index.html) and audio file playback uses 
[Qt Multimedia](https://doc.qt.io/qt-6/qtmultimedia-index.html) with its AVFoundation backend.

Scribe has been designed and tested on macOS Tahoe version 26.5 using AppleClang 21.0.0, 
CMake 4.3.2 and Qt 6.12.0 (configure with `-DCMAKE_PREFIX_PATH=<path to Qt>/6.12.0/macos`). 
No attempt is currently being made for backwards compatibility.

Guidance on using `CATapDescription` for Core Audio capture provided by 
[Yingzhong Xu](https://dev.to/yingzhong_xu_20d6f4c5d4ce/from-core-audio-to-llms-native-macos-audio-capture-for-ai-powered-tools-dkg). 
