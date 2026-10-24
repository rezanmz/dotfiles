import QtQuick
import qs
import Quickshell
import Quickshell.Services.SystemTray

// The tray, as one icon.
//
// waybar showed one icon per StatusNotifier item, and on this desktop that row
// (udiskie, a browser, a password manager) was the widest thing on the bar — it
// grew with every application and said nothing about what the icons were. There
// is one icon now, and the click opens the item list (panels/Tray.qml), where
// each item is named and its DBusMenu is one click deeper.
//
// The count rides along only when there is more than one item: a numeral is a
// character wide, and "1" on its own is noise.
BarItem {
    id: root

    panel: "tray"

    readonly property int count: SystemTray.items.values.length

    // Nothing in the tray, nothing to click.
    visible: root.count > 0

    Text {
        text: root.count > 1 ? "\uf00b " + root.count : "\uf00b"
        color: root.panelOpen ? Theme.purple : Theme.comment
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
    }
}
