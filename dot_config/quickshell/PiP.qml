import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import qs

// Picture-in-picture view of another workspace.
//
// A live, floating window onto a workspace you are not on: watch a build, a
// render, a chat, or a video while you work somewhere else. Drag it by its
// header, resize it from the corner, switch to the workspace it shows, or close
// it.
//
// The capture is the workspace's *last focused* window (Hyprland reports that as
// `lastwindow` on the workspace's IPC object), which is the window you would land
// on if you switched — a live view of the workspace's own idea of itself.
Scope {
    id: root

    property bool showing: false
    property int workspaceId: -1

    // Window geometry: anchored top-left so a drag is just a margin change.
    property int windowX: 40
    property int windowY: 56
    property int windowWidth: 420
    property int windowHeight: 300

    readonly property var workspace: {
        const list = Hyprland.workspaces.values;
        for (let i = 0; i < list.length; i++) {
            if (list[i].id === root.workspaceId)
                return list[i];
        }
        return null;
    }

    // The window to capture: the workspace's last focused toplevel, falling back
    // to any window it holds.
    readonly property var target: {
        const ws = root.workspace;
        if (!ws)
            return null;
        const windows = ws.toplevels.values;
        if (windows.length === 0)
            return null;
        const last = ws.lastIpcObject && ws.lastIpcObject.lastwindow ? String(ws.lastIpcObject.lastwindow) : "";
        for (let i = 0; i < windows.length; i++) {
            if (windows[i].address === last)
                return windows[i];
        }
        return windows[windows.length - 1];
    }

    function openFor(id: int): void {
        root.workspaceId = id;
        root.showing = true;
    }

    function toggleFor(id: int): void {
        if (root.showing && root.workspaceId === id)
            root.showing = false;
        else
            root.openFor(id);
    }

    function close(): void {
        root.showing = false;
    }

    function switchTo(): void {
        if (root.workspaceId >= 0)
            Hyprland.dispatch("hl.dsp.focus({workspace = " + root.workspaceId + "})");
    }

    // Workspaces that hold windows and are not the one you are on — the set worth
    // watching.
    readonly property var otherWorkspaces: {
        const list = Hyprland.workspaces.values.slice();
        const out = [];
        for (const ws of list) {
            if (!ws.focused && ws.toplevels.values.length > 0)
                out.push(ws);
        }
        out.sort((a, b) => a.id - b.id);
        return out;
    }

    // The bind's entry point: first press opens the PiP on the next workspace with
    // windows, each further press moves it along, and it closes when there is
    // nothing else to watch.
    function cycleOther(): void {
        const others = root.otherWorkspaces;
        if (others.length === 0) {
            root.close();
            return;
        }
        if (!root.showing) {
            root.openFor(others[0].id);
            return;
        }
        for (let i = 0; i < others.length; i++) {
            if (others[i].id === root.workspaceId) {
                if (i + 1 < others.length) {
                    root.openFor(others[i + 1].id);
                } else {
                    root.close();
                }
                return;
            }
        }
        root.openFor(others[0].id);
    }

    // Cycle the size: three presets are easier to hit than a drag, and the corner
    // handle is there when a preset is not the right shape.
    function cycleSize(): void {
        if (root.windowWidth < 380) {
            root.windowWidth = 420;
            root.windowHeight = 300;
        } else if (root.windowWidth < 560) {
            root.windowWidth = 620;
            root.windowHeight = 420;
        } else {
            root.windowWidth = 320;
            root.windowHeight = 220;
        }
    }

    IpcHandler {
        target: "pip"

        function open(id: int): void {
            root.openFor(id);
        }
        function toggle(id: int): void {
            root.toggleFor(id);
        }
        function close(): void {
            root.close();
        }
        function switchTo(): void {
            root.switchTo();
        }
        function cycleOther(): void {
            root.cycleOther();
        }
    }

    LazyLoader {
        active: root.showing

        PanelWindow {
            id: window

            screen: Util.focusedScreen()
            anchors.top: true
            anchors.left: true
            margins.top: root.windowY
            margins.left: root.windowX
            implicitWidth: root.windowWidth
            implicitHeight: root.windowHeight
            color: "transparent"
            // Floating, not reserving space, and never taking the keyboard: this
            // is something you glance at, not something you type into.
            exclusiveZone: -1
            WlrLayershell.namespace: "quickshell-pip"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            Rectangle {
                id: card

                anchors.fill: parent
                radius: Theme.panelRadius
                color: Theme.panelBg
                border.width: 1
                border.color: Theme.border

                // Same hairline as every other surface, so the PiP reads as part
                // of the shell rather than a stray window.
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
                            color: Theme.alpha(Theme.rampStart, 0.9)
                        }
                        GradientStop {
                            position: 0.6
                            color: Theme.alpha(Theme.rampMid, 0.9)
                        }
                        GradientStop {
                            position: 1.0
                            color: Theme.alpha(Theme.rampEnd, 0.9)
                        }
                    }
                }

                // Header: the drag handle, and the three actions.
                Item {
                    id: header

                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 30

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: "\uf0d9  workspace " + (root.workspace ? root.workspace.name : "?")
                        color: Theme.purple
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSmall
                    }

                    Row {
                        anchors.right: parent.right
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 12

                        Text {
                            text: "\uf061"
                            color: switchHover.hovered ? Theme.green : Theme.comment
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSmall

                            HoverHandler {
                                id: switchHover
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.switchTo()
                            }
                        }

                        Text {
                            text: "\uf065"
                            color: sizeHover.hovered ? Theme.cyan : Theme.comment
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSmall

                            HoverHandler {
                                id: sizeHover
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.cycleSize()
                            }
                        }

                        Text {
                            text: "\uf00d"
                            color: closeHover.hovered ? Theme.red : Theme.comment
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSmall

                            HoverHandler {
                                id: closeHover
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.close()
                            }
                        }
                    }

                    MouseArea {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        anchors.rightMargin: 80
                        cursorShape: Qt.SizeAllCursor
                        drag.target: null

                        property real startX: 0
                        property real startY: 0

                        onPressed: mouse => {
                            startX = root.windowX;
                            startY = root.windowY;
                        }
                        onPositionChanged: mouse => {
                            if (pressed) {
                                root.windowX = Math.max(0, Math.min(screen.width - root.windowWidth, startX + mouse.x));
                                root.windowY = Math.max(44, Math.min(screen.height - root.windowHeight, startY + mouse.y));
                            }
                        }
                    }
                }

                ClippingWrapperRectangle {
                    id: frame

                    anchors.top: header.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: 6
                    radius: Theme.radius
                    color: Theme.alpha("#000000", 0.5)
                    border.width: 1
                    border.color: Theme.alpha(Theme.border, 0.7)

                    Item {
                        anchors.fill: parent

                        ScreencopyView {
                            anchors.fill: parent
                            captureSource: root.target ? root.target.wayland : null
                            live: true
                            constraintSize: Qt.size(root.windowWidth, root.windowHeight)
                            paintCursor: false
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: root.target === null
                            text: "nothing on workspace " + (root.workspace ? root.workspace.name : "?")
                            color: Theme.comment
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSmall
                        }
                    }
                }

                // Corner resize handle.
                Text {
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.rightMargin: 4
                    anchors.bottomMargin: 4
                    text: "\uf0c9"
                    rotation: 90
                    color: resizeArea.containsMouse ? Theme.purple : Theme.alpha(Theme.comment, 0.8)
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall

                    MouseArea {
                        id: resizeArea

                        anchors.fill: parent
                        anchors.margins: -6
                        hoverEnabled: true
                        cursorShape: Qt.SizeFDiagCursor

                        property real startW: 0
                        property real startH: 0

                        onPressed: mouse => {
                            startW = root.windowWidth;
                            startH = root.windowHeight;
                        }
                        onPositionChanged: mouse => {
                            if (pressed) {
                                root.windowWidth = Math.max(240, Math.min(screen.width - root.windowX, startW + mouse.x));
                                root.windowHeight = Math.max(180, Math.min(screen.height - root.windowY, startH + mouse.y));
                            }
                        }
                    }
                }
            }
        }
    }
}
