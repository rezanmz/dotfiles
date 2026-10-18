import QtQuick
import qs
import Quickshell

// Recording indicator.
//
// Only exists while a recording is running: a red pill with a pulsing dot, so a
// forgotten `wf-recorder` cannot go unnoticed. Clicking it stops the recording
// through the same script the keybind uses.
BarItem {
    id: root

    readonly property bool active: Recorder.recording

    onClicked: Recorder.stop()

    // The content collapses to nothing when idle, so the bar does not reserve
    // space for a state that is usually off. (Sizing the BarItem itself from its
    // own content is a binding loop — BarItem measures the content it is given.)
    Item {
        implicitWidth: root.active ? label.implicitWidth + 14 : 0
        implicitHeight: root.active ? 22 : 0

        Rectangle {
            id: pill

            anchors.centerIn: parent
            width: parent.implicitWidth
            height: parent.implicitHeight
            radius: Theme.radiusPill
            color: Theme.alpha(Theme.red, 0.16)
            border.width: 1
            border.color: Theme.alpha(Theme.red, 0.7)

            SequentialAnimation on opacity {
                running: root.active
                loops: Animation.Infinite
                NumberAnimation {
                    to: 0.45
                    duration: 800
                }
                NumberAnimation {
                    to: 1
                    duration: 800
                }
            }

            Text {
                id: label

                anchors.centerIn: parent
                text: "\uf111  REC"
                color: Theme.red
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                font.bold: true
            }
        }
    }
}
