import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import qs

// SUPER+Tab WORKSPACE switcher, with live previews of where you would land.
//
// Each card is a workspace: a live ScreencopyView of the window you would land
// on — the workspace's most recently focused window — plus the workspace name,
// how many windows it holds, and the captured window's title. That is the whole
// point of the overlay: the thumbnails are *live*, not snapshots taken when it
// opened.
//
// Behaviour, matching what a switcher should feel like:
//   hold SUPER, tap Tab        cycle forward (Shift+Tab back)
//   release SUPER              switch to the highlighted workspace
//   click a card               switch to it
//   Esc                        cancel
//
// Candidates are workspaces in most-recently-used order, which is what makes a
// single tap-and-release return to the workspace you just came from. Hyprland
// does not expose workspace focus history, so it is tracked here from
// Hyprland.focusedWorkspaceChanged. Only workspaces that hold windows (plus the
// focused one) are offered — an empty workspace you merely visited is clutter.
//
// Committing is two dispatches on this machine's Lua-config Hyprland: focus the
// workspace (`hl.dsp.focus({workspace = N})`), then raise the window that card
// captured with an `address:` selector. The second call is what guarantees the
// right window is on top even where the shell's idea of "most recently focused"
// differs from Hyprland's own `lastwindow`.
Scope {
    id: root

    property bool showing: false
    property int selected: 0

    // Workspace ids, most recently focused first. Kept in the shell rather than
    // derived from Hyprland.workspaces, whose order is creation order.
    property var order: []

    // Workspace id -> address of the window the shell saw focused on it most
    // recently. Hyprland's per-workspace `lastwindow` is whatever the compositor
    // last recorded; this stays correct while windows are being focused.
    property var recent: ({})

    // Live thumbnails are only worth paying for while the overlay is up.
    readonly property bool live: root.showing

    Connections {
        target: Hyprland

        function onFocusedWorkspaceChanged(): void {
            const ws = Hyprland.focusedWorkspace;
            if (!ws)
                return;
            root.order = [ws.id].concat(root.order.filter(id => id !== ws.id)).slice(0, 40);
        }

        function onActiveToplevelChanged(): void {
            const top = Hyprland.activeToplevel;
            if (!top || !top.workspace)
                return;
            const recent = Object.assign({}, root.recent);
            recent[top.workspace.id] = top.address;
            root.recent = recent;
        }
    }

    // Hyprland's IPC reports addresses with an 0x prefix and quickshell does not
    // always keep it, so comparisons normalise it away.
    function sameAddress(a: var, b: var): bool {
        if (!a || !b)
            return false;
        const norm = s => String(s).replace(/^0x/i, "").toLowerCase();
        return norm(a) === norm(b);
    }

    // The window a workspace card shows (and commit raises): the one the shell
    // saw focused on that workspace most recently, else the workspace's own
    // `lastwindow`, else its first toplevel.
    function captureFor(ws: var): var {
        const tops = ws.toplevels.values;
        if (tops.length === 0)
            return null;

        const tracked = root.recent[ws.id];
        for (const t of tops) {
            if (root.sameAddress(t.address, tracked))
                return t;
        }

        const last = ws.lastIpcObject && ws.lastIpcObject.lastwindow ? String(ws.lastIpcObject.lastwindow) : "";
        for (const t of tops) {
            if (root.sameAddress(t.address, last))
                return t;
        }

        return tops[0];
    }

    // Workspaces to offer, MRU first: every workspace that holds windows plus
    // the focused one, with anything that no longer exists dropped.
    readonly property var candidates: {
        const values = Hyprland.workspaces.values;
        const byId = {};
        for (const ws of values)
            byId[ws.id] = ws;

        const entry = ws => {
            const tops = ws.toplevels.values;
            const capture = root.captureFor(ws);
            return {
                "ws": ws,
                "id": ws.id,
                "name": ws.name,
                "focused": ws.focused,
                "count": tops.length,
                "capture": capture,
                "title": capture ? capture.title : ""
            };
        };

        const out = [];
        const seen = {};

        for (const id of root.order) {
            const ws = byId[id];
            if (ws && !seen[id] && (ws.toplevels.values.length > 0 || ws.focused)) {
                seen[id] = true;
                out.push(entry(ws));
            }
        }
        // Workspaces the shell has not seen focused yet (started before the
        // shell, or focused while a reload happened) go last, in Hyprland's
        // order.
        for (const ws of values) {
            if (!seen[ws.id] && (ws.toplevels.values.length > 0 || ws.focused)) {
                seen[ws.id] = true;
                out.push(entry(ws));
            }
        }
        return out;
    }

    readonly property var current: root.candidates.length > 0 ? root.candidates[Math.min(root.selected, root.candidates.length - 1)] : null

    function open(): void {
        if (root.showing) {
            root.next();
            return;
        }
        // MRU-first means index 0 is the workspace you are on. Opening with it
        // selected would make a single tap-and-release a no-op; preselecting the
        // previous workspace is what alt-tab does.
        //
        // The focused workspace is forced to the MRU front so index 1 is "the
        // previous one" even before the shell has seen a focus change.
        const focused = Hyprland.focusedWorkspace;
        if (focused && (root.order.length === 0 || root.order[0] !== focused.id))
            root.order = [focused.id].concat(root.order.filter(id => id !== focused.id));
        root.selected = root.candidates.length > 1 ? 1 : 0;
        root.showing = true;
    }

    function close(): void {
        root.showing = false;
    }

    function next(): void {
        if (root.candidates.length === 0)
            return;
        root.selected = (root.selected + 1) % root.candidates.length;
    }

    function previous(): void {
        if (root.candidates.length === 0)
            return;
        root.selected = (root.selected - 1 + root.candidates.length) % root.candidates.length;
    }

    function commit(): void {
        const target = root.current;
        root.close();
        if (!target)
            return;

        // Switch to the workspace. It is the working form on this machine:
        // `hyprctl dispatch` parses its argument as Lua, not as classic
        // dispatcher syntax.
        Hyprland.dispatch("hl.dsp.focus({workspace = " + target.id + "})");

        // Then raise the window the card showed. Toplevel.activate() (xdg
        // activation) is ignored by Hyprland for a window the shell does not
        // own (verified), and the bare address without the `address:` prefix is
        // rejected with "window not found" (also verified) — so the selector
        // form is the only thing that works.
        const t = target.capture;
        if (t) {
            const address = String(t.address).startsWith("0x") ? String(t.address) : "0x" + String(t.address);
            Hyprland.dispatch("hl.dsp.focus({window = \"address:" + address + "\"})");
        }
    }

    IpcHandler {
        target: "switcher"

        function toggle(): void {
            root.open();
        }
        function next(): void {
            root.open();
        }
        function previous(): void {
            if (!root.showing)
                root.open();
            else
                root.previous();
        }
        function close(): void {
            root.close();
        }
    }

    LazyLoader {
        active: root.showing

        PanelWindow {
            id: window

            screen: Util.focusedScreen()
            anchors.top: true
            anchors.left: true
            anchors.right: true
            anchors.bottom: true
            color: "transparent"
            exclusiveZone: -1
            WlrLayershell.namespace: "quickshell-switcher"
            WlrLayershell.layer: WlrLayer.Overlay
            // Exclusive: the overlay has to see the SUPER release to know when to
            // commit, which is the whole point of the gesture.
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            focusable: true

            Rectangle {
                anchors.fill: parent
                color: Theme.alpha("#000000", 0.55)

                MouseArea {
                    anchors.fill: parent
                    onClicked: root.close()
                }
            }

            // Keyboard: Tab cycles, releasing SUPER commits, Esc cancels.
            Item {
                anchors.fill: parent
                focus: true

                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Tab || event.key === Qt.Key_Right || event.key === Qt.Key_Down) {
                        root.next();
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Backtab || event.key === Qt.Key_Left || event.key === Qt.Key_Up) {
                        root.previous();
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                        root.commit();
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Escape) {
                        root.close();
                        event.accepted = true;
                    }
                }

                // The gesture ends when the modifier is let go. Qt delivers the
                // release to whichever surface holds keyboard focus, which is
                // this overlay for as long as it is up.
                Keys.onReleased: event => {
                    if (event.key === Qt.Key_Super_L || event.key === Qt.Key_Super_R || event.key === Qt.Key_Meta)
                        root.commit();
                }
            }

            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                spacing: 22

                // Where you would land, spelled out. This is the one piece of
                // text in the overlay, so it says the useful thing.
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 10

                    Text {
                        text: "\uf0d9"
                        color: Theme.purple
                        font.family: Theme.fontFamily
                        font.pixelSize: 20
                    }

                    Text {
                        id: header

                        anchors.verticalCenter: parent.verticalCenter
                        text: {
                            if (!root.current)
                                return "nothing to switch to";
                            const c = root.current;
                            const windows = c.count === 1 ? "1 window" : c.count + " windows";
                            return (c.focused ? "workspace " : "jumping to workspace ") + c.name + " · " + windows;
                        }
                        color: root.current && !root.current.focused ? Theme.pink : Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                        font.bold: true
                    }
                }

                // Filmstrip. The whole row slides so the selected card stays
                // centred, which reads as "moving through" the workspaces.
                Item {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: window.width
                    height: 300
                    clip: true

                    Row {
                        id: strip

                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 18

                        // Centred by hand: the strip is as wide as its contents,
                        // and the selected card is pulled to the middle.
                        x: window.width / 2 - (root.selected * (cardWidth + strip.spacing)) - cardWidth / 2
                        Behavior on x {
                            NumberAnimation {
                                duration: Theme.animationNormal
                                easing.type: Easing.OutCubic
                            }
                        }

                        readonly property int cardWidth: 340

                        Repeater {
                            model: root.candidates

                            delegate: Item {
                                id: slot

                                required property var modelData
                                required property int index

                                readonly property bool current: index === root.selected
                                readonly property bool live: root.live && Math.abs(index - root.selected) <= 1

                                width: strip.cardWidth
                                height: 250
                                opacity: slot.current ? 1 : 0.62
                                Behavior on opacity {
                                    NumberAnimation {
                                        duration: Theme.animationFast
                                    }
                                }

                                scale: slot.current ? 1.04 : 1.0
                                Behavior on scale {
                                    NumberAnimation {
                                        duration: Theme.animationNormal
                                        easing.type: Easing.OutBack
                                    }
                                }

                                ClippingWrapperRectangle {
                                    id: frame

                                    anchors.top: parent.top
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: parent.width
                                    height: 212
                                    radius: Theme.panelRadius
                                    color: Theme.alpha(Theme.bg, 0.85)
                                    border.width: slot.current ? 2 : 1
                                    border.color: slot.current ? Theme.purple : Theme.border

                                    // One child only: a Wrapper component cannot
                                    // have more than one, so the capture and its
                                    // placeholder live inside this Item.
                                    Item {
                                        anchors.fill: parent

                                        ScreencopyView {
                                            anchors.fill: parent
                                            anchors.margins: 2
                                            captureSource: slot.live && slot.modelData.capture ? slot.modelData.capture.wayland : null
                                            // Only the highlighted card streams: a live
                                            // screencopy per card is ~25 MiB of buffers each
                                            // (measured: +80 MiB with three cards streaming).
                                            // The neighbours still show real content, captured
                                            // once, which is enough to recognise them.
                                            live: slot.current
                                            // Ask the compositor to scale down before it sends
                                            // the frame; the card is 340px wide either way.
                                            constraintSize: Qt.size(340, 212)
                                            paintCursor: false
                                        }

                                        // Shown when the workspace holds no window
                                        // (the focused one can legitimately be
                                        // empty), and when a window is too new
                                        // to capture.
                                        Text {
                                            anchors.centerIn: parent
                                            visible: slot.modelData.capture === null
                                            text: "\uf2d0"
                                            color: Theme.comment
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 30
                                        }
                                    }
                                }

                                // Workspace name/number and how much it holds.
                                Text {
                                    anchors.top: frame.bottom
                                    anchors.topMargin: 8
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: parent.width - 8
                                    horizontalAlignment: Text.AlignHCenter
                                    text: "workspace " + slot.modelData.name + "  ·  " + (slot.modelData.count === 1 ? "1 window" : slot.modelData.count + " windows")
                                    color: slot.current ? Theme.fg : Theme.comment
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.bold: slot.current
                                }

                                // The captured window's title: what is on top of
                                // that workspace right now.
                                Text {
                                    anchors.top: frame.bottom
                                    anchors.topMargin: 26
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: parent.width - 8
                                    horizontalAlignment: Text.AlignHCenter
                                    text: Util.elide(slot.modelData.title, 34)
                                    color: slot.current ? Theme.fg : Theme.comment
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeSmall
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.selected = slot.index;
                                        root.commit();
                                    }
                                }
                            }
                        }
                    }
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "release SUPER to switch   ·   tab cycles   ·   esc cancels"
                    color: Theme.comment
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                }
            }
        }
    }
}
