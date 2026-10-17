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
// Left click opens the item's DBus menu when it has one and otherwise activates
// it; middle click always activates; right click opens the menu. The menu is the
// application's own, shown through SystemTrayItem.display(), so no menu has to
// be modelled here.
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
                    Behavior on color {
                        ColorAnimation {
                            duration: Theme.animationFast
                        }
                    }
                    z: -1
                }

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                    cursorShape: Qt.PointingHandCursor

                    onClicked: mouse => {
                        // udiskie's item advertises org.kde.StatusNotifierItem.Activate(ii)
                        // but the bus answers "Call failed: No handler for Activate" — its
                        // activation is a stub and only its dbusmenu is real. So the menu is
                        // the primary left-click action whenever the item has one, and
                        // activate() is just the fallback (and the middle-click action).
                        const item = slot.modelData;
                        if (mouse.button === Qt.MiddleButton) {
                            item.activate();
                        } else if (item.hasMenu) {
                            // Drawn by the shell (TrayMenu.qml + panels/Tray.qml) rather
                            // than handed to Qt's platform menu renderer, which needs
                            // QApplication mode and looks nothing like the rest of the
                            // desktop.
                            TrayMenu.openFor(item, slot);
                        } else if (mouse.button === Qt.LeftButton) {
                            item.activate();
                        }
                    }
                    onWheel: wheel => slot.modelData.scroll(wheel.angleDelta.y, false)
                }
            }
        }
    }
}
