import QtQuick
import qs

// CPU package temperature (k10temp's Tctl).
//
// Thresholds are the ones the waybar config used: warning at 75 °C, critical at
// 90 °C — and critical blinks, which is the one animation the old CSS had.
// The system group in Bar.qml owns the panel; this is only the number.
Item {
    id: root

    implicitWidth: label.implicitWidth + Theme.modulePadding
    implicitHeight: Theme.barHeight
    width: implicitWidth
    height: implicitHeight

    readonly property real temp: Stats.cpuTemp
    readonly property bool critical: root.temp >= 90

    Text {
        id: label

        anchors.centerIn: parent
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
