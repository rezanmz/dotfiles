import QtQuick
import Quickshell

// Shared shell for every bar panel: the window, the card, the animation.
//
// Panels are separate windows anchored under the bar widget that owns them, so
// they are not clipped by the 44px bar and can overlap windows. `name` is the
// key in Panels — the popup is visible exactly while that key is current.
//
// Dismissal is the event watch in shell.qml: a new active window or a workspace
// switch closes the panel. Not HyprlandFocusGrab (upstream's recommendation) — it
// takes the keyboard for the whole seat, which swallowed every keybind on every
// monitor while a panel was open — and not PopupWindow.grabFocus either, which
// cannot change while open and measured worse here: a grabbing popup took the
// keyboard but no longer dismissed on an outside click at all.
//
// Escape is a separate matter: a popup has no keyboard focus, so the popup panels
// cannot close on Escape — the bar-level owner (a full-screen click-through layer
// surface) turned out to cost the click dismissal, so Escape is handled only by
// the panels that hold the keyboard themselves: the cheatsheet and the capture
// toolbar (layer-shell, WlrKeyboardFocus.Exclusive) and the notification centre
// (its search field needs an xdg popup grab, so it takes one).
PopupWindow {
    id: root

    required property string name

    // Panel contents; laid out in a Column with Theme.panelPadding margins.
    default property alias content: column.data

    property int contentWidth: Theme.panelWidth
    property int contentHeight: column.implicitHeight + Theme.panelPadding * 2

    // Hangs below the widget that owns it, centered on it, flipping or sliding
    // if it would run off the screen edge. The anchor comes from Panels, which
    // records the widget that was clicked — see Panels.toggle.
    // Only the item is set: PopupAnchor derives the window from it. Setting
    // anchor.window to the QQuickWindow that `Window.window` returns fails —
    // quickshell rejects it ("not a quickshell window") and the popup is left
    // with a NaN position, so it never appears.
    anchor.item: Panels.anchorItem
    // Attach to the widget's bottom edge and grow downward. gravity is the
    // direction the popup expands in, not the edge it hangs from: with
    // gravity: Edges.Top the panel grew *upward* over the bar.
    anchor.edges: Edges.Bottom
    anchor.gravity: Edges.Bottom
    anchor.adjustment: PopupAdjustment.Slide | PopupAdjustment.FlipX

    readonly property bool open: Panels.current === root.name

    // Kept visible for the length of the close animation; the binding alone
    // would hide the window on the same frame the panel closes.
    property bool hiding: false
    visible: open || hiding

    onOpenChanged: {
        // The anchor rect is not recomputed when anchor.item changes after the
        // window was created (a documented PopupAnchor gotcha): without this the
        // popup has no position and never maps.
        if (open)
            root.anchor.updateAnchor();
        if (open) {
            hiding = false;
            hideTimer.stop();
        } else if (visible) {
            hiding = true;
            hideTimer.restart();
        }
    }

    Timer {
        id: hideTimer
        interval: Theme.animationFast
        onTriggered: root.hiding = false
    }


    // Panels announce themselves to Panels so the shell knows what is open; they
    // are destroyed when they close (see shell.qml), so the list has to be kept
    // clean.
    Component.onCompleted: Panels.register(root)
    Component.onDestruction: Panels.unregister(root)

    color: "transparent"
    implicitWidth: contentWidth
    implicitHeight: contentHeight

    Rectangle {
        id: card

        anchors.fill: parent
        color: Theme.panelBg
        radius: Theme.panelRadius
        border.width: 1
        border.color: Theme.border

        // Escape closes the panel, for the one popup panel whose window takes the
        // keyboard: the notification centre, which holds an xdg popup grab for its
        // search field. The other popups never see a key press — a popup without a
        // grab has no keyboard focus — so they do not close on Escape. Nothing
        // inside a panel handles Escape before this, except the network password
        // prompt, which accepts the event and keeps the panel open.
        Keys.onEscapePressed: Panels.close()

        // Same hairline as the bar's bottom edge, on the card's top edge.
        Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: 1
            height: 2
            radius: parent.radius
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop {
                    position: 0.0
                    color: Theme.alpha(Theme.rampStart, 0.0)
                }
                GradientStop {
                    position: 0.25
                    color: Theme.alpha(Theme.rampStart, 0.9)
                }
                GradientStop {
                    position: 0.6
                    color: Theme.alpha(Theme.rampMid, 0.9)
                }
                GradientStop {
                    position: 1.0
                    color: Theme.alpha(Theme.rampEnd, 0.0)
                }
            }
        }

        opacity: root.open ? 1 : 0
        scale: root.open ? 1 : 0.97

        Behavior on opacity {
            NumberAnimation {
                duration: Theme.animationFast
                easing.type: Easing.OutCubic
            }
        }
        Behavior on scale {
            NumberAnimation {
                duration: Theme.animationNormal
                easing.type: Easing.OutCubic
            }
        }

        Column {
            id: column

            anchors.fill: parent
            anchors.margins: Theme.panelPadding
            spacing: Theme.spacing
        }
    }
}
