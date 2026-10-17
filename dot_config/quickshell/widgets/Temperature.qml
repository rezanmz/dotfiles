import QtQuick
import qs
import Quickshell

// CPU package temperature (k10temp's Tctl).
//
// Thresholds are the ones the waybar config used: warning at 75 °C, critical at
// 90 °C — and critical blinks, which is the one animation the old CSS had.
BarItem {
    id: root

    panel: "system"

    readonly property real temp: Stats.cpuTemp
    readonly property bool critical: root.temp >= 90

    Text {
        id: label

        text: Util.pad(root.temp, 2) + "°C"
        color: Theme.level(root.temp, 75, 90, Theme.cyan)
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
    }

    SequentialAnimation on opacity {
        running: root.critical
        loops: Animation.Infinite
        alwaysRunToEnd: true
        NumberAnimation {
            to: 0.35
            duration: 500
        }
        NumberAnimation {
            to: 1
            duration: 500
        }
    }
}
