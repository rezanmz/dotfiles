pragma Singleton

// Design tokens for the whole shell: one palette, one metric set, one place to
// change them. Mirrors dot_config/hypr/modules/00-theme.lua (the canonical
// Dracula table) and the values the waybar/dunst configs used, so the bar keeps
// the look it had before the switch.
import Quickshell
import QtQuick

Singleton {
    // ---- palette -------------------------------------------------------
    readonly property color bg: "#282a36"
    readonly property color fg: "#f8f8f2"
    readonly property color selection: "#44475a"
    readonly property color comment: "#6272a4"
    readonly property color cyan: "#8be9fd"
    readonly property color green: "#50fa7b"
    readonly property color orange: "#ffb86c"
    readonly property color pink: "#ff79c6"
    readonly property color purple: "#bd93f9"
    readonly property color red: "#ff5555"
    readonly property color yellow: "#f1fa8c"

    // ---- surfaces ------------------------------------------------------
    // The bar keeps waybar's rgba(40,42,54,0.92) so the layer-rule blur still
    // has something to sample through.
    readonly property color barBg: alpha(bg, 0.92)
    readonly property color panelBg: alpha(bg, 0.97)
    readonly property color hoverBg: alpha(selection, 0.55)
    readonly property color activeBg: alpha(selection, 0.9)
    readonly property color border: selection
    readonly property color borderStrong: comment
    readonly property color shadow: alpha("#000000", 0.35)

    // ---- metrics -------------------------------------------------------
    readonly property int barHeight: 44
    readonly property int fontSize: 15
    readonly property int fontSizeSmall: 13
    readonly property int fontSizeHeading: 16
    readonly property string fontFamily: "Hack Nerd Font"
    readonly property int modulePadding: 11
    readonly property int margin: 6
    readonly property int spacing: 6
    readonly property int radius: 6
    readonly property int panelRadius: 10
    readonly property int panelPadding: 12
    readonly property int panelWidth: 340
    readonly property int animationFast: 120
    readonly property int animationNormal: 180

    // ---- helpers -------------------------------------------------------
    function alpha(c: color, a: real): color {
        return Qt.rgba(c.r, c.g, c.b, a);
    }

    // Blend two colors; used for hover/press states that must survive being
    // drawn over a translucent bar.
    function mix(a: color, b: color, t: real): color {
        return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, a.a + (b.a - a.a) * t);
    }

    // Accent color for a 0-100 value: green, then orange past `warn`, red past
    // `crit`. Used by the load/temperature/disk readouts so a hot or full
    // machine looks different from an idle one.
    function level(v: real, warn: real, crit: real, base: color): color {
        if (v >= crit)
            return red;
        if (v >= warn)
            return orange;
        return base;
    }
}
