import QtQuick
import qs
import Quickshell

// Live throughput.
//
// The standalone readout the waybar config kept next to the network module, so
// "how fast is this download going" is visible without opening anything. Both
// directions are padded to a fixed width, which is what stops the readout from
// resizing the bar every second.
BarItem {
    id: root

    panel: "network"

    Text {
        text: "\u2193 " + Util.rateFixed(Stats.netRx) + "  \u2191 " + Util.rateFixed(Stats.netTx)
        color: Theme.comment
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
    }
}
