import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import qs

// The picture-in-picture windows: one per workspace, each a live floating view.
//
// State lives in PiP.qml (the bar drives it by dragging a workspace pill down);
// this file only draws them.
//
// WHY THE WINDOW IS FULL-SCREEN AND THE CARD MOVES INSIDE IT
// A layer surface's position is set by its margins, and the compositor applies
// them asynchronously. If the drag derives the pointer position from the window's
// own position (which is what a small moving window forces you to do), the stale
// position is added to the delta again on the next event and the window runs away
// from the cursor. With a full-screen window the surface never moves, so
// mouse.x/mouse.y ARE screen coordinates and a drag tracks the pointer exactly.
// The input region (`mask`) is the card, so everything outside it still belongs to
// whatever is underneath.
Scope {
    id: root

    Variants {
        model: PiP.previews

        delegate: PanelWindow {
            id: window

            required property int modelData

            readonly property var box: PiP.geometry[modelData] !== undefined ? PiP.geometry[modelData] : {
                "x": 40,
                "y": 56,
                "w": PiP.defaultWidth,
                "h": PiP.defaultHeight
            }

            readonly property var target: PiP.targetFor(modelData)
            readonly property var workspace: PiP.workspaceFor(modelData)

            // Header strip height, and the size of the corner grab area.
            readonly property int headerHeight: 30
            readonly property int cornerSize: 22

            function inHeader(x: real, y: real): bool {
                return x >= window.box.x && x <= window.box.x + window.box.w && y >= window.box.y && y <= window.box.y + window.headerHeight;
            }

            function inCorner(x: real, y: real): bool {
                return x >= window.box.x + window.box.w - window.cornerSize && x <= window.box.x + window.box.w && y >= window.box.y + window.box.h - window.cornerSize && y <= window.box.y + window.box.h;
            }

            screen: Util.focusedScreen()
            anchors.top: true
            anchors.left: true
            anchors.right: true
            anchors.bottom: true
            color: "transparent"
            // Floating, not reserving space, and never taking the keyboard: this
            // is something you glance at, not something you type into.
            exclusiveZone: -1
            WlrLayershell.namespace: "quickshell-pip"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            // Input only where the card is drawn.
            mask: Region {
                shape: RegionShape.Rect
                x: window.box.x
                y: window.box.y
                width: window.box.w
                height: window.box.h
                radius: Theme.panelRadius
            }

            // Drag and resize. Declared before the card so the card's own buttons
            // (which are click targets, not motion handlers) sit on top of it; a
            // plain Rectangle does not consume presses, so a press on the card's
            // body still lands here.
            MouseArea {
                id: dragArea

                anchors.fill: parent

                // 0 = idle, 1 = moving the card, 2 = resizing it.
                property int mode: 0
                property real grabDX: 0
                property real grabDY: 0

                cursorShape: window.inCorner(mouseX, mouseY) ? Qt.SizeFDiagCursor : (window.inHeader(mouseX, mouseY) ? Qt.SizeAllCursor : Qt.ArrowCursor)


                onPressed: mouse => {
                    if (window.inCorner(mouse.x, mouse.y)) {
                        dragArea.mode = 2;
                    } else if (window.inHeader(mouse.x, mouse.y)) {
                        dragArea.mode = 1;
                        dragArea.grabDX = mouse.x - window.box.x;
                        dragArea.grabDY = mouse.y - window.box.y;
                    } else {
                        dragArea.mode = 0;
                    }
                }
                onPositionChanged: mouse => {
                    console.log("PDRAG2 mode=" + dragArea.mode + " mouse=" + Math.round(mouse.x) + "," + Math.round(mouse.y) + " box=" + Math.round(window.box.x) + "," + Math.round(window.box.y) + " grab=" + Math.round(dragArea.grabDX) + "," + Math.round(dragArea.grabDY));  // TEMPORARY
                    if (dragArea.mode === 1)
                        PiP.setGeometry(window.modelData, mouse.x - dragArea.grabDX, mouse.y - dragArea.grabDY, window.box.w, window.box.h);
                    else if (dragArea.mode === 2)
                        PiP.setGeometry(window.modelData, window.box.x, window.box.y, Math.max(240, mouse.x - window.box.x), Math.max(180, mouse.y - window.box.y));
                }
                onReleased: dragArea.mode = 0
                onCanceled: dragArea.mode = 0
            }

            Rectangle {
                id: card

                x: window.box.x
                y: window.box.y
                width: window.box.w
                height: window.box.h
                radius: Theme.panelRadius
                color: Theme.panelBg
                border.width: 1
                border.color: Theme.border

                Behavior on x {
                    enabled: dragArea.mode !== 1
                    NumberAnimation {
                        duration: Theme.animationFast
                    }
                }
                Behavior on y {
                    enabled: dragArea.mode !== 1
                    NumberAnimation {
                        duration: Theme.animationFast
                    }
                }

                // Same hairline as every other surface, so a preview reads as
                // part of the shell rather than a stray window.
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

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    anchors.top: parent.top
                    anchors.topMargin: 8
                    text: "\uf0d9  workspace " + (window.workspace ? window.workspace.name : "?")
                    color: Theme.purple
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                }

                Row {
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    anchors.top: parent.top
                    anchors.topMargin: 8
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
                            anchors.margins: -4
                            cursorShape: Qt.PointingHandCursor
                            onClicked: PiP.switchTo(window.modelData)
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
                            anchors.margins: -4
                            cursorShape: Qt.PointingHandCursor
                            onClicked: PiP.cycleSize(window.modelData)
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
                            anchors.margins: -4
                            cursorShape: Qt.PointingHandCursor
                            onClicked: PiP.close(window.modelData)
                        }
                    }
                }

                ClippingWrapperRectangle {
                    id: frame

                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: 6
                    anchors.topMargin: window.headerHeight
                    radius: Theme.radius
                    color: Theme.alpha("#000000", 0.5)
                    border.width: 1
                    border.color: Theme.alpha(Theme.border, 0.7)

                    Item {
                        anchors.fill: parent

                        ScreencopyView {
                            anchors.fill: parent
                            captureSource: window.target ? window.target.wayland : null
                            live: true
                            constraintSize: Qt.size(window.box.w, window.box.h)
                            paintCursor: false
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: window.target === null
                            text: "nothing on workspace " + (window.workspace ? window.workspace.name : "?")
                            color: Theme.comment
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSmall
                        }
                    }
                }

                // Corner resize hint; the grab area itself is the full-screen
                // MouseArea above, so this is decoration.
                Text {
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.rightMargin: 4
                    anchors.bottomMargin: 4
                    text: "\uf0c9"
                    rotation: 90
                    color: window.inCorner(dragArea.mouseX, dragArea.mouseY) ? Theme.purple : Theme.alpha(Theme.comment, 0.8)
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                }
            }
        }
    }
}
