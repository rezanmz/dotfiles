pragma Singleton

// Idle-inhibitor state, shared by the bar widget and its panel.
//
// The inhibitor blocks *hypridle* — display off, screen lock, suspend (see
// dot_config/hypr/hypridle.conf).
//
// Three ways it can be held, in the order they matter:
//   auto    — something is playing. A film or a YouTube tab should never let the
//             screen blank. Chrome only inhibits for *fullscreen* video, so this
//             covers the windowed case too, and any player that never asked.
//   timed   — you asked for N minutes; it releases itself, so a forgotten hold
//             cannot leave the session unlocked for a week.
//   forever — you asked for no deadline.
import QtQuick
import Quickshell
import Quickshell.Services.Mpris
import Quickshell.Wayland

Singleton {
    id: root

    // Media-triggered holding. On by default; the panel can turn it off.
    property bool autoInhibit: true

    property bool indefinite: false
    property int minutes: 0
    property real deadline: 0

    readonly property var playing: {
        const players = Mpris.players.values;
        for (let i = 0; i < players.length; i++) {
            if (players[i].isPlaying)
                return players[i];
        }
        return null;
    }

    readonly property bool auto: root.autoInhibit && root.playing !== null
    readonly property bool manual: root.indefinite || root.deadline > 0
    readonly property bool held: root.auto || root.manual

    readonly property int remaining: root.deadline > 0 ? Math.max(0, Math.round((root.deadline - Date.now()) / 1000)) : 0

    function holdFor(m: int): void {
        if (m <= 0) {
            root.indefinite = true;
            root.deadline = 0;
        } else {
            root.indefinite = false;
            root.minutes = m;
            root.deadline = Date.now() + m * 60000;
        }
    }

    function holdIndefinitely(): void {
        root.holdFor(0);
    }

    function release(): void {
        root.indefinite = false;
        root.deadline = 0;
    }

    function toggle(): void {
        if (root.manual)
            root.release();
        else
            root.holdIndefinitely();
    }

    // Short by design: this is a bar readout.
    readonly property string label: {
        if (root.auto)
            return "playing";
        if (!root.manual)
            return "idle";
        if (root.indefinite)
            return "hold";
        const total = root.remaining;
        const h = Math.floor(total / 3600);
        const m = Math.floor((total % 3600) / 60);
        if (h > 0)
            return "hold " + h + "h" + Util.pad(m, 2) + "m";
        if (m > 0)
            return "hold " + m + "m";
        return "hold " + total + "s";
    }

    // The bar is always mapped, so the inhibitor lives exactly as long as the
    // hold does.
    IdleInhibitor {
        enabled: root.held
        window: Panels.barWindow
    }

    Timer {
        interval: 1000
        running: root.deadline > 0
        repeat: true
        onTriggered: {
            if (Date.now() >= root.deadline)
                root.release();
        }
    }
}
