import QtQuick
import Quickshell
import Quickshell.Wayland
import qs

// "Click somewhere else", for the bar panels.
//
// Panels are overlay-layer surfaces (Popup.qml) and this one is on the top layer,
// so the panel is above it: a click on the panel reaches the panel, and a click
// anywhere else lands here and closes it. That ordering is why panels stopped being
// xdg-popups — a popup renders above everything on the bar's layer, so no catcher
// could be placed between the desktop and the panel.
//
// The bar keeps its own strip (the top margin), so clicking another widget still
// switches panels instead of only closing the open one.
//
// Pointer only: no keyboard focus, so keystrokes keep going to the focused window
// and Escape is handled by the compositor bind in Panels.qml. Mapped only while a
// panel is open — a permanently mapped surface would swallow every desktop click.
PanelWindow {
    id: root

    visible: Panels.anyOpen
    screen: Util.focusedScreen()
    color: "transparent"
    exclusiveZone: -1
    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true
    margins.top: Theme.barHeight
    WlrLayershell.namespace: "quickshell-catcher"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onClicked: Panels.close()
    }
}
