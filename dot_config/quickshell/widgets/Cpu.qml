import QtQuick
import qs
import Quickshell

// CPU utilisation. Green, as before; clicking opens the system panel.
BarItem {
    id: root

    panel: "system"

    Text {
        text: "cpu " + Util.pad(Stats.cpu, 3) + "%"
        color: Theme.green
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
    }
}
