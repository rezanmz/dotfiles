import QtQuick
import qs
import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Widgets

// Status notifier (tray) icons.
//
// Same placement rule as the waybar config: first in the right cluster, so a new
// icon grows into free space to its right instead of pushing the readouts the
// user is actually watching leftwards.
//
// Left click activates the item, right click opens its DBus menu through
// SystemTrayItem.display() — the menu is the application's own, so no menu has
// to be modelled here.
Item {
    id: root

    // 18px icons (waybar's icon-size) with the module's own padding.
    readonly property int iconSize: 18

    implicitWidth: row.implicitWidth + Theme.modulePadding * 2
    implicitHeight: Theme.barHeight

    Row {
        id: row

        anchors.centerIn: parent
        spacing: 8

        Repeater {
            model: SystemTray.items

            delegate: Item {
                id: slot

                required property var modelData

                implicitWidth: root.iconSize
                implicitHeight: root.iconSize
                anchors.verticalCenter: parent.verticalCenter

                IconImage {
                    anchors.fill: parent
                    // SystemTrayItem.icon is already an Image-usable source
                    // string (e.g. image://icon/...), not a bare theme name, so
                    // it is used as-is. Passing it through iconPath() returns an
                    // empty string and the icon silently disappears.
                    source: slot.modelData.icon
                    visible: source !== ""
                }

                HoverHandler {
                    id: hover
                }

                Rectangle {
                    anchors.centerIn: parent
                    width: root.iconSize + 6
                    height: root.iconSize + 6
                    radius: Theme.radius
                    color: hover.hovered ? Theme.hoverBg : "transparent"
                    z: -1
                }

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

                    onClicked: mouse => {
                        // Menu coordinates are relative to the bar window, which
                        // is the popup's parent.
                        const position = slot.mapToItem(null, 0, slot.height);
                        if (mouse.button === Qt.RightButton && slot.modelData.hasMenu)
                            slot.modelData.display(Panels.barWindow, position.x, position.y);
                        else if (mouse.button === Qt.LeftButton && slot.modelData.onlyMenu && slot.modelData.hasMenu)
                            slot.modelData.display(Panels.barWindow, position.x, position.y);
                        else if (mouse.button === Qt.LeftButton)
                            slot.modelData.activate();
                    }
                    onWheel: wheel => slot.modelData.scroll(wheel.angleDelta.y, false)
                }
            }
        }
    }
}
