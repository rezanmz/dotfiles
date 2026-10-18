import QtQuick
import qs
import Quickshell

// Control centre: the way into the quick-settings panel.
//
// macOS keeps Control Centre at the right end of the menu bar; this is the same
// idea in one glyph, so the panel has an anchor and is discoverable without a
// chord. It also serves as the *fallback* anchor for panels that have no widget of
// their own (the cheatsheet, and the battery panel when its readout has collapsed).
BarItem {
    id: root

    panel: "controls"

    Text {
        text: "\uf1de"
        color: hovered ? Theme.fg : Theme.comment
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize

        HoverHandler {
            id: hovered
        }
    }

    Component.onCompleted: Panels.registerFallback(root)
}
