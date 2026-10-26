import QtQuick
import Quickshell
import Quickshell.Wayland
import qs

// Shared shell for every bar panel: the window, the card, the animation.
//
// Panels are layer surfaces on the overlay layer, hung under the bar widget that
// owns them, so they are not clipped by the 44px bar and can overlap windows.
// `name` is the key in Panels — the panel is visible exactly while that key is
// current.
//
// Why a layer surface and not a PopupWindow: a popup is an xdg-popup of the bar
// surface, and popups render above everything on the parent's layer. That makes a
// click-catcher impossible — it would either cover the panel or sit under the
// desktop. On the overlay layer the panel is above the catcher (Catcher.qml, on
// the top layer) and above the bar, so a click outside the panel reaches the
// catcher and dismisses, while a click inside it reaches the panel.
//
// Dismissal is therefore: a click outside (Catcher.qml), Escape (a compositor
// bind, see Panels.qml), and clicking the widget again. Deliberately NOT a focus
// change — closing on "another window became active" meant the panel vanished
// whenever the pointer passed over a window on its way to the panel.
//
// The keyboard is never taken here: keystrokes keep going to the focused window.
// Panels that need it (the notification search field, the network password
// prompt) take it themselves and close on Escape in their own document.
PanelWindow {
    id: root

    required property string name

    // Panel contents; laid out in a Column with Theme.panelPadding margins.
    default property alias content: column.data

    property int contentWidth: Theme.panelWidth
    property int contentHeight: column.implicitHeight + Theme.panelPadding * 2

    readonly property bool open: Panels.current === root.name

    // The monitor the panel belongs to, captured when it opens. Bound to the
    // focused screen it would follow the pointer to another monitor, and a panel
    // that jumps across screens when the mouse drifts is worse than one that
    // stays where it was opened.
    property var panelScreen: Util.focusedScreen()

    // Kept visible for the length of the close animation; the binding alone
    // would hide the window on the same frame the panel closes.
    property bool hiding: false
    visible: open || hiding

    // The widget that opened it. Panels records it on the click; a panel opened
    // by keybind or IPC has no widget and falls back to the middle of the screen.
    readonly property var anchor: Panels.anchorItem
    readonly property real anchorX: anchor ? anchor.mapToItem(null, 0, 0).x : 0
    readonly property real anchorWidth: anchor ? anchor.width : 0
    readonly property real desiredLeft: anchor ? anchorX + anchorWidth / 2 - contentWidth / 2 : (screen.width - contentWidth) / 2

    screen: root.panelScreen
    anchors.top: true
    anchors.left: true
    // Hung from the bar's bottom edge, clamped so the panel never runs off the
    // monitor it was opened on.
    margins.top: Theme.barHeight + Theme.margin
    margins.left: Math.max(Theme.margin, Math.min(screen.width - contentWidth - Theme.margin, Math.round(desiredLeft)))

    implicitWidth: contentWidth
    implicitHeight: contentHeight
    color: "transparent"
    exclusiveZone: -1
    WlrLayershell.namespace: "quickshell-panel"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    onOpenChanged: {
        if (open) {
            panelScreen = Util.focusedScreen();
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

    Rectangle {
        id: card

        anchors.fill: parent
        color: Theme.panelBg
        radius: Theme.panelRadius
        border.width: 1
        border.color: Theme.border

        // Escape closes the panel for the one popup panel whose window takes the
        // keyboard: the notification centre, which holds an xdg popup grab for its
        // search field. The other panels never see a key press — a panel without a
        // grab has no keyboard focus — so they close on Escape through the
        // compositor bind in Panels.qml instead.
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
