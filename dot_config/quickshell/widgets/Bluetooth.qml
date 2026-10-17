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

    Text {
        text: root.enabled ? "\uf293 " + root.connected : "\uf293 off"
        color: root.enabled ? Theme.pink : Theme.comment
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
    }
}
