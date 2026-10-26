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
// It maps and unmaps with the panel on purpose. Keyboard focus is applied when a
// layer surface maps, so flipping WlrLayershell.keyboardFocus on an already-mapped
// window does nothing (measured: the bar held Exclusive while a panel was open and
// the key never arrived).
//
// `mask: Region {}` is an empty input region, so it is click-through: every click
// still reaches the panel, the bar or the window underneath. That is what makes it
// safe to put on the overlay layer, above the panels it must not block. It is not
// a scrim — an input-taking surface here would have to sit above the panels to see
// the desktop at all, and would then eat every click they need.
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
    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true
    mask: Region {}
    WlrLayershell.namespace: "quickshell-escape"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    Item {
        anchors.fill: parent
        focus: true

        Keys.onEscapePressed: Panels.close()
    }
}
