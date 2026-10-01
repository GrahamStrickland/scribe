import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtMultimedia

ApplicationWindow {
    id: root
    width: 1280
    height: 720
    minimumWidth: 960
    minimumHeight: 540
    visible: true
    title: Qt.application.name

    function openFile() {
        if (!recordingController.recording)
            openDialog.open();
    }

    function toggleFullScreen() {
        root.visibility = root.visibility === Window.FullScreen ? Window.Windowed : Window.FullScreen;
    }

    menuBar: MenuBar {
        Menu {
            title: qsTr("&File")

            Action {
                text: qsTr("&Open…")
                shortcut: StandardKey.Open
                enabled: !recordingController.recording
                onTriggered: root.openFile()
            }
            MenuSeparator {}
            Action {
                text: qsTr("&Close")
                shortcut: StandardKey.Close
                onTriggered: root.close()
            }
        }

        Menu {
            title: qsTr("&Window")

            Action {
                text: qsTr("Minimize")
                shortcut: "Ctrl+M"
                onTriggered: root.showMinimized()
            }
            Action {
                text: qsTr("Zoom")
                onTriggered: root.visibility === Window.Maximized ? root.showNormal() : root.showMaximized()
            }
            Action {
                text: qsTr("Toggle Full Screen")
                shortcut: StandardKey.FullScreen
                onTriggered: root.toggleFullScreen()
            }
        }

        Menu {
            title: qsTr("&Help")

            Action {
                text: qsTr("About %1").arg(Qt.application.name)
                onTriggered: aboutDialog.open()
            }
        }
    }

    RecordingController {
        id: recordingController

        onRecordingChanged: {
            // Playback and capture are mutually exclusive.
            if (recordingController.recording) {
                player.stop();
                player.source = "";
            }
        }
        onPermissionDenied: permissionDialog.open()
        onSaveRequested: saveDialog.open()
        onErrorOccurred: message => root.showError(message)
    }

    MediaPlayer {
        id: player

        audioOutput: AudioOutput {
            muted: playbackControl.muted
            volume: playbackControl.volume
        }

        onErrorOccurred: (error, errorString) => root.showError(errorString)
    }

    function showError(message) {
        errorDialog.text = message;
        errorDialog.open();
    }

    FileDialog {
        id: openDialog
        title: qsTr("Please choose an audio file")
        fileMode: FileDialog.OpenFile
        nameFilters: [qsTr("Audio files (*.wav *.aif *.aiff *.caf *.mp3 *.m4a *.aac *.flac)"), qsTr("All files (*)")]
        onAccepted: {
            player.stop();
            player.source = selectedFile;
            player.play();
        }
    }

    FileDialog {
        id: saveDialog
        title: qsTr("Please choose a location to save captured audio file")
        fileMode: FileDialog.SaveFile
        nameFilters: [qsTr("WAV audio (*.wav)")]
        defaultSuffix: "wav"
        onAccepted: recordingController.saveRecording(selectedFile)
    }

    MessageDialog {
        id: permissionDialog
        text: qsTr("System audio access is required to record")
        informativeText: qsTr("Grant %1 access to record system audio in System Settings ▸ Privacy & Security.").arg(Qt.application.name)
        buttons: MessageDialog.Ok
    }

    MessageDialog {
        id: errorDialog
        buttons: MessageDialog.Ok
    }

    MessageDialog {
        id: aboutDialog
        text: Qt.application.name
        informativeText: qsTr("Version %1").arg(Qt.application.version)
        buttons: MessageDialog.Ok
    }

    // Dark "stage" area; double-click toggles full screen.
    Rectangle {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: playbackControl.top
        color: "black"

        TapHandler {
            onDoubleTapped: root.toggleFullScreen()
        }
    }

    PlaybackControl {
        id: playbackControl
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom

        mediaPlayer: player
        recorder: recordingController

        onOpenRequested: root.openFile()
    }
}
