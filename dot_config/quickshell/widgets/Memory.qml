import QtQuick
import qs
import Quickshell

// Memory usage. Yellow, as before; used/total is in the system panel.
BarItem {
    id: root

    panel: "system"

    Text {
        text: "ram " + Math.round(Stats.memPct) + "%"
        color: Theme.yellow
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
    }
}
