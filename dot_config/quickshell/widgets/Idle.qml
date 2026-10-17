import QtQuick
import qs
import Quickshell
import Quickshell.Wayland

// Idle inhibitor.
//
// Replaces waybar's idle_inhibitor module with the same underlying mechanism
// (the idle-inhibit Wayland protocol, which hypridle honours). A word rather
// than a glyph, like before: a missing Nerd Font glyph would silently render as
// a blank module, and this one carries state.
BarItem {
    id: root

    readonly property IdleInhibitor inhibitor: IdleInhibitor {
        // The bar window is the surface that holds the inhibitor; it is always
        // mapped, so the inhibitor lives exactly as long as the toggle is on.
        window: root.barWindow
        enabled: false
    }

    onClicked: root.inhibitor.enabled = !root.inhibitor.enabled

    Text {
        text: root.inhibitor.enabled ? "hold" : "idle"
        color: root.inhibitor.enabled ? Theme.green : Theme.comment
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
    }
}
