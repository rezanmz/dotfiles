pragma Singleton

// The screen recording: whether one is running, and the one place
// `wf-recorder` is started and stopped.
//
// `wf-recorder` has no state file or IPC — the running process *is* the state.
// So this polls `pgrep` every few seconds: one short-lived process, and only
// while the shell is up. (The old waybar spawned its scripts every 2s; this is
// one `pgrep` per 3s.) Start/stop optimistically flip `recording`, and the
// probe is re-run right after both, so the indicator never lags a state change
// by more than the probe itself.
//
// The naming of the file and the region selection live in Capture.qml; this is
// only the process. Stopping sends SIGINT, which is what makes wf-recorder
// finalise the file cleanly (the old script did the same).
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property bool recording: false

    // When the running recording started (epoch ms) and how long it has run, in
    // whole seconds — the bar's stop pill counts it up in mm:ss, the way the
    // macOS menu-bar stop button shows its elapsed time. A recording the probe
    // finds already running (started outside this shell) counts from the moment
    // it was discovered.
    property real startedAt: 0
    property int elapsed: 0

    onRecordingChanged: {
        if (root.recording) {
            root.startedAt = Date.now();
            root.elapsed = 0;
        }
    }

    // One tick a second, and only while a recording runs; the pill's mm:ss is
    // the only reader.
    Timer {
        interval: 1000
        running: root.recording
        repeat: true
        onTriggered: root.elapsed = Math.floor((Date.now() - root.startedAt) / 1000)
    }

    Process {
        id: probe

        command: ["pgrep", "-x", "wf-recorder"]
        running: true
        onExited: (exitCode, exitStatus) => root.recording = exitCode === 0
    }

    Timer {
        interval: 3000
        running: true
        repeat: true
        onTriggered: probe.running = true
    }

    // The recording itself. Runs until SIGINT; onExited just re-probes.
    Process {
        id: wf
        onExited: (exitCode, exitStatus) => probe.running = true
    }

    // SIGINT (so the file is finalised), then wait for the process to actually
    // be gone and re-probe: `recording` flips exactly when the file is complete,
    // not up to one poll later.
    Process {
        id: stopper

        command: ["sh", "-c", "pkill -INT -x wf-recorder; sleep 0.7"]
        onExited: (exitCode, exitStatus) => probe.running = true
    }

    // Health check after a start: on a GPU where the encoder is broken
    // wf-recorder dies within a moment, and the probe corrects the state.
    Timer {
        id: failCheck
        interval: 1200
        onTriggered: probe.running = true
    }

    // `geometry` is slurp's "x,y WxH" for a region, "" for the whole screen;
    // `audio` is a pulse source name for wf-recorder --audio=<device>, "" for
    // a silent recording.
    function start(outFile: string, geometry: string, audio: string): void {
        if (root.recording)
            return;
        const args = ["wf-recorder"];
        if (geometry !== "")
            args.push("-g", geometry);
        if (audio !== "")
            args.push("--audio=" + audio);
        args.push("-f", outFile);
        wf.command = args;
        wf.running = true;
        root.recording = true;
        failCheck.restart();
    }

    function stop(): void {
        if (!root.recording)
            return;
        stopper.running = true;
    }
}
