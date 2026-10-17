import QtQuick
import qs

// Live throughput.
//
// The standalone readout the waybar config kept next to the network module, so
// "how fast is this download going" is visible without opening anything. Both
// directions are padded to a fixed width, which is what stops the readout from
// resizing the bar every second. The network panel is opened by the group in
// Bar.qml; this readout opens nothing itself.
Item {
    id: root

    implicitWidth: label.implicitWidth + Theme.modulePadding
    implicitHeight: Theme.barHeight
    width: implicitWidth
    height: implicitHeight

    Text {
        id: label

        anchors.centerIn: parent
        text: "\u2193 " + Util.rateFixed(Stats.netRx) + "  \u2191 " + Util.rateFixed(Stats.netTx)
        color: Theme.comment
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
    }
}
