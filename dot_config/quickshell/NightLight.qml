pragma Singleton

// Night light and screen brightness, done the way the compositor intends.
//
// Not an overlay. A full-screen orange surface is a screen shader in effect: it
// washes the whole image instead of moving the white point, it can only add
// orange rather than take blue away, and being a real surface it ended up in
// every screenshot and recording. The first version of this file did exactly that
// and was, fairly, called terrible.
//
// hyprsunset applies a colour transform matrix through
// hyprland-ctm-control-v1 — the same mechanism GNOME and KDE use — so the white
// point genuinely moves, the pixel data is untouched (nothing shows up in a
// screenshot), and the same interface offers a gamma ramp, which is how you dim a
// desktop monitor whose brightness cannot be driven in software.
//
// The daemon is a systemd user service (`hyprsunset.service`), not a child of the
// shell: the transform outlives any one shell, which is also why the old tint
// kept switching itself off whenever the shell restarted. This file only sends
// requests over the daemon's socket:
//
//   temperature <K>    white point, 1000-20000 (also clears identity)
//   gamma <percent>    perceived brightness, 0-100% of the panel
//   identity <bool>    temperature filter off, gamma left alone
//
// Requests are idempotent, so a request lost to a coalesced read during a slider
// drag is corrected by the next one.
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    // The temperature filter. Off means identity: no colour change at all, which
    // is what "night light off" has to look like.
    property bool enabled: false

    // Kelvin; lower is warmer. 6500 is neutral daylight.
    property int temperature: 4500

    // Gamma as a percentage of the panel's native output: 100 leaves the ramp
    // untouched, lower dims. This is a software brightness control, and the only
    // one a desktop monitor without DDC can have.
    property int brightness: 100

    readonly property int neutral: 6500

    // The daemon is started with --gamma_max 150 (see the unit): above 100% gamma
    // lifts perceived brightness past what the panel's own controls allow, which
    // is the only way up a desktop monitor has.
    readonly property int brightnessMax: 150

    // The named temperatures the panel offers, in the convention everyone else
    // uses: warm is a gentle evening shift, warmer is late night.
    readonly property int warm: 4500
    readonly property int warmer: 3500

    // Did the daemon answer? The panel says so rather than pretending to control
    // something that is not running.
    property bool available: false
    property string lastReply: ""

    readonly property string socketPath: {
        const runtime = Quickshell.env("XDG_RUNTIME_DIR") || "/run/user/1000";
        const signature = Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") || "";
        return runtime + "/hypr/" + signature + "/.hyprsunset.sock";
    }

    function setWarm(): void {
        root.temperature = root.warm;
        root.enabled = true;
    }

    function setWarmer(): void {
        root.temperature = root.warmer;
        root.enabled = true;
    }

    // The two gestures the bar offers: one wheel notch of brightness, one of
    // warmth. Shared so the readouts, the bar background and the panel's sliders
    // all move by the same amounts.
    function adjustBrightness(steps: int): void {
        root.brightness = Math.max(60, Math.min(root.brightnessMax, root.brightness + steps * 5));
    }

    function adjustWarmth(steps: int): void {
        root.temperature = Math.max(2500, Math.min(6500, root.temperature - steps * 250));
        root.enabled = true;
    }

    // ---- the daemon's socket ---------------------------------------------

    // One request per connection, then hang up.
    //
    // hyprsunset serves a single client at a time: it accepts a connection and
    // sits in a read loop until that client goes away. Holding the socket open for
    // the session would therefore lock every other tool out of the daemon (it also
    // made this file hard to verify). Connecting per request costs microseconds,
    // and requests are idempotent — a slider drag overwrites the pending one
    // rather than queueing, which is exactly what you want.
    Socket {
        id: socket

        path: root.socketPath
        connected: false

        // The override hooks the docs suggest (onSocketConnected & co) are not
        // assignable properties in this build; the signals are.
        onConnectionStateChanged: {
            if (!socket.connected)
                return;
            root.available = true;
            if (root.pending !== "") {
                socket.write(root.pending);
                socket.flush();
                root.pending = "";
            } else {
                // A connection with nothing pending means the daemon was not
                // there before: it restarted, so it lost the transform and the
                // whole state has to go back. Requests are idempotent.
                root.applyAll();
                return;
            }
            hangUp.restart();
        }

        onError: root.available = false
    }

    // The request waiting for a connection: only the newest one matters.
    property string pending: ""

    Timer {
        id: hangUp

        interval: 40
        onTriggered: socket.connected = false
    }

    function send(request: string): void {
        root.pending = request;
        if (socket.connected) {
            // Already open: send this one and restart the hang-up window.
            socket.write(request);
            socket.flush();
            root.pending = "";
            hangUp.restart();
            return;
        }
        socket.connected = true;
    }

    // Everything the daemon needs to reproduce the current state, sent on connect
    // (and by the panel's "reapply" path, e.g. after a monitor change).
    // What the panel calls (and the connect path) to push the whole state: the
    // second request is queued behind the first by send()'s single pending slot.
    function applyAll(): void {
        send(root.enabled ? "temperature " + root.temperature : "identity true");
        send("gamma " + root.brightness);
    }

    onEnabledChanged: {
        if (root.enabled)
            send("temperature " + root.temperature);
        else
            send("identity true");
    }

    onTemperatureChanged: {
        if (root.enabled)
            send("temperature " + Math.max(1000, Math.min(20000, root.temperature)));
    }

    onBrightnessChanged: send("gamma " + Math.max(10, Math.min(root.brightnessMax, root.brightness)))

    Component.onCompleted: {
        send("temperature");
        send("gamma");
    }
}
