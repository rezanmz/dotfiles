import QtQuick
import qs
import Quickshell

// Removable drives, as one icon.
//
// It exists only while a drive is plugged in — the whole complaint about the
// udiskie tray icon was that it sat there with nothing attached, saying nothing.
// Green when something is mounted, so a stick that is still unmounted (automount
// off, or a filesystem udisks2 will not mount) is visibly different from one you
// can open.
BarItem {
    id: root

    panel: "drives"

    readonly property bool present: DrivesState.volumes.length > 0

    visible: root.present

    Text {
        text: "\uf287"
        color: root.panelOpen ? Theme.purple : (DrivesState.anyMounted ? Theme.green : Theme.comment)
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
    }
}
