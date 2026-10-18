import QtQuick
import qs
import Quickshell

// The recording indicator: macOS's menu-bar Stop button.
//
// Only exists while a recording runs: a red pill with the stop symbol (the
// circle-and-square macOS puts in the menu bar), the REC state and the elapsed
// time counting up in mm:ss — so a forgotten `wf-recorder` cannot go unnoticed,
// and the button tells you how long it has been running. Clicking anywhere on
// the pill stops the recording through Capture — the same SIGINT path the
// toolbar and the keybind use. Hovering brightens the pill and shows the
// pointing hand, the hint that it is a button. It sits at the far right of the
// bar, after the clock: the menu-bar position of the button it stands in for.
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
    implicitWidth: root.active ? pillLabel.implicitWidth + 14 + Theme.modulePadding * 2 : 0

    // "mm:ss" from Recorder's whole-second counter (pad2 on both sides: the
    // minutes field is two digits too, until it outgrows them).
    readonly property string elapsedText: Util.pad2(Math.floor(Recorder.elapsed / 60)) + ":" + Util.pad2(Recorder.elapsed % 60)

    // BarItem's MouseArea covers the whole wrapper (it is the topmost input
    // item), so the stop lives here and the whole pill is the hit target.
    onClicked: Capture.toggleRecording()

    HoverHandler {
        id: pillHover
    }

    // ---- the pill -----------------------------------------------------
    // The content collapses to nothing when idle, so the bar does not reserve
    // space for a state that is usually off. (Sizing the BarItem itself from its
    // own content is a binding loop — BarItem measures the content it is given.)
    //
    // The pill fills its wrapper exactly, and the wrapper is hidden when idle.
    // That last part matters: a Text paints its string regardless of its
    // parent's size, so a label inside a zero-size pill still draws over the
    // neighbouring icons — which is exactly how the earlier version overlapped
    // the clock. Clipping the pill is the belt to that braces.
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
            // The hover hint: the border comes up solid red under the pointer.
            border.color: pillHover.hovered ? Theme.red : Theme.alpha(Theme.red, 0.7)

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
                // The stop symbol is the circle-and-square U+F28D
                // (fa-stop_circle), the Hack Nerd Font point for it — literal
                // U+23F9 "⏹" is not in the font and would fall back to another
                // one mid-label. Built from the codepoint, like Battery.qml's
                // glyphs.
                text: String.fromCodePoint(0xF28D) + "  REC  " + root.elapsedText
                color: Theme.red
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                font.bold: true
            }
        }

        // The whole pill is the hit target, not just the glyph. Belt to the
        // braces: if BarItem's wrapper MouseArea ever stops covering the pill,
        // the pill still takes the click itself (kept above the wrapper).
        MouseArea {
            z: 100
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: Capture.toggleRecording()
        }
    }
}
