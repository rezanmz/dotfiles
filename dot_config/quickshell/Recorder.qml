pragma Singleton

// Whether a screen recording is running.
//
// `wf-recorder` has no state file or IPC — the running process *is* the state, and
// dot_local/bin/record-toggle reads it the same way. So this polls `pgrep` every
// few seconds: one short-lived process, and only while the shell is up. (The old
// waybar spawned its scripts every 2s; this is one `pgrep` per 3s.)
//
// The indicator and any future panel read this, and stopping goes through the
// same script the keybind uses so there is one code path for it.
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property bool recording: false

    readonly property string helper: Quickshell.env("HOME") + "/.local/bin/record-toggle"

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

    // Stop (or start) through the same script the keybind calls.
    Process {
        id: toggle
    }

    function stop(): void {
        if (!root.recording)
            return;
        toggle.command = [root.helper];
        toggle.running = true;
    }

    function toggleRecording(): void {
        toggle.command = [root.helper];
        toggle.running = true;
    }
}
