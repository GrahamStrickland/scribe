import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtMultimedia

import ScribeUI

// Transport bar: seek row with time labels, then file/record, playback, and
// volume/mute controls.
Item {
    id: playbackControl

    required property MediaPlayer mediaPlayer
    required property RecordingController recorder

    property alias muted: audioControl.muted
    property alias volume: audioControl.volume

    readonly property bool hasMedia: mediaPlayer.mediaStatus !== MediaPlayer.NoMedia && mediaPlayer.mediaStatus !== MediaPlayer.InvalidMedia
    readonly property bool playbackEnabled: hasMedia && !recorder.recording

    signal openRequested

    implicitHeight: 168

    function skipBy(milliseconds) {
        const position = mediaPlayer.position + milliseconds;
        mediaPlayer.setPosition(Math.max(0, Math.min(position, mediaPlayer.duration)));
    }

    component TransportButton: RoundButton {
        Layout.preferredWidth: 40
        Layout.preferredHeight: 40
        radius: 20
        icon.width: 24
        icon.height: 24
        icon.color: palette.buttonText
    }

    Frame {
        anchors.fill: parent
        padding: 32
        topPadding: 28

        ColumnLayout {
            anchors.fill: parent
            spacing: 16

            PlaybackSeekControl {
                Layout.fillWidth: true
                mediaPlayer: playbackControl.mediaPlayer
                enabled: playbackControl.playbackEnabled
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                implicitHeight: 40

                RowLayout {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 12

                    TransportButton {
                        icon.source: "../images/folder-open.svg"
                        enabled: !playbackControl.recorder.recording
                        ToolTip.visible: hovered
                        ToolTip.text: qsTr("Open")
                        onClicked: playbackControl.openRequested()
                    }

                    TransportButton {
                        icon.source: playbackControl.recorder.recording ? "../images/stop-circle.svg" : "../images/dot-circle.svg"
                        ToolTip.visible: hovered
                        ToolTip.text: playbackControl.recorder.recording ? qsTr("Stop Recording") : qsTr("Record")
                        onClicked: playbackControl.recorder.toggleRecording()
                    }
                }

                RowLayout {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 16
                    enabled: playbackControl.playbackEnabled

                    TransportButton {
                        icon.source: "../images/angle-double-small-left.svg"
                        ToolTip.visible: hovered
                        ToolTip.text: qsTr("Back 10s")
                        onClicked: playbackControl.skipBy(-10000)
                    }

                    TransportButton {
                        readonly property bool playing: playbackControl.mediaPlayer.playbackState === MediaPlayer.PlayingState
                        icon.source: playing ? "../images/pause-circle.svg" : "../images/play-circle.svg"
                        ToolTip.visible: hovered
                        ToolTip.text: playing ? qsTr("Pause") : qsTr("Play")
                        onClicked: playing ? playbackControl.mediaPlayer.pause() : playbackControl.mediaPlayer.play()
                    }

                    TransportButton {
                        icon.source: "../images/angle-double-small-right.svg"
                        ToolTip.visible: hovered
                        ToolTip.text: qsTr("Forward 10s")
                        onClicked: playbackControl.skipBy(10000)
                    }
                }

                AudioControl {
                    id: audioControl
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    enabled: !playbackControl.recorder.recording
                }
            }
        }
    }
}
