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
    //
    // The default sink and source are deliberately NOT tracked separately.
    // A tracker over [Pipewire.defaultAudioSink, Pipewire.defaultAudioSource]
    // crashes quickshell 0.3.2 when the default device goes away (USB audio
    // removed on resume from suspend, or the sink unplugged):
    //
    //   1. The device's pipewire node is destroyed. That destroys the
    //      PwNodeIface cached on the node.
    //   2. The tracker's `objects` binding re-evaluates on objectsChanged and
    //      asks for Pipewire.defaultAudioSink again.
    //   3. Pipewire::defaultAudioSink() returns PwNodeIface::instance(node),
    //      the iface cached on the node that is already being destroyed.
    //   4. That pointer is dangling. Qt wraps it, and
    //      QQmlData::wasDeleted() dereferences the freed QObjectPrivate:
    //      SIGSEGV in QV4::QQmlTypeWrapper::lookupSingletonProperty.
    //
    // It is redundant anyway: the default sink and source are members of
    // Pipewire.nodes, so this tracker already binds them. The one thing the
    // default devices need is that they are bound at all, and the node
    // tracker gives them that.
    PwObjectTracker {
        objects: Pipewire.nodes.values
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

    // Input devices, for the panel's input picker: the same list as sinks,
    // from the other side. A node is a source when its type carries the Source
    // flag and not the Sink one (there is no `isSource` property in this
    // Quickshell — only `isSink`/`isStream`/`type`, and `type` is the flag
    // mask: Audio=1, Stream=4, Source=8, Sink=16).
    //
    // Then one monitor entry per sink, because the pulse layer (`pactl`,
    // pavucontrol) models a sink's monitor as a selectable source and this is
    // the machine's only input: there is no microphone, the default input is
    // the Pebble's monitor, and Quickshell's defaultAudioSource is null for
    // `...monitor` names. Without the monitors the picker would have nothing
    // to list and could not show the current default at all. Each entry's
    // `name` is the pulse source name `pactl set-default-source` takes: the
    // node name for a real source, `<sink>.monitor` for a monitor.
    readonly property var sources: {
        const out = [];
        const nodes = Pipewire.nodes.values;
        for (let i = 0; i < nodes.length; i++) {
            const n = nodes[i];
            if (!n.isStream && !n.isSink && (n.type & 8) !== 0)
                out.push(n);
        }
        for (let i = 0; i < nodes.length; i++) {
            const n = nodes[i];
            if (n.isSink)
                out.push({
                    name: n.name + ".monitor",
                    description: "Monitor of " + (n.description || n.name)
                });
        }
        return out;
    }

    // The old binds stepped by 5% (waybar's scroll-step) — kept so the muscle
    // memory and the increments are unchanged.
    readonly property real step: 0.05

    function setVolume(v: real): void {
        if (root.sink)
            // Whole percent, so every step displays as exactly five points
            // (75 -> 70 -> 65): the device quantises to its own granularity, and
            // a raw 5 % step landing 0.1 % off nominal could straddle a rounding
            // boundary and read as six (Reza's 75 -> 69). The device still holds
            // its own value within half a percent — inaudible — and the number
            // shown always matches the step.
            root.sink.audio.volume = Math.round(Math.max(0, Math.min(1, v)) * 100) / 100;
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
