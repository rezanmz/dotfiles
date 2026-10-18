pragma Singleton

// The volume feedback tick, macOS's "Play feedback when volume is changed".
//
// One short sound per step, from the freedesktop sound theme — the same
// audio-volume-change.oga every desktop environment plays. It is hooked off the
// sink's volume signal rather than off our own setter, so the volume keys (which
// run wpctl straight from a Hyprland bind, never touching the shell), the bar's
// scroll, the mixer and anything else that changes the sink all get the same
// feedback, exactly as macOS's setting does.
//
// Two things it deliberately does not do: play for the burst of changes pipewire
// emits while enumerating devices at shell startup, and play for mute. Mute is a
// different action and macOS plays nothing for it.
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property bool enabled: true

    // A scroll can emit several changes in a few milliseconds; one tick per step
    // is what the ear expects, ten is a rattle.
    property double lastTick: 0
    readonly property int minGap: 70

    function volumeTick(): void {
        if (!root.enabled)
            return;
        const now = Date.now();
        if (now - root.lastTick < root.minGap)
            return;
        root.lastTick = now;
        // Restart rather than queue: the sound is ~100 ms and a fast scroll should
        // follow the wheel, not lag behind it.
        tick.running = false;
        tick.running = true;
    }

    // The tick is played on the *default* sink, explicitly.
    //
    // pw-play follows pipewire's active node rather than the default one, and
    // those differ as soon as anything else has played recently: with the default
    // on the desktop speakers but the active node on the monitor's HDMI output,
    // a plain pw-play went to the monitor — which has no speakers — and the
    // feedback was silent. Naming the default sink removes the ambiguity.
    Process {
        id: tick

        command: root.tickCommand()

        Component.onCompleted: command = root.tickCommand()
    }

    function tickCommand(): var {
        const sink = Sound.sink && Sound.sink.name ? Sound.sink.name : "";
        const sound = "/usr/share/sounds/freedesktop/stereo/audio-volume-change.oga";
        return sink === "" ? ["pw-play", sound] : ["pw-play", "--target", sink, sound];
    }
}
