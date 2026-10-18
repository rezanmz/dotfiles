import QtQuick
import Quickshell
import Quickshell.Wayland
import qs

// The floating thumbnail macOS shows after a capture.
//
// Bottom-right, the captured image at ~180px, gone after five seconds. Click
// it to annotate — satty opens on the file, which is where annotation lives
// now (the old scripts froze the screen and opened satty inline) — or hit the
// ✕ to dismiss it. A clipboard capture shows here too, from a temp file that
// is deleted with the thumbnail (see Capture.qml).
//
// The window is exactly the card and its input region is the card, so every
// click outside it still belongs to whatever is underneath.
PanelWindow {
    id: root

    screen: Util.focusedScreen()
    anchors.bottom: true
    anchors.right: true
    implicitWidth: card.width
    implicitHeight: card.height
    margins.right: Theme.margin * 2
    margins.bottom: Theme.margin * 2
    color: "transparent"
    exclusiveZone: -1
    WlrLayershell.namespace: "quickshell-thumb"
    WlrLayershell.layer: WlrLayer.Overlay
    // Never takes the keyboard: this is something you glance at, not
    // something you type into.
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    mask: Region {
        shape: RegionShape.Rect
        x: 0
        y: 0
        width: card.width
        height: card.height
        radius: Theme.panelRadius
    }

    // Auto-hide: five seconds, like macOS (which also lets you slide the
    // thumbnail away — the ✕ here).
    Timer {
        interval: 5000
        running: true
        onTriggered: Capture.dismissThumb()
    }

    Rectangle {
        id: card

        width: img.width + Theme.panelPadding * 2
        height: img.height + Theme.panelPadding * 2
        radius: Theme.panelRadius
        color: Theme.panelBg
        border.width: 1
        border.color: Theme.border

        // Same hairline as every surface in the shell (see Theme.rampStart).
        Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: 1
            height: 2
            radius: parent.radius
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop {
                    position: 0.0
                    color: Theme.alpha(Theme.rampStart, 0.0)
                }
                GradientStop {
                    position: 0.25
                    color: Theme.alpha(Theme.rampStart, 0.9)
                }
                GradientStop {
                    position: 0.6
                    color: Theme.alpha(Theme.rampMid, 0.9)
                }
                GradientStop {
                    position: 1.0
                    color: Theme.alpha(Theme.rampEnd, 0.0)
                }
            }
        }

        // ~180px wide, decoded at 4x so it stays sharp on the scaled output.
        Image {
            id: img

            anchors.centerIn: parent
            source: "file://" + Capture.thumbPath
            sourceSize.width: 720
            width: 180
            height: implicitWidth > 0 ? 180 * implicitHeight / implicitWidth : 101
            fillMode: Image.PreserveAspectFit

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: Capture.annotate()
            }
        }

        // Dismiss. Declared after the image so its click wins the corner.
        Rectangle {
            id: closeBtn

            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: 4
            width: 22
            height: 22
            radius: Theme.radiusPill
            color: closeHover.hovered ? Theme.alpha(Theme.red, 0.85) : Theme.alpha(Theme.bg, 0.75)
            border.width: 1
            border.color: Theme.alpha(Theme.red, 0.6)

            Text {
                anchors.centerIn: parent
                text: "✕"
                color: Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
            }

            HoverHandler {
                id: closeHover
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: Capture.dismissThumb()
            }
        }
    }
}
