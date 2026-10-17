import QtQuick
import qs
import Quickshell

// Root filesystem usage.
//
// One entry is enough: root is a single LVM/btrfs volume, which is why the
// waybar config had a single `disk` module with no mount list. The percentage is
// in the system panel; this is the "am I about to run out" number.
BarItem {
    id: root

    panel: "system"

    // 85% is where a root filesystem stops being boring, 92% is where btrfs
    // snapshots and updates start to hurt.
    readonly property color colour: Theme.level(Stats.diskPct, 85, 92, Theme.yellow)

    Text {
        text: Util.gib(Stats.diskUsed) + "GiB"
        color: root.colour
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
    }
}
