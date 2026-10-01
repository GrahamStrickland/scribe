import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Mute toggle and volume slider.
Item {
    id: audioControl

    property alias muted: muteButton.checked
    readonly property real volume: slider.value

    implicitHeight: 40
    implicitWidth: layout.implicitWidth

    RowLayout {
        id: layout
        anchors.verticalCenter: parent.verticalCenter
        spacing: 12

        RoundButton {
            id: muteButton
            Layout.preferredWidth: 40
            Layout.preferredHeight: 40
            radius: 4
            flat: true
            checkable: true
            icon.source: audioControl.muted ? "../images/volume-slash.svg" : "../images/volume.svg"
            icon.width: 24
            icon.height: 24
            icon.color: palette.buttonText
            ToolTip.visible: hovered
            ToolTip.text: audioControl.muted ? qsTr("Unmute") : qsTr("Mute")
        }

        Slider {
            id: slider
            Layout.preferredWidth: 120
            value: 1
        }
    }
}
