import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs
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

    // barWindow is what popups reach the bar window through (QtQuick's
    // Window.window is a ProxiedWindow that the popup APIs reject).
    Component.onCompleted: Panels.barWindow = bar

    // The empty stretch of the bar counts as "outside": clicking it closes the
    // panel. First child, so it sits behind every widget and a widget's own click
    // handler still wins.
    //
    // No wheel here on purpose. It used to dim the screen from anywhere on the
    // bar, so a stray scroll over empty space — the bar is mostly empty — changed
    // the brightness of the whole display. The gesture belongs to the brightness
    // readout alone (see widgets/Brightness.qml); everywhere else the wheel does
    // nothing.
    MouseArea {
        anchors.fill: parent
        onClicked: Panels.close()
    }

    // The bar's bottom edge: the shell's signature hairline, a Dracula-spectrum
    // ramp that fades in and out at the ends instead of a flat border. One per
    // surface (see Theme.rampStart).
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 1
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop {
                position: 0.0
                color: Theme.alpha(Theme.rampStart, 0.0)
            }
            GradientStop {
                position: 0.18
                color: Theme.alpha(Theme.rampStart, 0.95)
            }
            GradientStop {
                position: 0.5
                color: Theme.alpha(Theme.rampMid, 0.95)
            }
            GradientStop {
                position: 0.82
                color: Theme.alpha(Theme.rampEnd, 0.95)
            }
            GradientStop {
                position: 1.0
                color: Theme.alpha(Theme.rampEnd, 0.0)
            }
        }
    }

    RowLayout {
        id: leftLayout
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        spacing: 0

        Workspaces {
            // The workspaces are split between the panels, so each bar shows
            // only the ones on its own screen.
            barScreen: bar.modelData
        }
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

        // Scroll to adjust: the two screen-wide things that are not
        // per-application like the volume is. Readouts, no panel on click.
        Brightness {}
        Warmth {}

        // The separators mark where one group ends and the next begins: what
        // you adjust by scrolling (volume, brightness, warmth), the network, the
        // device, and the two numbers that say whether the machine is loaded or
        // hot. Without the marks the bar is one long run of numbers and the eye
        // has to work out which belong together.
        Network {}

        Bluetooth {}

        // Only while a removable drive is attached: the icon is the shell's own
        // now, not udiskie's tray item, so it can say "nothing here" by not
        // being here (see widgets/Drives.qml).
        Drives {}

        // Same-panel readouts are grouped under one BarItem: one hover pill,
        // one click target, one highlight. The readouts inside are plain items
        // (no hover, no click, no panel of their own); the Row is sized from its
        // children so BarItem's content width picks the whole group up.
        //
        // Two numbers, not five: cpu and package temperature are the pair that
        // answer "is this machine fine", and they change every tick, so they earn
        // the space. Gpu load, memory, swap, DIMM temperatures, disk capacity and
        // disk throughput all live in the system panel — one click, and the panel
        // says which chip each number came from, which the bar never could.
        BarItem {
            panel: "system"
            separator: true

            Row {
                spacing: 0
                width: childrenRect.width
                height: childrenRect.height

                Cpu {}
                Temperature {}
            }
        }
        Clock {}
        // Last, at the far right edge: the recording pill only exists while a
        // recording runs (see Rec.qml), so it never sits in the middle of the
        // readouts pushing them around.
        Rec {}
        Power {}
    }
}
