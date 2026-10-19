import QtQuick
import qs
import Quickshell

// Power: the way into the power panel — lock, log out, suspend, restart,
// shut down.
//
// It replaces the Control Centre's tray icon and takes over that widget's
// role as the *fallback* anchor for panels that have no widget of their own
// (the cheatsheet, and any panel opened without a click).
BarItem {
    id: root

    panel: "power"

    Text {
        // The power symbol (circle and stem, nf-fa-power_off), the same
        // codepoint the launcher's "Power off" row carries. Rendered from Hack
        // Nerd Font with PIL and looked at before picking it: U+F011 draws the
        // glyph, U+F0425 the same shape again and U+F0426 a dotted variant,
        // while an unassigned codepoint comes out a tofu box. Built from the
        // codepoint, like Rec.qml's glyph.
        text: String.fromCodePoint(0xF011)
        color: hovered ? Theme.fg : Theme.comment
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize

        HoverHandler {
            id: hovered
        }
    }

    Component.onCompleted: Panels.registerFallback(root)
}
