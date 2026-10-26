import QtQuick
import qs
import Quickshell

// Removable drives.
//
// One row per filesystem, grouped under the disk it lives on, because that is
// the shape of the thing: you mount a partition, you eject a disk.
//
// What the row shows is what the tray icon never could: the label, the size, the
// filesystem and whether it is mounted. What it does is one click on the row —
// open it in the file manager when it is mounted, mount it when it is not.
//
// The two switches at the bottom are the policies, and they are the shell's own
// now (DrivesState): automount is this panel mounting what appears, and
// notifications is this panel saying so.
Popup {
    id: root

    name: "drives"
    contentWidth: 300

    // A mount done elsewhere (a script, a file manager) raises no udev event, so
    // opening the panel is the moment to be sure the list is current.
    onOpenChanged: {
        if (open) {
            DrivesState.status = "";
            DrivesState.refresh();
        }
    }

    component Section: Text {
        color: Theme.comment
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSmall
        font.capitalization: Font.AllUppercase
    }

    // The same control as the network and bluetooth panels': a pill reads as
    // state, not as a button.
    component Toggle: Item {
        id: toggle

        required property bool on
        signal toggled()

        width: 34
        height: 18

        Rectangle {
            anchors.fill: parent
            radius: parent.height / 2
            color: toggle.on ? Theme.alpha(Theme.green, 0.35) : Theme.alpha(Theme.comment, 0.25)
            border.width: 1
            border.color: toggle.on ? Theme.green : Theme.alpha(Theme.comment, 0.5)
        }

        Rectangle {
            width: parent.height - 6
            height: width
            radius: width / 2
            y: 3
            x: toggle.on ? parent.width - width - 3 : 3
            color: toggle.on ? Theme.green : Theme.comment
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: toggle.toggled()
        }
    }

    component Button: Rectangle {
        id: button

        property string label: ""
        property bool usable: true
        signal clicked()

        implicitWidth: buttonLabel.implicitWidth + 20
        implicitHeight: 22
        radius: Theme.radius
        opacity: button.usable ? 1 : 0.5
        color: !button.usable ? "transparent" : (buttonHover.hovered ? Theme.alpha(Theme.selection, 0.9) : Theme.alpha(Theme.selection, 0.5))
        border.width: 1
        border.color: Theme.alpha(Theme.comment, 0.6)

        HoverHandler {
            id: buttonHover
            enabled: button.usable
        }

        Text {
            id: buttonLabel

            anchors.centerIn: parent
            text: button.label
            color: Theme.fg
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
        }

        MouseArea {
            anchors.fill: parent
            enabled: button.usable
            cursorShape: Qt.PointingHandCursor
            onClicked: button.clicked()
        }
    }

    // A switch and its name, on one line: the two settings at the bottom.
    component Setting: Item {
        id: setting

        property string label: ""
        property bool on: false
        signal toggled()

        width: parent.width
        height: 22

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            text: setting.label
            color: Theme.fg
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
        }

        Toggle {
            anchors.right: parent.right
            anchors.rightMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            on: setting.on
            onToggled: setting.toggled()
        }

        MouseArea {
            anchors.fill: parent
            anchors.rightMargin: 40
            cursorShape: Qt.PointingHandCursor
            onClicked: setting.toggled()
        }
    }

    Section {
        text: DrivesState.volumes.length > 0 ? "drives" : ""
    }

    Text {
        width: parent.width
        visible: DrivesState.volumes.length === 0
        text: "no removable drives"
        color: Theme.comment
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSmall
    }

    Repeater {
        model: DrivesState.disks

        delegate: Item {
            id: diskGroup

            required property var modelData

            width: parent.width
            implicitHeight: group.implicitHeight
            height: group.implicitHeight

            Column {
                id: group

                width: parent.width
                spacing: 2

                // The disk: its model, and the one action that belongs to the
                // whole device rather than to a filesystem on it.
                Item {
                    width: parent.width
                    height: 20

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 4
                        anchors.right: eject.left
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        text: diskGroup.modelData.model
                        elide: Text.ElideRight
                        color: Theme.comment
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSmall
                    }

                    Text {
                        id: eject

                        anchors.right: parent.right
                        anchors.rightMargin: 4
                        anchors.verticalCenter: parent.verticalCenter
                        text: DrivesState.isBusy(diskGroup.modelData.path) ? "working" : "eject"
                        color: ejectHover.hovered ? Theme.orange : Theme.comment
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSmall

                        HoverHandler {
                            id: ejectHover
                        }

                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -4
                            cursorShape: Qt.PointingHandCursor
                            onClicked: DrivesState.eject(diskGroup.modelData)
                        }
                    }
                }

                Repeater {
                    model: diskGroup.modelData.volumes

                    delegate: Item {
                        id: volumeRow

                        required property var modelData

                        readonly property bool hasFilesystem: volumeRow.modelData.fstype !== ""

                        width: parent.width
                        height: 40

                        Rectangle {
                            anchors.fill: parent
                            radius: Theme.radius
                            color: rowHover.hovered ? Theme.hoverBg : "transparent"
                        }

                        HoverHandler {
                            id: rowHover
                        }

                        Column {
                            anchors.left: parent.left
                            anchors.leftMargin: 8
                            anchors.right: action.left
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 1

                            Text {
                                width: parent.width
                                text: volumeRow.modelData.label !== "" ? volumeRow.modelData.label : volumeRow.modelData.path
                                elide: Text.ElideRight
                                color: Theme.fg
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSmall
                            }

                            Text {
                                width: parent.width
                                text: volumeRow.modelData.path + " \u00b7 " + (volumeRow.hasFilesystem ? volumeRow.modelData.fstype : "no filesystem") + " \u00b7 " + volumeRow.modelData.size
                                elide: Text.ElideRight
                                color: volumeRow.modelData.mounted ? Theme.green : Theme.comment
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSmall - 2
                            }
                        }

                        // The row itself: open when mounted, mount when not. The
                        // button repeats the one action that is not the row
                        // click, and the button is declared after the row's
                        // MouseArea so its own handler wins.
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (volumeRow.modelData.mounted) {
                                    DrivesState.open(volumeRow.modelData);
                                    Panels.close();
                                } else {
                                    DrivesState.mount(volumeRow.modelData);
                                }
                            }
                        }

                        Item {
                            id: action

                            anchors.right: parent.right
                            anchors.rightMargin: 4
                            anchors.verticalCenter: parent.verticalCenter
                            width: childrenRect.width
                            height: childrenRect.height

                            Button {
                                visible: volumeRow.hasFilesystem
                                label: DrivesState.isBusy(volumeRow.modelData.path) ? "working" : (volumeRow.modelData.mounted ? "unmount" : "mount")
                                usable: !DrivesState.isBusy(volumeRow.modelData.path)
                                onClicked: {
                                    if (volumeRow.modelData.mounted)
                                        DrivesState.unmount(volumeRow.modelData);
                                    else
                                        DrivesState.mount(volumeRow.modelData);
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // The policies. A hairline, because they are not devices.
    Rectangle {
        width: parent.width
        height: 1
        visible: DrivesState.volumes.length > 0
        color: Theme.border
    }

    Setting {
        label: "automount"
        on: DrivesState.automount
        onToggled: DrivesState.setAutomount(!DrivesState.automount)
    }

    Setting {
        label: "notifications"
        on: DrivesState.notifications
        onToggled: DrivesState.setNotifications(!DrivesState.notifications)
    }

    // Only while there is something to say: a mount that failed (a busy device,
    // a filesystem udisks2 will not touch) says why instead of doing nothing.
    Text {
        width: parent.width
        visible: DrivesState.status !== ""
        text: DrivesState.status
        wrapMode: Text.WordWrap
        color: Theme.red
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSmall - 1
    }
}
