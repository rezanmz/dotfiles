import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.widgets

// The bar.
//
// A layer-shell panel on the top layer with an exclusive zone the height of the
// bar, which is what reserves the strip the waybar `reserved=[0,44,0,0]` used to
// cover. The layer namespace is `quickshell-bar` so Hyprland's layer rules can
// blur it (see 70-rules.lua).
//
// Module order matches the waybar config it replaces: workspaces and the window
// title on the left, then the status cluster on the right with the tray first —
// as the last item the tray would push every other readout leftwards whenever an
// icon appeared.
PanelWindow {
    id: bar

    // Filled in by the Variants in shell.qml, one bar per monitor.
    required property ShellScreen modelData

    screen: modelData
    anchors.top: true
    anchors.left: true
    anchors.right: true
    implicitHeight: Theme.barHeight
    color: Theme.barBg
    exclusiveZone: Theme.barHeight
    WlrLayershell.namespace: "quickshell-bar"
    WlrLayershell.layer: WlrLayer.Top

    // Whitelisted for the focus grab so clicking the bar itself never counts as
    // "clicked outside".
    Component.onCompleted: {
        Panels.register(bar);
        Panels.barWindow = bar;
    }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 1
        color: Theme.selection
    }

    RowLayout {
        id: leftLayout
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        spacing: 0

        Workspaces {}
        Title {}
        Language {}
    }

    RowLayout {
        id: rightLayout
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: 0

        Tray {}
        Bell {}
        Idle {}
        Media {}
        Audio {}
        Network {}
        Speed {}
        Bluetooth {}
        Cpu {}
        Gpu {}
        Memory {}
        Temperature {}
        Disk {}
        Clock {}
    }
}
