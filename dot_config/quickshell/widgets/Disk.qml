import QtQuick
import qs

// Root filesystem usage.
//
// One entry is enough: root is a single LVM/btrfs volume, which is why the
// waybar config had a single `disk` module with no mount list. The percentage is
// in the system panel (opened by the group in Bar.qml); this is the "am I about
// to run out" number.
Item {
    id: root

    implicitWidth: label.implicitWidth + Theme.modulePadding
    implicitHeight: Theme.barHeight
    width: implicitWidth
    height: implicitHeight

    // 85% is where a root filesystem stops being boring, 92% is where btrfs
    // snapshots and updates start to hurt.
    readonly property color colour: Theme.level(Stats.diskPct, 85, 92, Theme.yellow)

    Text {
        id: label

        anchors.centerIn: parent
        text: Util.pad(Stats.diskUsed / 1073741824, 3) + "GiB"
        color: root.colour
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
    }
}
