import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import qs

// The picture-in-picture windows: one per workspace, each a live floating view.
//
// State lives in PiP.qml (the bar drives it by dragging a workspace pill down);
// this file only draws them. Drag a view by its header, resize it from the
// corner, switch to the workspace it shows, or close it. Several can be up at
// once — one per workspace.
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

            screen: Util.focusedScreen()
            anchors.top: true
            anchors.left: true
            margins.top: window.box.y
            margins.left: window.box.x
            implicitWidth: window.box.w
            implicitHeight: window.box.h
            color: "transparent"
            // Floating, not reserving space, and never taking the keyboard: this
            // is something you glance at, not something you type into.
            exclusiveZone: -1
            WlrLayershell.namespace: "quickshell-pip"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            Rectangle {
                anchors.fill: parent
                radius: Theme.panelRadius
                color: Theme.panelBg
                border.width: 1
                border.color: Theme.border

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
                        text: "\uf0d9  workspace " + (window.workspace ? window.workspace.name : "?")
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
                                cursorShape: Qt.PointingHandCursor
                                onClicked: PiP.close(window.modelData)
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

                        // mouse.x/y are relative to this item, and the item moves
                        // with the window — using them directly makes the window
                        // chase its own tail, so it visibly lags the cursor.
                        // Deriving the pointer's screen position from the window's
                        // current position cancels that out.
                        property real pressPointerX: 0
                        property real pressPointerY: 0
                        property real pressWindowX: 0
                        property real pressWindowY: 0

                        onPressed: mouse => {
                            pressPointerX = window.box.x + mouse.x;
                            pressPointerY = window.box.y + mouse.y;
                            pressWindowX = window.box.x;
                            pressWindowY = window.box.y;
                        }
                        onPositionChanged: mouse => {
                            if (!pressed)
                                return;
                            const pointerX = window.box.x + mouse.x;
                            const pointerY = window.box.y + mouse.y;
                            PiP.setGeometry(window.modelData, pressWindowX + (pointerX - pressPointerX), pressWindowY + (pointerY - pressPointerY), window.box.w, window.box.h);
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

                        property real pressPointerX: 0
                        property real pressPointerY: 0
                        property real startW: 0
                        property real startH: 0

                        onPressed: mouse => {
                            // Same self-cancelling pointer derivation as the drag
                            // handle: the handle moves with the window, so a raw
                            // mouse delta would undershoot.
                            pressPointerX = window.box.x + window.box.w + mouse.x;
                            pressPointerY = window.box.y + window.box.h + mouse.y;
                            startW = window.box.w;
                            startH = window.box.h;
                        }
                        onPositionChanged: mouse => {
                            if (!pressed)
                                return;
                            const pointerX = window.box.x + window.box.w + mouse.x;
                            const pointerY = window.box.y + window.box.h + mouse.y;
                            PiP.setGeometry(window.modelData, window.box.x, window.box.y, Math.max(240, startW + (pointerX - pressPointerX)), Math.max(180, startH + (pointerY - pressPointerY)));
                        }
                    }
                }
            }
        }
    }
}
