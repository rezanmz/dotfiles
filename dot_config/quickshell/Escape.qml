import QtQuick
import Quickshell
import Quickshell.Wayland
import qs

// Escape, for as long as a bar panel is open.
//
// A panel is a PopupWindow: it cannot take keyboard focus at all, so with a panel
// open the key goes to whichever application is focused and nothing closes. This
// surface is the shell's keyboard seat for the lifetime of a panel.
//
// It is one pixel in the bottom-right corner, and that is the whole point. An
// earlier version covered the screen with `mask: Region {}` on the theory that an
// empty input region makes a surface click-through; it does not here, and every
// click on the screen — including clicks inside the panel — went to this surface
// instead, so the shell looked frozen until Escape was pressed. A 1x1 surface
// cannot block a click anywhere else no matter what the input region resolves to,
// and keyboard focus does not depend on the surface being large.
//
// It maps and unmaps with the panel on purpose: keyboard focus is applied when a
// layer surface maps, so flipping WlrLayershell.keyboardFocus on an already-mapped
// window does nothing (measured: the bar held Exclusive while a panel was open and
// the key never arrived).
//
// Panels that hold the keyboard themselves (Panels.selfFocused) are excluded:
// taking it from them would swallow what the user is typing, and those panels
// close on Escape in their own document.
PanelWindow {
    id: root

    visible: Panels.shellOwnsKeyboard
    screen: Util.focusedScreen()
    color: "transparent"
    exclusiveZone: -1
    anchors.bottom: true
    anchors.right: true
    implicitWidth: 1
    implicitHeight: 1
    WlrLayershell.namespace: "quickshell-escape"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    Item {
        anchors.fill: parent
        focus: true

        Keys.onEscapePressed: Panels.close()
    }
}
