import QtQuick
import qs
import Quickshell
import Quickshell.DBusMenu

// Tray item menu, drawn in the shell's own style.
//
// SystemTrayItem.display() hands the DBusMenu to Qt, which draws a platform menu
// — square corners, system font, no theme — and needs QApplication mode to work
// at all. Reading the same menu through QsMenuOpener and drawing it here keeps the
// shell consistent, and gives the menu the same hover, radius and hairline as
// every other surface.
//
// One level at a time: a row with children drills in and a "back" row appears,
// instead of spawning a second window that has to chase the pointer.
Popup {
    id: root

    name: "tray"
    contentWidth: 268

    // The menu level being shown. Rebound as TrayMenu drills in and out.
    readonly property var opener: QsMenuOpener {
        menu: TrayMenu.current
    }

    readonly property var entries: root.opener.children.values

    Component.onCompleted:
    Text {
        width: parent.width
        text: TrayMenu.item ? (TrayMenu.item.title || TrayMenu.item.id || "") : ""
        color: Theme.comment
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSmall
        elide: Text.ElideRight
        visible: text !== ""
    }

    // Back row, only when inside a submenu.
    Row {
        width: parent.width
        spacing: 8
        visible: TrayMenu.stack.length > 1
        height: 24

        Text {
            text: "\uf104"
            color: Theme.purple
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
        }

        Text {
            text: "back"
            color: Theme.comment
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: TrayMenu.back()
        }
    }

    Repeater {
        model: root.entries

        delegate: Item {
            id: row

            required property var modelData

            readonly property bool entrySeparator: modelData.isSeparator
            readonly property bool enabled: modelData.enabled
            readonly property bool hasChildren: modelData.hasChildren
            readonly property bool checked: modelData.checkState !== Qt.Unchecked

            width: parent.width
            height: row.entrySeparator ? 9 : 26

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                height: 1
                visible: row.entrySeparator
                color: Theme.border
            }

            Rectangle {
                anchors.fill: parent
                radius: Theme.radius
                visible: !row.entrySeparator
                color: hover.hovered && row.enabled ? Theme.alpha(Theme.selection, 0.85) : "transparent"
                Behavior on color {
                    ColorAnimation {
                        duration: Theme.animationFast
                    }
                }
            }

            // Check/radio column: the glyph is a nerd-font check so the column
            // never shifts, which a platform menu gets wrong.
            Text {
                id: check

                anchors.left: parent.left
                anchors.leftMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                width: 14
                visible: !row.entrySeparator
                text: row.checked ? "\uf00c" : ""
                color: Theme.purple
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
            }

            Text {
                id: label

                anchors.left: check.right
                anchors.leftMargin: 4
                anchors.right: arrow.left
                anchors.rightMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                visible: !row.entrySeparator
                text: row.modelData.text
                elide: Text.ElideRight
                color: row.enabled ? Theme.fg : Theme.alpha(Theme.comment, 0.7)
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
            }

            Text {
                id: arrow

                anchors.right: parent.right
                anchors.rightMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                visible: row.hasChildren && !row.entrySeparator
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
                enabled: row.enabled && !row.entrySeparator
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (row.hasChildren)
                        TrayMenu.drill(row.modelData);
                    else {
                        row.modelData.triggered();
                        TrayMenu.close();
                    }
                }
            }
        }
    }

    Text {
        width: parent.width
        visible: root.entries.length === 0
        text: "no menu"
        color: Theme.comment
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSmall
    }
}
