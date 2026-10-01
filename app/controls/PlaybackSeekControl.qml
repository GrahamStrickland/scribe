import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtMultimedia

import ScribeUI

// Current time, scrub slider, and remaining time.
Item {
    id: seekControl

    required property MediaPlayer mediaPlayer

    implicitHeight: 20

    RowLayout {
        anchors.fill: parent
        spacing: 16

        Label {
            Layout.preferredWidth: 54
            text: TimeFormatter.toMinutes(seekControl.mediaPlayer.position)
            horizontalAlignment: Text.AlignLeft
            font.pixelSize: 11
            font.features: { "tnum": 1 }
            opacity: 0.7
        }

        Slider {
            Layout.fillWidth: true
            value: seekControl.mediaPlayer.duration > 0 ? seekControl.mediaPlayer.position / seekControl.mediaPlayer.duration : 0
            onMoved: seekControl.mediaPlayer.setPosition(value * seekControl.mediaPlayer.duration)
        }

        Label {
            Layout.preferredWidth: 54
            text: TimeFormatter.toMinutes(seekControl.mediaPlayer.duration - seekControl.mediaPlayer.position)
            horizontalAlignment: Text.AlignRight
            font.pixelSize: 11
            font.features: { "tnum": 1 }
            opacity: 0.7
        }
    }
}
