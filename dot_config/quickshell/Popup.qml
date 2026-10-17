import QtQuick
import Quickshell

// Shared shell for every bar panel: the window, the card, the animation.
//
// Panels are separate windows anchored under the bar widget that owns them, so
// they are not clipped by the 44px bar and can overlap windows. `name` is the
// key in Panels — the popup is visible exactly while that key is current.
//
// Dismissal is handled by the HyprlandFocusGrab in shell.qml (per upstream's
// recommendation over PopupWindow.grabFocus, which cannot change while open).
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

    // Whitelisted for the focus grab while open, otherwise a click on the panel's
    // own controls counts as "outside" and closes it. Panels are destroyed when
    // they close (see shell.qml), so the registry has to be kept clean.
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
