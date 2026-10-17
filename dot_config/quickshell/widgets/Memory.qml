import QtQuick
import qs

// Memory usage. Yellow, as before; used/total is in the system panel, which the
// group in Bar.qml opens.
Item {
    id: root

    implicitWidth: label.implicitWidth + Theme.modulePadding
    implicitHeight: Theme.barHeight
    width: implicitWidth
    height: implicitHeight

    Text {
        id: label

        anchors.centerIn: parent
        text: "ram " + Util.pad(Stats.memPct, 3) + "%"
        color: Theme.yellow
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
    }
}
