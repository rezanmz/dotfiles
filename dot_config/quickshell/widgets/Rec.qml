import QtQuick
import qs
import Quickshell

// Recording indicator.
//
// Only exists while a recording is running: a red pill with a pulsing dot, so a
// forgotten `wf-recorder` cannot go unnoticed. Clicking it stops the recording
// through Recorder — the same SIGINT path the toolbar and the keybind use. It
// sits at the far right of the bar, after the clock: the menu-bar position of
// the macOS stop button it stands in for.
BarItem {
    id: root

    readonly property bool active: Recorder.recording

    // In the bar's RowLayout an invisible item is not laid out at all, so idle
    // costs zero width — "visible only while recording", literally.
    visible: root.active

    // Collapse the whole item when idle: an invisible item is not laid out in the
    // bar's RowLayout and a later visible flip does not reliably re-run it, so the
    // pill used to appear in the wrong place. Sizing from the label keeps this out
    // of BarItem's binding-loop territory.
    implicitWidth: root.active ? label.implicitWidth + 14 + Theme.modulePadding * 2 : 0

    onClicked: Recorder.stop()

    // The content collapses to nothing when idle, so the bar does not reserve
    // space for a state that is usually off. (Sizing the BarItem itself from its
    // own content is a binding loop — BarItem measures the content it is given.)
    //
    // The pill fills its wrapper exactly, and the wrapper is hidden when idle.
    // That last part matters: a Text paints its string regardless of its
    // parent's size, so a label inside a zero-size pill still draws " REC" over
    // the neighbouring icons — which is exactly how the earlier version
    // overlapped the clock. Clipping the pill is the belt to that braces.
    Item {
        visible: root.active
        implicitWidth: root.active ? pillLabel.implicitWidth + 14 : 0
        implicitHeight: root.active ? 22 : 0
        width: implicitWidth
        height: implicitHeight

        Rectangle {
            id: pill

            anchors.fill: parent
            clip: true
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
                id: pillLabel

                anchors.centerIn: parent
                text: "  REC"
                color: Theme.red
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                font.bold: true
            }
        }
    }
}
