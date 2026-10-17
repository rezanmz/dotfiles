import QtQuick
import qs
import Quickshell
import Quickshell.Bluetooth

// Bluetooth panel: adapter state, scanning, and the device list.
//
// This is where `kitty -e bluetui` was launched from. Connect/disconnect, pair,
// and battery level (BluetoothDevice exposes it directly, which is how the
// wireless mouse and keyboard report theirs).
Popup {
    id: root

    name: "bluetooth"
    contentWidth: 380

    readonly property var adapter: Bluetooth.defaultAdapter

    component Section: Text {
        color: Theme.comment
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSmall
        font.capitalization: Font.AllUppercase
    }

    component DeviceRow: Item {
        id: row

        required property var device

        width: parent.width
        implicitHeight: 30

        readonly property bool connected: device.connected

        Text {
            id: name

            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - state.width - battery.width - 20
            text: (row.device.icon !== "" ? "" : "") + row.device.name
            elide: Text.ElideRight
            color: row.connected ? Theme.fg : Theme.comment
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
        }

        Text {
            id: state

            anchors.right: battery.left
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            text: row.connected ? "connected" : (row.device.paired ? "paired" : "new")
            color: row.connected ? Theme.green : Theme.comment
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
        }

        Text {
            id: battery

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: 46
            horizontalAlignment: Text.AlignRight
            visible: row.device.batteryAvailable
            text: Math.round(row.device.battery * 100) + "%"
            color: Theme.comment
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton | Qt.RightButton

            onClicked: mouse => {
                if (mouse.button === Qt.RightButton) {
                    row.device.forget();
                    return;
                }
                if (row.connected)
                    row.device.disconnect();
                else if (row.device.paired)
                    row.device.connect();
                else
                    row.device.pair();
            }
        }
    }

    Text {
        width: parent.width
        text: !root.adapter ? "no bluetooth adapter" : (root.adapter.enabled ? root.adapter.name : "adapter off")
        color: root.adapter && root.adapter.enabled ? Theme.fg : Theme.comment
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize

        MouseArea {
            anchors.fill: parent
            enabled: root.adapter !== null
            cursorShape: Qt.PointingHandCursor
            onClicked: root.adapter.enabled = !root.adapter.enabled
        }
    }

    Row {
        spacing: 14
        visible: root.adapter !== null && root.adapter.enabled

        Text {
            text: root.adapter && root.adapter.discovering ? "stop scanning" : "scan"
            color: root.adapter && root.adapter.discovering ? Theme.pink : Theme.comment
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.adapter.discovering = !root.adapter.discovering
            }
        }

        Text {
            text: root.adapter && root.adapter.discoverable ? "visible" : "hidden"
            color: root.adapter && root.adapter.discoverable ? Theme.pink : Theme.comment
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.adapter.discoverable = !root.adapter.discoverable
            }
        }
    }

    Section {
        text: "devices"
        visible: root.adapter !== null
    }

    Repeater {
        model: root.adapter ? root.adapter.devices : []

        delegate: DeviceRow {
            required property var modelData

            device: modelData
        }
    }
}
