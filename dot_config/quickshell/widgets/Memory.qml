import QtQuick
import qs
import Quickshell

// Memory usage. Yellow, as before; used/total is in the system panel.
BarItem {
    id: root

    panel: "system"

    Text {
        text: "ram " + Util.pad(Stats.memPct, 3) + "%"
        color: Theme.yellow
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
    }
}
