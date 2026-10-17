pragma Singleton

// Audio state, shared by the bar readout, the volume OSD and the mixer panel.
//
// Pipewire objects are unbound by default in Quickshell: an unbound node only
// exposes a subset of its properties, and `volume`/`muted` on the audio
// interface read as zero (verified: wpctl reported 0.34 while the unbound node
// reported 0). A PwObjectTracker is what binds them, so this singleton owns the
// trackers and everyone else reads through it.
import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

Singleton {
    id: root

    // Every node is tracked rather than only the default sink: the mixer panel
    // lists per-application streams, and those need binding to be adjustable.
    // There are a handful of nodes on this machine, so this is not a cost.
    PwObjectTracker {
        objects: Pipewire.nodes.values
    }

    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink, Pipewire.defaultAudioSource]
    }

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource

    // Before the initial sync with the pipewire server completes, nodes and the
    // default device can still be missing; the widgets hide rather than show a
    // wrong number.
    readonly property bool ready: Pipewire.ready

    readonly property real volume: root.sink ? root.sink.audio.volume : 0
    readonly property bool muted: root.sink ? root.sink.audio.muted : false
    readonly property string sinkName: root.sink ? root.sink.description : ""
    readonly property bool micMuted: root.source ? root.source.audio.muted : false
    readonly property string sourceName: root.source ? root.source.description : ""

    // Playback streams, for the mixer. Sinks are the devices themselves and are
    // listed separately.
    readonly property var streams: {
        const out = [];
        const nodes = Pipewire.nodes.values;
        for (let i = 0; i < nodes.length; i++) {
            if (nodes[i].isStream)
                out.push(nodes[i]);
        }
        return out;
    }

    readonly property var sinks: {
        const out = [];
        const nodes = Pipewire.nodes.values;
        for (let i = 0; i < nodes.length; i++) {
            if (nodes[i].isSink)
                out.push(nodes[i]);
        }
        return out;
    }

    // The old binds stepped by 5% (waybar's scroll-step) — kept so the muscle
    // memory and the increments are unchanged.
    readonly property real step: 0.05

    function setVolume(v: real): void {
        if (root.sink)
            root.sink.audio.volume = Math.max(0, Math.min(1, v));
    }

    function adjustVolume(delta: real): void {
        if (!root.sink)
            return;
        // Scrolling up while muted should unmute rather than silently change a
        // volume nobody can hear.
        if (root.muted && delta > 0)
            root.sink.audio.muted = false;
        root.setVolume(root.sink.audio.volume + delta);
    }

    function toggleMute(): void {
        if (root.sink)
            root.sink.audio.muted = !root.sink.audio.muted;
    }

    function toggleMicMute(): void {
        if (root.source)
            root.source.audio.muted = !root.source.audio.muted;
    }
}
