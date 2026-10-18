pragma Singleton

// Night light: a warm screen tint with no extra packages (no hyprsunset, no
// wlsunset, no gamma control).
//
// One full-screen window on the overlay layer, above everything including
// fullscreen windows. It takes no input at all (empty click mask) and reserves
// nothing (exclusiveZone: -1), so it is invisible to everything but the eye:
// one warm orange (#ff8c42) at one alpha. `strength` scales the alpha (0..1),
// the presets are just named strengths, and toggling animates the alpha so the
// screen warms up and cools down instead of snapping.
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs

Singleton {
    id: root

    property bool enabled: false

    // 0..1; the alpha the tint is drawn at when enabled.
    property real strength: 0.1

    // Presets: warm is the default tint, warmer for late nights.
    readonly property real strengthWarm: 0.1
    readonly property real strengthWarmer: 0.22

    function setWarm(): void {
        root.strength = root.strengthWarm;
        root.enabled = true;
    }

    function setWarmer(): void {
        root.strength = root.strengthWarmer;
        root.enabled = true;
    }

    // The alpha actually drawn: follows `enabled` and `strength`, animated.
    property real shown: 0

    onEnabledChanged: root.updateShown()
    onStrengthChanged: root.updateShown()
    Component.onCompleted: root.updateShown()

    function updateShown(): void {
        root.shown = root.enabled ? Math.max(0, Math.min(1, root.strength)) : 0;
    }

    // The tint itself. Stays mapped at alpha 0 while off (an unmapped window
    // would snap on instead of fading), and never takes a click.
    PanelWindow {
        id: tint

        screen: Util.focusedScreen()
        anchors.top: true
        anchors.bottom: true
        anchors.left: true
        anchors.right: true
        exclusiveZone: -1
        color: Theme.alpha("#ff8c42", root.shown)
        mask: Region {}
        WlrLayershell.namespace: "quickshell-nightlight"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        Behavior on color {
            ColorAnimation {
                duration: Theme.animationNormal
                easing.type: Easing.InOutCubic
            }
        }
    }
}
