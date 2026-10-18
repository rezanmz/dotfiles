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
// Every capture is grim, every region is slurp (Esc exits non-zero and cancels
// silently, like ⌘⇧4), the focused window is read from hyprctl's JSON, and
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
    property string saveTo: "desktop"       // "desktop" | "pictures" | "clipboard"
    property int timer: 0                   // 0 | 5 | 10 seconds
    property bool thumbnail: true           // show the floating thumbnail after a capture
    property bool recordingMode: false      // the toolbar is showing its recording controls
    property string recordTarget: "selection" // "screen" | "selection"
    property string mic: "none"             // "none" | "default" (the default source) | "system" (the sink monitor)
    // macOS's "Other Location": a typed directory, used when saveTo is "other".
    property string customDir: ""
    // macOS's "Remember Last Selection": a plain selection capture reuses the
    // previous geometry instead of asking again. slurp cannot pre-draw a frame, so
    // the toolbar's Reselect button is the way to draw a new one.
    property bool rememberSelection: false
    property string lastGeometry: ""
    property bool reselect: false

    // ---- timer countdown (the toolbar displays it) --------------------
    property int countdown: 0
    property string countdownMode: ""

    // ---- floating thumbnail state (ScreenshotThumb.qml reads it) -------
    property string thumbPath: ""
    property bool thumbTemp: false          // a clipboard capture: delete the file with the thumbnail
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
        if (root.saveTo === "clipboard") {
            root.pendingDir = "/tmp";
            root.pendingFile = "/tmp/" + name;
            root.pendingTemp = true;
            return;
        }
        if (root.saveTo === "pictures") {
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

    // Recordings always land in ~/Videos/Recordings (macOS: ~/Movies).
    function beginRecord(target: string): void {
        if (Recorder.recording)
            return;
        root.pendingKind = "record";
        root.pendingMode = target;
        root.pendingDir = root.home + "/Videos/Recordings";
        root.pendingFile = root.pendingDir + "/Recording " + root.stamp() + ".mp4";
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

    function stopRecording(): void {
        if (!Recorder.recording)
            return;
        Recorder.stop();
        if (root.recordingFile !== "") {
            root.notify("recording", "Recording saved", root.recordingFile);
            root.recordingFile = "";
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
        if (root.pendingKind === "record") {
            if (root.pendingMode === "screen") {
                root.startRecording("");
            } else {
                slurpProc.running = true;
            }
            return;
        }
        if (root.pendingMode === "selection") {
            // Remembered selection: reuse the last geometry instead of asking
            // again (macOS's "Remember Last Selection"). Reselect forces slurp.
            if (root.rememberSelection && root.lastGeometry !== "" && !root.reselect) {
                root.pendingGeometry = root.lastGeometry;
                root.runGrim();
                return;
            }
            root.reselect = false;
            slurpProc.running = true;
        } else if (root.pendingMode === "window") {
            winProc.running = true;
        } else {
            root.runGrim();
        }
    }

    // slurp draws its own overlay and waits for the drag; Esc exits non-zero,
    // which cancels silently — nothing to say about a cancelled selection.
    Process {
        id: slurpProc
        command: ["slurp"]
        stdout: StdioCollector {
            id: slurpOut
            waitForEnd: true
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                root.clearPending();
                return;
            }
            root.pendingGeometry = slurpOut.text.trim();
            if (root.rememberSelection)
                root.lastGeometry = root.pendingGeometry;
            if (root.pendingKind === "record")
                root.startRecording(root.pendingGeometry);
            else
                root.runGrim();
        }
    }

    // The focused window's geometry, in the same logical coordinates slurp
    // works in (grim -g takes those; the old script did this too).
    Process {
        id: winProc
        command: ["hyprctl", "-j", "activewindow"]
        stdout: StdioCollector {
            id: winOut
            waitForEnd: true
        }
        onExited: (exitCode, exitStatus) => root.applyWindow(winOut.text)
    }

    function applyWindow(text: string): void {
        let geom = "";
        try {
            const w = JSON.parse(text);
            if (w && w.at && w.size)
                geom = w.at[0] + "," + w.at[1] + " " + w.size[0] + "x" + w.size[1];
        } catch (e) {
            geom = "";
        }
        // Nothing focused (or hyprctl said something unexpected): cancel
        // silently, like the old `screenshot window` did.
        if (geom === "") {
            root.clearPending();
            return;
        }
        root.pendingGeometry = geom;
        root.runGrim();
    }

    function runGrim(): void {
        grimProc.command = root.pendingGeometry !== "" ? ["grim", "-g", root.pendingGeometry, root.pendingFile] : ["grim", root.pendingFile];
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
        if (root.saveTo === "clipboard") {
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
            root.thumbVisible = true;
        } else {
            if (temp) {
                rmProc.command = ["rm", "-f", file];
                rmProc.running = true;
            }
            if (root.saveTo === "clipboard")
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
