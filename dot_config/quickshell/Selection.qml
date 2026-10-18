pragma Singleton

// The ⌘⇧4 crosshair: a region selection drawn by the shell itself.
//
// macOS freezes the screen the moment the crosshair appears and dims everything
// but the selection; this does the same with one grim capture of the whole screen
// taken before the window maps, shown back at full size under the dim. Selecting
// then works on a still image, so nothing moves under the pointer.
//
// It replaces slurp, for two reasons. slurp's own overlay never mapped when the
// shell started it (the process ran, no layer surface ever appeared — reproduced
// with the shell's own `capture selection`, while the same binary run from a
// terminal drew its overlay fine), and slurp cannot do what macOS does: a live
// size readout, Space to switch to the window picker, Enter to take the
// remembered rectangle, or highlighting a window before you click it.
//
// Space is the key macOS overloads: ⌘⇧4 then Space picks a window, and holding
// Space *while dragging* moves the selection instead of resizing it. Both are
// here.
//
// The result is a geometry string in grim's own format ("x,y WxH", logical
// coordinates) — the same thing slurp printed, so the capture pipeline below is
// unchanged. The caller does the capturing: this window is already gone by then,
// which is what keeps the dim and the border out of the shot.
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs

Singleton {
    id: root

    // A selection is in progress: the frozen shot was taken, the window is up.
    property bool active: false

    // "region" (crosshair) or "window" (hover a window, click it). Space swaps.
    property string mode: "region"

    // The frozen screen shown back to the user, and the file it comes from.
    property string frozenPath: "/tmp/qs-capture-frozen.png"

    // Live selection, in logical screen coordinates.
    property real selX: 0
    property real selY: 0
    property real selW: 0
    property real selH: 0

    // The last selection, pre-drawn so Enter can just take it again (macOS's
    // "Remember Last Selection"): set by begin() from Capture.lastGeometry.
    property bool hasPreset: false

    // The window under the pointer in window mode: null when there is none.
    property var hoveredWindow: null
    property string hoveredTitle: ""

    // Emitted once the geometry is settled; the overlay is already hidden, so a
    // capture cannot include it.
    signal chosen(string geometry)
    signal cancelled()

    // Is there a usable selection right now (bigger than a stray click)?
    readonly property bool hasSelection: root.selW >= 4 && root.selH >= 4

    readonly property string geometry: Math.round(root.selX) + "," + Math.round(root.selY) + " " + Math.round(root.selW) + "x" + Math.round(root.selH)

    // ---- entry points ---------------------------------------------------

    // presetGeometry: "" for a fresh crosshair, or a previous "x,y WxH" to
    // pre-draw (the user can still drag a new one, or press Enter to take it).
    function begin(m: string, presetGeometry: string): void {
        root.mode = m === "window" ? "window" : "region";
        root.hoveredWindow = null;
        root.hoveredTitle = "";
        root.hasPreset = false;
        if (presetGeometry !== "") {
            const m2 = /^(-?\d+),(-?\d+)\s+(\d+)x(\d+)$/.exec(presetGeometry.trim());
            if (m2 !== null) {
                root.selX = parseInt(m2[1]);
                root.selY = parseInt(m2[2]);
                root.selW = parseInt(m2[3]);
                root.selH = parseInt(m2[4]);
                root.hasPreset = true;
            }
        }
        if (!root.hasPreset) {
            root.selX = 0;
            root.selY = 0;
            root.selW = 0;
            root.selH = 0;
        }
        clientsProc.running = true;
        freeze.running = true;
    }

    function cancel(): void {
        root.active = false;
        root.cancelled();
    }

    // Take the overlay down without answering anyone: what the capture pipeline
    // calls when it ends for a reason that is not this window's (a failed grim,
    // a replaced request), so the crosshair can never be left up with no owner.
    function dismiss(): void {
        root.active = false;
    }

    function commit(): void {
        if (!root.hasSelection)
            return;
        const g = root.geometry;
        root.active = false;
        root.chosen(g);
    }

    function toggleMode(): void {
        root.mode = root.mode === "window" ? "region" : "window";
    }

    // Every window's geometry, read once when the picker opens.
    //
    // Not from a HyprlandToplevel's lastIpcObject: that snapshot is empty for
    // windows opened since the shell started until it is hydrated, which is most
    // of them on a session that has been up for a while, and the picker needs
    // geometry for every window, not just the focused one. `hyprctl -j clients` is
    // one process, gives at/size for all of them, and nothing can move while the
    // frozen screen is up.
    property var clients: []

    Process {
        id: clientsProc

        command: ["hyprctl", "-j", "clients"]
        stdout: StdioCollector {
            id: clientsOut

            waitForEnd: true
            onStreamFinished: {
                try {
                    const list = JSON.parse(clientsOut.text);
                    root.clients = list.map(c => ({
                        "x": c.at[0],
                        "y": c.at[1],
                        "w": c.size[0],
                        "h": c.size[1],
                        "title": c.title !== undefined ? c.title : "",
                        "class": c.class !== undefined ? c.class : ""
                    }));
                } catch (e) {
                    root.clients = [];
                }
            }
        }
    }

    // The pointer's position, so a picker that opens under a still pointer still
    // highlights the window it is over (macOS does).
    Process {
        id: cursorProc

        command: ["hyprctl", "cursorpos"]
        stdout: StdioCollector {
            id: cursorOut

            waitForEnd: true
            onStreamFinished: {
                const m = /(-?\d+)\s*,\s*(-?\d+)/.exec(cursorOut.text);
                if (m !== null)
                    root.hoverAt(parseInt(m[1]), parseInt(m[2]));
            }
        }
    }

    function hoverAt(x: real, y: real): void {
        if (root.mode !== "window")
            return;
        let hit = null;
        for (let i = root.clients.length - 1; i >= 0; i--) {
            const c = root.clients[i];
            if (x >= c.x && y >= c.y && x < c.x + c.w && y < c.y + c.h) {
                hit = c;
                break;
            }
        }
        root.hoveredWindow = hit;
        if (hit === null) {
            root.hoveredTitle = "";
            return;
        }
        root.selX = hit.x;
        root.selY = hit.y;
        root.selW = hit.w;
        root.selH = hit.h;
        root.hoveredTitle = hit.title !== "" ? hit.title : hit.class;
    }

    // ---- the frozen shot ------------------------------------------------

    Process {
        id: freeze

        // The focused screen's own name, never a literal: grim fails outright on
        // an output that does not exist, and a failed freeze used to be
        // indistinguishable from pressing nothing at all.
        command: ["grim", "-o", Util.focusedScreen().name, root.frozenPath]

        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                // Say so: quiet is right for a user cancellation (Escape), not for
                // a failure to even take the still the crosshair works on.
                Capture.notify("screenshot", "Capture failed", "could not freeze the screen (grim " + exitCode + ")");
                root.cancelled();
                return;
            }
            root.active = true;
            if (root.mode === "window")
                cursorProc.running = true;
        }
    }

    // ---- the overlay ----------------------------------------------------

    PanelWindow {
        id: win

        visible: root.active
        screen: Util.focusedScreen()
        color: "transparent"
        exclusiveZone: -1
        anchors.top: true
        anchors.bottom: true
        anchors.left: true
        anchors.right: true
        WlrLayershell.namespace: "quickshell-selection"
        WlrLayershell.layer: WlrLayer.Overlay
        // Taken at map time, which is why this window maps *for* the selection
        // instead of staying mapped: a layer surface cannot be handed the
        // keyboard after it is already up.
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

        // The screen as it was when the crosshair appeared, at logical size.
        Image {
            anchors.fill: parent
            source: "file://" + root.frozenPath
            fillMode: Image.PreserveAspectFit
            smooth: true
            cache: false
        }

        // Everything outside the selection is dimmed, macOS-style, drawn as four
        // bands so the selection itself stays at full brightness. Nothing dims
        // until there is a selection to protect: before the drag the screen looks
        // exactly as it did, which is what macOS does.
        readonly property color dim: Qt.rgba(0, 0, 0, 0.42)
        readonly property bool dimming: root.hasSelection

        Rectangle {
            color: win.dim
            visible: win.dimming
            x: 0
            y: 0
            width: win.width
            height: Math.max(0, root.selY)
        }

        Rectangle {
            visible: win.dimming
            color: win.dim
            x: 0
            y: Math.max(0, root.selY)
            width: Math.max(0, root.selX)
            height: Math.max(0, root.selH)
        }

        Rectangle {
            visible: win.dimming
            color: win.dim
            x: root.selX + root.selW
            y: Math.max(0, root.selY)
            width: Math.max(0, win.width - root.selX - root.selW)
            height: Math.max(0, root.selH)
        }

        Rectangle {
            visible: win.dimming
            color: win.dim
            x: 0
            y: root.selY + root.selH
            width: win.width
            height: Math.max(0, win.height - root.selY - root.selH)
        }

        // The selection frame, and the live size readout macOS puts beside it.
        Item {
            visible: root.hasSelection
            x: root.selX
            y: root.selY
            width: root.selW
            height: root.selH

            Rectangle {
                anchors.fill: parent
                color: "transparent"
                border.width: 1
                border.color: "#ffffff"
            }

            Rectangle {
                id: readout

                anchors.horizontalCenter: parent.horizontalCenter
                // Below the selection, or inside it when the selection reaches the
                // bottom of the screen (a tiled window does) — macOS keeps the
                // label on screen the same way.
                y: (parent.y + parent.height + height + 8 > win.height) ? parent.height - height - 6 : parent.height + 6
                width: readoutText.implicitWidth + 12
                height: readoutText.implicitHeight + 6
                radius: 3
                color: Qt.rgba(0, 0, 0, 0.72)

                Text {
                    id: readoutText

                    anchors.centerIn: parent
                    text: Math.round(root.selW) + " × " + Math.round(root.selH)
                    color: "#ffffff"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                }
            }
        }

        // Window mode: the window under the pointer, outlined like macOS's
        // camera pointer highlights it, with its title.
        Item {
            visible: root.mode === "window" && root.hoveredWindow !== null
            x: root.selX
            y: root.selY
            width: root.selW
            height: root.selH

            Rectangle {
                anchors.fill: parent
                color: "#1affffff"
                border.width: 2
                border.color: "#ffffff"
                radius: 6
            }

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                y: (parent.y + parent.height + height + 8 > win.height) ? parent.height - height - 6 : parent.height + 6
                width: titleText.implicitWidth + 14
                height: titleText.implicitHeight + 6
                radius: 3
                color: Qt.rgba(0, 0, 0, 0.78)

                Text {
                    id: titleText

                    anchors.centerIn: parent
                    text: root.hoveredTitle + "   " + Math.round(root.selW) + " × " + Math.round(root.selH)
                    color: "#ffffff"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                }
            }
        }

        // One line of help, the way ⌘⇧5's panel explains itself. Nothing else
        // on screen says that Space picks a window.
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 40
            width: hint.implicitWidth + 20
            height: hint.implicitHeight + 10
            radius: 4
            color: Qt.rgba(0, 0, 0, 0.72)

            Text {
                id: hint

                anchors.centerIn: parent
                text: root.mode === "window" ? "click a window to capture · Space for a region · Esc to cancel" : (root.hasPreset ? "drag a new region, or Enter to use the last one · Space for a window · Esc to cancel" : "drag to select · Space for a window · Esc to cancel")
                color: "#e8e8e8"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
            }
        }

        MouseArea {
            id: mouse

            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: Qt.CrossCursor
            hoverEnabled: true

            property real pressX: 0
            property real pressY: 0
            property bool dragging: false

            onPressed: (m) => {
                if (root.mode === "window") {
                    // Hit test at the click itself. Waiting for a motion event to
                    // have highlighted something first meant a click that arrived
                    // before any pointer move did nothing at all.
                    root.hoverAt(m.x, m.y);
                    root.commit();
                    return;
                }
                pressX = m.x;
                pressY = m.y;
                dragging = true;
                root.hasPreset = false;
                root.selX = m.x;
                root.selY = m.y;
                root.selW = 0;
                root.selH = 0;
            }

            onPositionChanged: (m) => {
                if (root.mode === "window") {
                    root.hoverAt(m.x, m.y);
                    return;
                }
                if (!dragging)
                    return;
                // Dragging up or left is normal: the rectangle is normalised.
                root.selX = Math.min(pressX, m.x);
                root.selY = Math.min(pressY, m.y);
                root.selW = Math.abs(m.x - pressX);
                root.selH = Math.abs(m.y - pressY);
            }

            onReleased: (m) => {
                if (root.mode === "window")
                    return;
                dragging = false;
                if (root.hasSelection)
                    root.commit();
            }
        }

        // Keys land here: this window holds exclusive keyboard focus while it is
        // up. Escape cancels, Space swaps to the window picker (macOS overloads
        // the same key), Enter takes the selection on screen.
        Item {
            anchors.fill: parent
            focus: true

            Keys.onEscapePressed: root.cancel()
            Keys.onSpacePressed: root.toggleMode()
            Keys.onReturnPressed: root.commit()
            Keys.onEnterPressed: root.commit()

            Component.onCompleted: forceActiveFocus()
        }
    }
}
