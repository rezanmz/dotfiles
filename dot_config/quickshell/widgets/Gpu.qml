import QtQuick
import qs

// GPU utilisation.
//
// waybar had no GPU module, so the old bar showed this through the gpu-usage
// script; the numbers come from the same sysfs attributes now, read by Stats.
// Stats picks the card the console boots on (boot_vga), which on this machine
// is the discrete RX 9070 XT rather than the Raphael APU, and takes its
// temperature from that same card's hwmon.
// VRAM and GTT detail is in the system panel — opened by the group in Bar.qml,
// not by this readout.
Item {
    id: root

    implicitWidth: label.implicitWidth + Theme.modulePadding
    implicitHeight: Theme.barHeight
    width: implicitWidth
    height: implicitHeight

    Text {
        id: label

        anchors.centerIn: parent
        text: "gpu " + Util.pad(Stats.gpu, 3) + "%"
        color: Theme.fg
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
    }
}
