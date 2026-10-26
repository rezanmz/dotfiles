import QtQuick
import qs
import Quickshell
import Quickshell.DBusMenu
import Quickshell.Services.SystemTray
import Quickshell.Widgets

// Tray, drawn in the shell's own style: the item list, then one item's menu.
//
// SystemTrayItem.display() hands the DBusMenu to Qt, which draws a platform menu
// — square corners, system font, no theme — and needs QApplication mode to work
// at all. Reading the same menu through QsMenuOpener and drawing it here keeps the
// shell consistent, and gives the menu the same hover, radius and hairline as
// every other surface.
//
// The bar shows one tray icon, not one per item: with udiskie, a browser and a
// password manager the icon row was the widest thing on the bar. What was the
// left click on an icon is now two clicks (list, then item) on a surface that
// also names the items, which the icons never did.
//
// One level at a time inside a menu: a row with children drills in and a "back"
// row appears, instead of spawning a second window that has to chase the pointer.
Popup {
    id: root

    name: "tray"
    contentWidth: 268

    readonly property var items: SystemTray.items.values

    // The menu level being shown. Rebound as TrayMenu drills in and out.
    readonly property var opener: QsMenuOpener {
        menu: TrayMenu.current
    }

    readonly property var entries: root.opener.children.values

    Text {
        width: parent.width
        text: TrayMenu.item ? (TrayMenu.item.title || TrayMenu.item.id || "") : "tray"
        color: Theme.comment
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSmall
        elide: Text.ElideRight
    }

    // Back row: always present while inside a menu, out of a submenu and (from
    // the top of the item's menu) back to the item list.
    Item {
        width: parent.width
        height: 24
        visible: !TrayMenu.atList

        Row {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

            Text {
                text: "\uf104"
                color: Theme.purple
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
            }

            Text {
                text: TrayMenu.stack.length > 1 ? "back" : "all items"
                color: Theme.comment
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
            }
        }

        // Not inside the Row: a Row positions its children, so a MouseArea that
        // fills it cannot be laid out by it.
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: TrayMenu.back()
        }
    }

    // ---- the item list ---------------------------------------------------
    Repeater {
        model: TrayMenu.atList ? root.items : []

        delegate: Item {
            id: itemRow

            required property var modelData

            readonly property bool hasMenu: modelData.hasMenu

            width: parent.width
            height: 28

            Rectangle {
                anchors.fill: parent
                radius: Theme.radius
                color: itemHover.hovered ? Theme.alpha(Theme.selection, 0.85) : "transparent"
                Behavior on color {
                    ColorAnimation {
                        duration: Theme.animationFast
                    }
                }
            }

            IconImage {
                id: icon

                anchors.left: parent.left
                anchors.leftMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                implicitWidth: 16
                implicitHeight: 16
                // Already an Image-usable source string; see widgets/Tray.qml.
                source: itemRow.modelData.icon
            }

            Text {
                anchors.left: icon.right
                anchors.leftMargin: 8
                anchors.right: arrow.left
                anchors.verticalCenter: parent.verticalCenter
                text: itemRow.modelData.title || itemRow.modelData.id || ""
                elide: Text.ElideRight
                color: Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
            }

            Text {
                id: arrow

                anchors.right: parent.right
                anchors.rightMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                text: itemRow.hasMenu ? "\uf105" : "\uf08e"
                color: Theme.comment
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
            }

            HoverHandler {
                id: itemHover
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (itemRow.hasMenu) {
                        TrayMenu.openFor(itemRow.modelData);
                    } else {
                        itemRow.modelData.activate();
                        // The app cannot raise itself (Util.focusApp). A window
                        // that is still hidden has no toplevel yet, and mapping
                        // it focuses it on its own.
                        Util.focusApp([itemRow.modelData.id, itemRow.modelData.icon, itemRow.modelData.title]);
                        TrayMenu.close();
                    }
                }
            }
        }
    }

    // ---- the item's menu -------------------------------------------------
    Repeater {
        model: TrayMenu.atList ? [] : root.entries

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
                anchors.right: arrowMenu.left
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
                id: arrowMenu

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
                    if (row.hasChildren) {
                        TrayMenu.drill(row.modelData);
                    } else {
                        // sendTriggered(), not triggered(): `triggered` is a
                        // signal, so calling it only emits locally and the
                        // server never hears the click. That is why every item
                        // in a DBusMenu here (udiskie's toggles among them) did
                        // nothing.
                        if (typeof row.modelData.sendTriggered === "function")
                            row.modelData.sendTriggered();
                        else
                            row.modelData.triggered();
                        TrayMenu.close();
                    }
                }
            }
        }
    }

    Text {
        width: parent.width
        visible: TrayMenu.atList && root.items.length === 0
        text: "no tray items"
        color: Theme.comment
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSmall
    }

    Text {
        width: parent.width
        visible: !TrayMenu.atList && root.entries.length === 0
        text: "no menu"
        color: Theme.comment
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSmall
    }
}
