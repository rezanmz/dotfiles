import QtQuick
import qs

// iGPU utilisation.
//
// waybar had no GPU module, so the old bar showed this through the gpu-usage
// script; the numbers come from the same sysfs attributes now, read by Stats.
// VRAM and GTT detail (which mattered on this APU: only 512 MiB of dedicated
// VRAM, so anything large spills into GTT carved from system RAM) is in the
// system panel — opened by the group in Bar.qml, not by this readout.
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
