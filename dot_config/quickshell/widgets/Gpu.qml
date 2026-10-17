import QtQuick
import qs
import Quickshell

// iGPU utilisation.
//
// waybar had no GPU module, so the old bar showed this through the gpu-usage
// script; the numbers come from the same sysfs attributes now, read by Stats.
// VRAM and GTT detail (which mattered on this APU: only 512 MiB of dedicated
// VRAM, so anything large spills into GTT carved from system RAM) is in the
// system panel.
BarItem {
    id: root

    panel: "system"

    Text {
        text: "gpu " + Math.round(Stats.gpu) + "%"
        color: Theme.fg
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
    }
}
