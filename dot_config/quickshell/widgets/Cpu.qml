import QtQuick
import qs

// CPU utilisation. Green, as before.
//
// Plain readout: the system group in Bar.qml owns the hover pill, the click and
// the panel, so nothing in here opens anything. Half a modulePadding of air per
// side is what keeps a group of readouts reading as one item instead of a row
// of cramped ones.
Item {
    id: root

    implicitWidth: label.implicitWidth + Theme.modulePadding
    implicitHeight: Theme.barHeight
    width: implicitWidth
    height: implicitHeight

    Text {
        id: label

        anchors.centerIn: parent
        text: "cpu " + Util.pad(Stats.cpu, 3) + "%"
        color: Theme.green
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
    }
}
