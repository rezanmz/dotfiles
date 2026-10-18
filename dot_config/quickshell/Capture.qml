pragma Singleton

// Screenshots and screen recordings: the actions, and the options the ⇧⌘5
// toolbar sets.
//
// This is the macOS capture model: ⌘⇧3/4-style direct captures (`screen`,
// `selection`, `window` over IPC), a toolbar for the options, a floating
// thumbnail afterwards, files named "Screenshot 2026-10-17 at 20.15.32.png".
// The old capture lived in two scripts (screenshot, record-toggle) that froze
// the screen and piped tools together; those scripts are now thin wrappers over
// this IPC, so there is exactly one implementation.
//
// Every capture is grim, a region comes from Selection.qml's own crosshair (the
// shell draws it — see that file for why slurp was dropped), the focused window
// is read from hyprctl's JSON, and
// recordings are wf-recorder via Recorder.qml, which owns the process and the
// `recording` state. All of it runs as child processes with argv lists —
// Quickshell.execDetached takes a *string* (see Launcher.qml), so filenames
// with spaces would break there.
//
// Notification policy: a capture notifies only when there is no thumbnail to
// show. The thumbnail is the feedback on macOS (a notification would stack in
// the same corner and open the notification centre beside it); when the
// thumbnail is off there is nothing else to say "saved", so notify-send does.
// Recordings always notify on start/stop: the REC pill says "running" but
// never where the file went.
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    // ---- options, shared with panels/Capture.qml ----------------------
    // The toolbar's segmented controls write these; the captures read them.
    property string mode: "screen"          // "screen" | "selection" | "window"
    property string saveTo: "desktop"       // "desktop" | "documents" | "pictures" | "clipboard" | "other"
    property int timer: 0                   // 0 | 5 | 10 seconds
    property bool thumbnail: true           // show the floating thumbnail after a capture
    property bool showPointer: false        // macOS's Show Mouse Pointer (grim -c)
    property bool recordingMode: false      // the toolbar is showing its recording controls
    property string recordTarget: "selection" // "screen" | "selection"
    property string mic: "none"             // "none" | "default" (the default source) | "system" (the sink monitor)
    // macOS's "Other Location": a typed directory, used when saveTo is "other".
    property string customDir: ""
    // macOS's "Remember Last Selection": the previous rectangle comes back
    // pre-drawn, ready to take with Enter or to replace with a new drag — macOS
    // does not skip the crosshair, and skipping it silently was how a ⌘⇧4 press
    // looked like it did nothing at all. The toolbar's Reselect button forces a
    // fresh crosshair with nothing pre-drawn.
    property bool rememberSelection: false
    property string lastGeometry: ""
    property bool reselect: false

    // ---- timer countdown (the toolbar displays it) --------------------
    property int countdown: 0
    property string countdownMode: ""

    // ---- floating thumbnail state (ScreenshotThumb.qml reads it) -------
    property string thumbPath: ""
    property bool thumbTemp: false          // a clipboard capture: delete the file with the thumbnail
    property bool thumbVideo: false         // the thumbnail is a recording, not an image
    property bool thumbVisible: false

    // The file the running recording will finalise into.
    property string recordingFile: ""

    // The default source for the Microphone option, resolved once at startup
    // (pactl names it in one line; wf-recorder takes it as --audio=<device>).
    // Empty means no detection worked and the option degrades to None-only.
    property string micName: ""
    readonly property bool micAvailable: root.micName !== ""

    // System audio: the default sink's monitor, which is what "record what you
    // hear" means in pipewire. `pactl get-default-sink` gives the sink, and its
    // monitor is always <sink>.monitor.
    property string sinkMonitorName: ""
    readonly property bool systemAudioAvailable: root.sinkMonitorName !== ""

    Process {
        id: sinkProc

        command: ["pactl", "get-default-sink"]
        running: true
        stdout: StdioCollector {
            id: sinkOut

            waitForEnd: true
            onStreamFinished: {
                const sink = sinkOut.text.trim();
                root.sinkMonitorName = sink === "" ? "" : sink + ".monitor";
            }
        }
    }

    readonly property string home: Quickshell.env("HOME")

    // ---- the one in-flight pipeline -----------------------------------
    // A capture (or the slurp before a recording) is a chain of child
    // processes; this is its state, cleared when the chain ends either way.
    property string pendingKind: ""         // "capture" | "record"
    property string pendingMode: ""         // capture mode / record target
    property string pendingFile: ""
    property string pendingDir: ""
    property bool pendingTemp: false
    // Set for the length of one pipeline by the ⌃⌘⇧3/⌃⌘⇧4 shortcuts, so the
    // Control modifier is per-invocation like macOS and does not leave Save to
    // stuck on Clipboard for the next ⌘⇧3.
    property bool pendingClipboard: false
    property string pendingGeometry: ""     // filled in by slurp / hyprctl
    property bool sattyTemp: false
    property string sattyPath: ""

    // "2026-10-17 at 20.15.32" — the macOS naming scheme.
    function stamp(): string {
        const d = new Date();
        return d.getFullYear() + "-" + Util.pad2(d.getMonth() + 1) + "-" + Util.pad2(d.getDate()) + " at " + Util.pad2(d.getHours()) + "." + Util.pad2(d.getMinutes()) + "." + Util.pad2(d.getSeconds());
    }

    // Where a screenshot lands, and whether it is a real save. Clipboard
    // captures go to a temp file: wl-copy reads it, the thumbnail shows it,
    // and it is deleted when the thumbnail goes away (macOS keeps no file
    // either, but does show the thumbnail).
    function makeTarget(): void {
        const name = "Screenshot " + root.stamp() + ".png";
        if (root.pendingClipboard || root.saveTo === "clipboard") {
            root.pendingDir = "/tmp";
            root.pendingFile = "/tmp/" + name;
            root.pendingTemp = true;
            return;
        }
        if (root.saveTo === "documents") {
            root.pendingDir = root.home + "/Documents";
        } else if (root.saveTo === "pictures") {
            root.pendingDir = root.home + "/Pictures/Screenshots";
        } else if (root.saveTo === "other" && root.customDir !== "") {
            root.pendingDir = root.customDir;
        } else {
            root.pendingDir = root.home + "/Desktop";
        }
        root.pendingFile = root.pendingDir + "/" + name;
        root.pendingTemp = false;
    }

    // ---- entry points --------------------------------------------------

    // The toolbar's Capture button: take the shot in the selected mode.
    function capture(): void {
        root.beginCapture(root.mode);
    }

    function beginCapture(m: string): void {
        if (countdownTimer.running) {
            countdownTimer.stop();
            root.countdown = 0;
        }
        root.countdownMode = m;
        if (root.timer > 0) {
            root.countdown = root.timer;
            // The remaining seconds have to be visible somewhere; the toolbar
            // is that somewhere, so a timed capture opens it even from a
            // keybind (it closes again the moment the shot is taken).
            if (Panels.current !== "capture")
                Panels.openByName("capture");
            countdownTimer.restart();
        } else {
            root.fireCapture(m);
        }
    }

    Timer {
        id: countdownTimer
        interval: 1000
        repeat: true
        onTriggered: {
            root.countdown -= 1;
            if (root.countdown <= 0) {
                countdownTimer.stop();
                root.fireCapture(root.countdownMode);
            }
        }
    }

    function fireCapture(m: string): void {
        // The toolbar must not be in its own screenshot: close whatever panel
        // is open and wait out the close animation before grim runs.
        const wasOpen = Panels.anyOpen;
        if (wasOpen)
            Panels.close();
        root.pendingKind = "capture";
        root.pendingMode = m;
        root.pendingGeometry = "";
        root.makeTarget();
        fireDelay.interval = wasOpen ? 260 : 1;
        fireDelay.restart();
    }

    Timer {
        id: fireDelay
        onTriggered: root.runPrep()
    }

    // Recordings always land in ~/Videos/Recordings (macOS: ~/Movies), named the
    // way macOS names them: "Screen Recording 2026-10-18 at 10.32.45.mov".
    function beginRecord(target: string): void {
        if (Recorder.recording)
            return;
        root.pendingKind = "record";
        root.pendingMode = target;
        root.pendingDir = root.home + "/Videos/Recordings";
        root.pendingFile = root.pendingDir + "/Screen Recording " + root.stamp() + ".mov";
        root.pendingTemp = false;
        root.pendingGeometry = "";
        root.runPrep();
    }

    function recordScreen(): void {
        root.beginRecord("screen");
    }

    function recordSelection(): void {
        root.beginRecord("selection");
    }

    // "Record a window": pick one with the same overlay the capture uses, then
    // record that rectangle. wf-recorder takes one fixed region per recording, so
    // a window that moves (or is tiled elsewhere) is not followed — macOS follows
    // it; this records where it was when you picked it.
    function recordWindow(): void {
        root.beginRecord("window");
    }

    function stopRecording(): void {
        if (!Recorder.recording)
            return;
        Recorder.stop();
        if (root.recordingFile !== "") {
            const file = root.recordingFile;
            root.recordingFile = "";
            // macOS shows the recording's floating thumbnail when it stops; the
            // notification stays because the thumbnail never says where the file
            // went (macOS has the Finder for that, the shell does not).
            if (root.thumbnail) {
                root.thumbPath = file;
                root.thumbTemp = false;
                root.thumbVideo = true;
                root.thumbVisible = true;
            }
            root.notify("recording", "Recording saved", file);
        }
    }

    function toggleRecording(): void {
        if (Recorder.recording)
            root.stopRecording();
        else
            root.beginRecord(root.recordTarget);
    }

    Process {
        id: micProc
        command: ["pactl", "get-default-source"]
        running: true
        stdout: StdioCollector {
            id: micOut
            waitForEnd: true
            onStreamFinished: root.micName = micOut.text.trim()
        }
    }

    // ---- the pipeline --------------------------------------------------

    function runPrep(): void {
        prepProc.command = ["mkdir", "-p", root.pendingDir];
        prepProc.running = true;
    }

    Process {
        id: prepProc
        onExited: root.continuePending()
    }

    function continuePending(): void {
        // Both kinds of pipeline run through the same dispatch: what differs is
        // only what happens once the geometry is known — a record starts
        // wf-recorder on it, a capture runs grim (see afterSelection).
        //
        // Whole-screen work skips the crosshair entirely; a region or a window
        // opens Selection, which reports back through chosen()/cancelled().
        if (root.pendingMode === "screen") {
            if (root.pendingKind === "record")
                root.startRecording("");
            else
                root.runGrim();
            return;
        }
        if (root.pendingMode === "selection") {
            // macOS's "Remember Last Selection" comes back pre-drawn rather than
            // skipping the crosshair; the toolbar's Reselect clears it.
            const preset = (root.rememberSelection && !root.reselect) ? root.lastGeometry : "";
            root.reselect = false;
            Selection.begin("region", preset);
        } else if (root.pendingMode === "window") {
            Selection.begin("window", "");
        } else {
            root.runGrim();
        }
    }

    // The overlay is gone by the time this runs; the wait covers the frame it
    // takes the compositor to unmap it.
    Timer {
        id: afterSelection

        onTriggered: {
            if (root.pendingKind === "record")
                root.startRecording(root.pendingGeometry);
            else
                root.runGrim();
        }
    }

    // The crosshair is the shell's own window (Selection.qml); it hands back the
    // geometry and is already hidden by then, so the capture cannot include the
    // dim or the border. A cancel is silent, like ⌘⇧4's Escape.
    Connections {
        target: Selection

        function onChosen(geometry: string): void {
            root.pendingGeometry = geometry;
            if (root.rememberSelection)
                root.lastGeometry = geometry;
            // The overlay hid itself on commit; give the compositor a frame to put
            // the screen back before anything reads it, so neither the shot nor the
            // recording's first frame has the dim in it.
            afterSelection.interval = 160;
            afterSelection.restart();
        }

        function onCancelled(): void {
            root.clearPending();
        }
    }

    function runGrim(): void {
        const base = root.pendingGeometry !== "" ? ["grim", "-g", root.pendingGeometry] : ["grim"];
        // macOS's Show Mouse Pointer: grim's own cursor flag, so the pointer is
        // drawn where it actually is rather than composited in afterwards.
        grimProc.command = root.showPointer ? base.concat(["-c", root.pendingFile]) : base.concat([root.pendingFile]);
        grimProc.running = true;
    }

    Process {
        id: grimProc
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0)
                root.captureDone();
            else
                root.clearPending();
        }
    }

    function captureDone(): void {
        const file = root.pendingFile;
        const temp = root.pendingTemp;
        root.clearPending();
        if (root.pendingClipboard || root.saveTo === "clipboard") {
            copyProc.command = ["sh", "-c", 'wl-copy --type image/png < "$1"', "sh", file];
            copyProc.running = true;
        }
        if (root.thumbnail) {
            // A new thumbnail replaces the old one; a temp it replaces is gone
            // with it, or it would leak in /tmp.
            if (root.thumbVisible && root.thumbTemp && root.thumbPath !== file) {
                rmProc.command = ["rm", "-f", root.thumbPath];
                rmProc.running = true;
            }
            root.thumbPath = file;
            root.thumbTemp = temp;
            root.thumbVideo = false;
            root.thumbVisible = true;
        } else {
            if (temp) {
                rmProc.command = ["rm", "-f", file];
                rmProc.running = true;
            }
            if (root.pendingClipboard || root.saveTo === "clipboard")
                root.notify("screenshot", "Screenshot copied", "to the clipboard");
            else
                root.notify("screenshot", "Screenshot saved", file);
        }
    }

    function startRecording(geom: string): void {
        root.recordingFile = root.pendingFile;
        const audio = root.mic === "system" ? root.sinkMonitorName : (root.mic === "default" ? root.micName : "");
        root.clearPending();
        root.recordingMode = true;
        Recorder.start(root.recordingFile, geom, audio);
        root.notify("recording", "Recording started", "the REC pill in the bar stops it");
    }

    // ---- thumbnail -----------------------------------------------------

    function dismissThumb(): void {
        root.thumbVisible = false;
        root.thumbVideo = false;
        if (root.thumbTemp && root.thumbPath !== "") {
            rmProc.command = ["rm", "-f", root.thumbPath];
            rmProc.running = true;
        }
        root.thumbPath = "";
        root.thumbTemp = false;
    }

    // Clicking the thumbnail opens the annotator (macOS opens Markup) and the
    // thumbnail goes away. A temp file must outlive the thumbnail long enough
    // for satty to read it, so it is deleted when satty exits instead.
    function annotate(): void {
        const file = root.thumbPath;
        if (file === "")
            return;
        root.sattyTemp = root.thumbTemp;
        root.sattyPath = file;
        root.thumbVisible = false;
        root.thumbPath = "";
        root.thumbTemp = false;
        sattyProc.command = ["satty", "-f", file];
        sattyProc.running = true;
    }

    Process {
        id: sattyProc
        onExited: (exitCode, exitStatus) => {
            if (root.sattyTemp) {
                root.sattyTemp = false;
                // satty may have saved elsewhere; the temp itself goes away.
                rmProc.command = ["rm", "-f", root.sattyPath];
                rmProc.running = true;
            }
            root.sattyPath = "";
        }
    }

    // ---- small helpers -------------------------------------------------

    Process {
        id: copyProc
    }

    Process {
        id: rmProc
    }

    Process {
        id: notifyProc
    }

    function notify(app: string, title: string, body: string): void {
        notifyProc.command = ["notify-send", "-a", app, title, body];
        notifyProc.running = true;
    }

    function clearPending(): void {
        root.pendingKind = "";
        root.pendingClipboard = false;
        // Whatever ended the pipeline, the crosshair goes with it: a stale overlay
        // blocks the whole screen and belongs to nobody.
        Selection.dismiss();
        root.pendingMode = "";
        root.pendingFile = "";
        root.pendingDir = "";
        root.pendingTemp = false;
        root.pendingGeometry = "";
    }

    IpcHandler {
        target: "capture"

        // ⌘⇧3-style: each one captures immediately in its mode, honouring the
        // toolbar's save-to/timer/thumbnail options like macOS does.
        function screen(): void {
            root.beginCapture("screen");
        }

        // ⌃⌘⇧3 / ⌃⌘⇧4: the same captures, straight to the clipboard.
        function screenClipboard(): void {
            root.pendingClipboard = true;
            root.beginCapture("screen");
        }

        function selectionClipboard(): void {
            root.pendingClipboard = true;
            root.beginCapture("selection");
        }

        // ⌘⇧4 then Space: pick a window by clicking it.
        function pickWindow(): void {
            root.beginCapture("window");
        }

        function selection(): void {
            root.beginCapture("selection");
        }

        function window(): void {
            root.beginCapture("window");
        }

        // The old record-toggle behaviour: toggle a region recording.
        function toggleRecording(): void {
            root.toggleRecording();
        }

        function stop(): void {
            root.stopRecording();
        }

        // Opens the ⇧⌘5 toolbar (panels/Capture.qml).
        function open(): void {
            Panels.openByName("capture");
        }
    }
}
