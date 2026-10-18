import QtQuick
import qs
import Quickshell

// Battery panel: everything that reports a level, lowest first.
//
// The bar shows only the device closest to dying; this is the full picture --
// mouse, keyboard, receiver, laptop battery -- each with the kind and where
// the number comes from. The low rows are marked, so the device to swap out
// is the obvious one.
Popup {
    id: root

    name: "battery"
    contentWidth: 380

    // Lowest first: the device about to die is the one worth reading first.
    readonly property var sorted: Batteries.devices.slice().sort((a, b) => a.percent - b.percent)

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
        implicitHeight: 42

        // Below 20% the row gets the warning treatment: a tinted ground and
        // the same left bar the launcher's selection uses, in red.
        readonly property bool low: row.device.percent <= 20

        Rectangle {
            anchors.fill: parent
            radius: Theme.radius
            color: row.low ? Theme.alpha(Theme.red, 0.12) : "transparent"
        }

        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.margins: 6
            width: 3
            radius: 2
            visible: row.low
            color: Theme.red
        }

        Text {
            id: name

            anchors.left: parent.left
            anchors.leftMargin: 14
            anchors.top: parent.top
            anchors.topMargin: 7
            width: parent.width - 14 - 100
            text: row.device.name
            elide: Text.ElideRight
            color: Theme.fg
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
        }

        Text {
            anchors.left: name.left
            anchors.top: name.bottom
            anchors.topMargin: 2
            text: row.device.kind + " / " + row.device.source
            color: Theme.comment
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
        }

        Text {
            id: percent

            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.top: parent.top
            anchors.topMargin: 7
            width: 44
            horizontalAlignment: Text.AlignRight
            text: row.device.percent + "%"
            color: Batteries.colorFor(row.device.percent)
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
        }

        // The small bar under the percentage: fill grows with the level and
        // takes the same low-is-red colour as the number above it.
        Rectangle {
            id: track

            anchors.right: percent.right
            anchors.top: percent.bottom
            anchors.topMargin: 6
            width: 72
            height: 4
            radius: 2
            color: Theme.alpha(Theme.selection, 0.9)

            Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: parent.width * row.device.percent / 100
                radius: 2
                color: Batteries.colorFor(row.device.percent)
            }
        }
    }

    Section {
        text: "devices"
        visible: root.sorted.length > 0
    }

    Text {
        width: parent.width
        visible: root.sorted.length === 0
        text: "nothing is reporting a battery"
        color: Theme.comment
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSmall
    }

    Repeater {
        model: root.sorted

        delegate: DeviceRow {
            required property var modelData

            device: modelData
        }
    }
}
