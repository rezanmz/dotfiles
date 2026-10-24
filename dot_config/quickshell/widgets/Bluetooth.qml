import QtQuick
import qs
import Quickshell
import Quickshell.Bluetooth

// Bluetooth adapter state and connected device count.
//
// Same readout as the waybar module (" 2" / " off"). Clicking opens the
// bluetooth panel, which lists and connects devices — that is what
// `kitty -e bluetui` was for.
BarItem {
    id: root

    panel: "bluetooth"

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool enabled: root.adapter !== null && root.adapter.enabled

    readonly property int connected: {
        if (!root.adapter)
            return 0;
        let count = 0;
        const devices = root.adapter.devices.values;
        for (let i = 0; i < devices.length; i++) {
            if (devices[i].connected)
                count++;
        }
        return count;
    }

    // How many of the connected devices are on a charger. The kernel is the
    // only source for that (see Charging.qml) -- BlueZ and Quickshell have no
    // charging flag -- and it only knows about the devices that speak HID++,
    // so this is a count of what the kernel can see, not of every device.
    readonly property int charging: {
        if (!root.adapter)
            return 0;
        let count = 0;
        const devices = root.adapter.devices.values;
        for (let i = 0; i < devices.length; i++) {
            if (devices[i].connected && Charging.isCharging(devices[i].address))
                count++;
        }
        return count;
    }

    // The bolt for a device on its charger. It is a separate element rather
    // than part of the count, so it can carry its own colour: the point of
    // the mark is that it stands out from the readouts around it, and a bolt
    // in the same pink as the count would not.
    //
    // It leads the count, and the count is anchored to it only while the bolt
    // is showing. childrenRect counts invisible children, so a bolt that sat
    // after the count would keep a gap in the bar for a mark that is not
    // there.
    Text {
        id: bolt

        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        visible: root.charging > 0
        text: Charging.glyph
        color: Theme.green
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
    }

    // The count of connected devices, with the bluetooth mark.
    Text {
        id: count

        anchors.left: bolt.visible ? bolt.right : parent.left
        anchors.leftMargin: bolt.visible ? 3 : 0
        anchors.verticalCenter: parent.verticalCenter
        // No "off" word: a dimmed mark is the same information in a third of
        // the width, and the panel behind the click says the rest.
        text: root.enabled ? "\uf293 " + root.connected : "\uf293"
        color: root.enabled ? Theme.pink : Theme.comment
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
    }
}
