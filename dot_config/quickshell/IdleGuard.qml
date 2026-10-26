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
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Wayland

Singleton {
    id: root

    // Media-triggered holding. On by default; the panel can turn it off.
    property bool autoInhibit: true

    // Cinema mode: a fullscreen window is focused, so the screen should not blank
    // or lock while it is up. Set by Cinema.qml.
    property bool cinema: false

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
    readonly property bool held: root.auto || root.manual || root.cinema

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
        if (root.cinema)
            return "cinema";
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

    // ---- suspend after inactivity -------------------------------------------
    // Minutes of inactivity before the machine suspends; 0 turns the timer off.
    //
    // This is the shell's timer rather than a hypridle listener because hypridle
    // reads its timeouts from a static config file, and this one is adjustable
    // from the panel. hypridle keeps the blank (4 min) and lock (5 min) timers,
    // so by the time this fires the screen is off and the session is locked.
    //
    // It watches the same ext-idle-notify the compositor gives hypridle, so the
    // IdleInhibitor above silences it exactly like it silences hypridle: a hold, a
    // playing video or cinema mode keeps the machine awake here too.
    property int suspendMinutes: 20
    property bool loaded: false

    IdleMonitor {
        id: suspendMonitor

        enabled: root.loaded && root.suspendMinutes > 0
        timeout: Math.max(1, root.suspendMinutes) * 60
        respectInhibitors: true

        onIsIdleChanged: {
            if (suspendMonitor.isIdle)
                Quickshell.execDetached(["systemctl", "suspend-then-hibernate"]);
        }
    }

    // Read once at startup. The file is created empty if missing, and a corrupt
    // or unparseable file degrades to the defaults instead of an error.
    Process {
        id: stateLoad

        command: ["sh", "-c", "mkdir -p \"$(dirname \"$1\")\" && touch \"$1\" && cat \"$1\"", "sh", Quickshell.statePath("idle.json")]
        running: true

        stdout: StdioCollector {
            id: stateLoadOut

            waitForEnd: true
            onStreamFinished: {
                try {
                    const parsed = JSON.parse(stateLoadOut.text);
                    if (parsed !== null && typeof parsed === "object") {
                        if (typeof parsed.suspendMinutes === "number")
                            root.suspendMinutes = parsed.suspendMinutes;
                        if (typeof parsed.autoInhibit === "boolean")
                            root.autoInhibit = parsed.autoInhibit;
                    }
                } catch (e) {
                    // Missing or corrupt: keep the defaults.
                }
                root.loaded = true;
            }
        }
    }

    Process {
        id: stateSave

        property string json: "{}"
        command: ["sh", "-c", "mkdir -p \"$(dirname \"$1\")\" && printf %s \"$2\" > \"$1\"", "sh", Quickshell.statePath("idle.json"), stateSave.json]
    }

    // Written whenever the panel changes something, so the choice survives a
    // reboot. json is assigned first, then the process is restarted so the
    // command binding picks the new payload up.
    function saveState(): void {
        stateSave.json = JSON.stringify({
            "suspendMinutes": root.suspendMinutes,
            "autoInhibit": root.autoInhibit
        });
        stateSave.running = true;
    }

    function setSuspend(minutes: int): void {
        root.suspendMinutes = minutes;
        root.saveState();
    }

    function setAutoInhibit(on: bool): void {
        root.autoInhibit = on;
        root.saveState();
    }
}
