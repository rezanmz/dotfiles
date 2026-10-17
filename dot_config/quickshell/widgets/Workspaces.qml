import QtQuick
import qs
import Quickshell
import Quickshell.Hyprland

// Workspace pills.
//
// Only workspaces that exist are shown — an empty workspace that has been
// visited is clutter, which is how the waybar module was configured before
// (`all-outputs: true`, dynamic list). Clicking a pill switches to it through
// HyprlandWorkspace.activate(), which avoids building a dispatch string: this
// machine runs Hyprland's Lua config, where `hyprctl dispatch` parses Lua
// rather than the classic dispatcher syntax.
Item {
    id: root

    readonly property var visibleWorkspaces: {
        const out = [];
        const values = Hyprland.workspaces.values;
        for (let i = 0; i < values.length; i++) {
            const ws = values[i];
            if (ws.toplevels.values.length > 0 || ws.focused)
                out.push(ws);
        }
        out.sort((a, b) => a.id - b.id);
        return out;
    }

    implicitWidth: row.implicitWidth + Theme.margin * 2
    implicitHeight: Theme.barHeight

    Row {
        id: row

        anchors.centerIn: parent
        spacing: 6

        Repeater {
            model: root.visibleWorkspaces

            delegate: Rectangle {
                id: pill

                required property var modelData

                readonly property bool focused: modelData.focused
                readonly property bool urgent: modelData.urgent
                // A dot marks workspaces that actually hold windows, so an empty
                // workspace you have visited is distinguishable from a live one
                // without reading the number twice.
                readonly property bool occupied: modelData.toplevels.values.length > 0

                implicitWidth: label.implicitWidth + 20
                height: Theme.barHeight - 10
                anchors.verticalCenter: parent.verticalCenter
                radius: Theme.radius
                color: urgent ? Theme.red : (focused ? Theme.purple : (hover.hovered ? Theme.selection : "transparent"))
                scale: hover.hovered && !focused ? 1.06 : 1.0

                Behavior on color {
                    ColorAnimation {
                        duration: Theme.animationFast
                    }
                }
                Behavior on scale {
                    NumberAnimation {
                        duration: Theme.animationFast
                        easing.type: Easing.OutCubic
                    }
                }

                // Urgent is the one state worth animating: something on that
                // workspace is asking for attention.
                SequentialAnimation on opacity {
                    running: pill.urgent
                    loops: Animation.Infinite
                    NumberAnimation {
                        to: 0.5
                        duration: 450
                    }
                    NumberAnimation {
                        to: 1
                        duration: 450
                    }
                }

                Text {
                    id: label

                    anchors.centerIn: parent
                    text: pill.modelData.name
                    color: pill.focused ? Theme.bg : Theme.comment
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                }

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 3
                    width: 4
                    height: 4
                    radius: 2
                    visible: pill.occupied && !pill.focused
                    color: Theme.alpha(Theme.fg, 0.45)
                }

                HoverHandler {
                    id: hover
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: pill.modelData.activate()
                }
            }
        }
    }
}
