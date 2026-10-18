import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs

// The floating thumbnail's right-click menu (ScreenshotThumb.qml), drawn by the
// shell like the tray menu (TrayMenu.qml + panels/Tray.qml) — not a platform
// menu, which would need QApplication mode and look nothing like the rest of
// the desktop.
//
// It is its own window and not a guest in the thumbnail's: the thumbnail's
// input region must stay exactly its card. The window is the whole screen and
// takes every click that is not on a row — a real menu's grab swallows clicks
// the same way — and the keyboard at map time (a layer surface cannot be handed
// the keyboard after it is already up), so Escape closes it like any other
// menu. A focus change with no click at all — a workspace switch from a keybind
// while the menu is up — clears the Hyprland focus grab and closes it too.
PanelWindow {
    id: root

    // Distance from the screen's bottom edge to the menu card's: the thumbnail
    // card's top edge plus a gap, so the menu grows up out of the thumbnail.
    property int lift: 0

    // A recording: no "Open in Markup" row — satty annotates images, not video.
    readonly property bool video: Capture.thumbVideo

    // The "Save As…" level, the tray menu's drill-down inside one window.
    property string level: "root"

    // What was chosen. ScreenshotThumb.qml owns the thumbnail's lifetime and
    // the file commands; this only reports choices. Every choice closes the
    // menu.
    signal dismissed()
    signal copyChosen()
    signal markupChosen()
    signal revealChosen()
    signal saveChosen(string dir)
    signal deleteChosen()

    function closeMenu(): void {
        root.dismissed();
    }

    screen: Util.focusedScreen()
    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true
    color: "transparent"
    exclusiveZone: -1
    WlrLayershell.namespace: "quickshell-thumb-menu"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    focusable: true

    HyprlandFocusGrab {
        windows: [root]
        active: true
        onCleared: root.closeMenu()
    }

    // Click-away: everything that is not a row is dismiss area, under the card
    // in the stacking order so the card wins where the two overlap.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onClicked: root.closeMenu()
    }

    // One menu row: glyph column, label, drill-down arrow — the tray menu's row
    // geometry, so the two menus read as one menu style.
    component Entry: Rectangle {
        id: entry

        property alias text: label.text
        property alias glyph: icon.text
        property color glyphColor: Theme.purple
        property color accent: Theme.fg
        property bool arrow: false
        signal chosen()

        width: parent.width
        height: 26
        radius: Theme.radius
        color: hover.hovered ? Theme.alpha(Theme.selection, 0.85) : "transparent"
        Behavior on color {
            ColorAnimation {
                duration: Theme.animationFast
            }
        }

        Text {
            id: icon

            anchors.left: parent.left
            anchors.leftMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            width: 16
            color: entry.glyphColor
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
        }

        Text {
            id: label

            anchors.left: icon.right
            anchors.leftMargin: 4
            anchors.right: arrow.left
            anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
            color: entry.accent
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
        }

        Text {
            id: arrow

            anchors.right: parent.right
            anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            visible: entry.arrow
            text: "\uf105"
            color: Theme.comment
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
        }

        HoverHandler {
            id: hover
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: entry.chosen()
        }
    }

    Rectangle {
        id: card

        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: Theme.margin * 2
        anchors.bottomMargin: root.lift
        width: 264
        height: column.implicitHeight + Theme.panelPadding * 2
        radius: Theme.panelRadius
        color: Theme.panelBg
        border.width: 1
        border.color: Theme.border

        // Escape closes the menu. The window takes the keyboard at map time and
        // this card takes the focus, the capture toolbar's pattern
        // (panels/Capture.qml).
        focus: true
        Keys.onEscapePressed: root.closeMenu()
        Component.onCompleted: forceActiveFocus()

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

        Column {
            id: column

            anchors.fill: parent
            anchors.margins: Theme.panelPadding
            spacing: 2

            Entry {
                text: "Copy to Clipboard"
                glyph: "\uf0c5"
                visible: root.level === "root"
                onChosen: root.copyChosen()
            }

            Entry {
                text: "Open in Markup"
                glyph: "\uf1fc"
                visible: root.level === "root" && !root.video
                onChosen: root.markupChosen()
            }

            Entry {
                text: "Reveal in File Manager"
                glyph: "\uf07b"
                visible: root.level === "root"
                onChosen: root.revealChosen()
            }

            Entry {
                text: "Save As…"
                glyph: "\uf0c7"
                arrow: true
                visible: root.level === "root"
                onChosen: root.level = "save"
            }

            // Back row, only inside the Save As… level.
            Entry {
                text: "back"
                glyph: "\uf104"
                glyphColor: Theme.purple
                accent: Theme.comment
                visible: root.level !== "root"
                onChosen: root.level = "root"
            }

            Entry {
                text: "Desktop"
                glyph: "\uf07b"
                visible: root.level === "save"
                onChosen: root.saveChosen(Quickshell.env("HOME") + "/Desktop")
            }

            Entry {
                text: "Documents"
                glyph: "\uf07b"
                visible: root.level === "save"
                onChosen: root.saveChosen(Quickshell.env("HOME") + "/Documents")
            }

            Entry {
                text: "Pictures"
                glyph: "\uf07b"
                visible: root.level === "save"
                onChosen: root.saveChosen(Quickshell.env("HOME") + "/Pictures")
            }

            Rectangle {
                width: parent.width
                height: 9
                color: "transparent"

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    height: 1
                    color: Theme.border
                }
            }

            Entry {
                text: "Delete"
                glyph: "\uf1f8"
                glyphColor: Theme.red
                accent: Theme.red
                visible: root.level === "root"
                onChosen: root.deleteChosen()
            }
        }
    }
}
