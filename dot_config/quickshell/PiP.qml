pragma Singleton

// Picture-in-picture state: one floating live view per workspace, and where each
// one sits.
//
// A singleton rather than a window object, because the *bar* drives it: dragging
// a workspace pill downward has to reach the state (`PiP.beginDrag`), and calling
// a function on a window instance from another file is not possible in QML —
// `PiP.beginDrag(...)` on a plain component resolves to the type object and
// throws "Property 'beginDrag' of object PiP is not a function". The windows are
// PiPWindow.qml, instantiated once in shell.qml, reading this state.
//
// Geometry lives in a map that is *replaced* on every change rather than mutated,
// so each window's margin binding re-evaluates without the window being recreated
// (a drag would otherwise flicker once per frame).
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs

Singleton {
    id: root

    // Workspace ids that have a floating view, in creation order.
    property var previews: []

    // id -> { x, y, w, h }. Replaced, never mutated.
    property var geometry: ({})

    // The preview currently being pulled out of the bar, or -1.
    property int dragId: -1

    readonly property int defaultWidth: 420
    readonly property int defaultHeight: 300

    readonly property var screenInfo: Util.focusedScreen()

    readonly property var workspace: {
        const list = Hyprland.workspaces.values;
        for (let i = 0; i < list.length; i++) {
            if (list[i].id === root.workspaceId)
                return list[i];
        }
        return null;
    }

    // Kept for the scripts that use it: the id of the most recently opened view.
    readonly property int workspaceId: root.previews.length > 0 ? root.previews[root.previews.length - 1] : -1

    function boxFor(id: int): var {
        const box = root.geometry[id];
        if (box !== undefined)
            return box;
        return {
            "x": 40,
            "y": 56,
            "w": root.defaultWidth,
            "h": root.defaultHeight
        };
    }

    function clampX(x: real, width: real): real {
        const screen = root.screenInfo ? root.screenInfo.width : 3072;
        return Math.max(0, Math.min(screen - width, x));
    }

    function clampY(y: real, height: real): real {
        const screen = root.screenInfo ? root.screenInfo.height : 1728;
        return Math.max(Theme.barHeight, Math.min(screen - height, y));
    }

    function setGeometry(id: int, x: real, y: real, width: real, height: real): void {
        const next = Object.assign({}, root.geometry);
        next[id] = {
            "x": root.clampX(x, width),
            "y": root.clampY(y, height),
            "w": width,
            "h": height
        };
        root.geometry = next;
    }

    // The window a preview shows: the workspace's last focused toplevel, falling
    // back to any window it holds.
    function targetFor(id: int): var {
        const list = Hyprland.workspaces.values;
        for (let i = 0; i < list.length; i++) {
            if (list[i].id !== id)
                continue;
            const windows = list[i].toplevels.values;
            if (windows.length === 0)
                return null;
            const last = list[i].lastIpcObject && list[i].lastIpcObject.lastwindow ? String(list[i].lastIpcObject.lastwindow) : "";
            for (let j = 0; j < windows.length; j++) {
                if (windows[j].address === last)
                    return windows[j];
            }
            return windows[windows.length - 1];
        }
        return null;
    }

    function workspaceFor(id: int): var {
        const list = Hyprland.workspaces.values;
        for (let i = 0; i < list.length; i++) {
            if (list[i].id === id)
                return list[i];
        }
        return null;
    }

    function openFor(id: int): void {
        if (root.previews.indexOf(id) !== -1)
            return;
        const box = root.boxFor(id);
        const next = Object.assign({}, root.geometry);
        next[id] = box;
        root.geometry = next;
        root.previews = root.previews.concat([id]);
    }

    function toggleFor(id: int): void {
        if (root.previews.indexOf(id) !== -1)
            root.close(id);
        else
            root.openFor(id);
    }

    function close(id: int): void {
        root.previews = root.previews.filter(p => p !== id);
        const next = Object.assign({}, root.geometry);
        delete next[id];
        root.geometry = next;
        if (root.dragId === id)
            root.dragId = -1;
    }

    function closeAll(): void {
        root.previews = [];
        root.geometry = ({});
        root.dragId = -1;
    }

    // Pulled out of the bar: a workspace pill hands over the pointer's screen
    // position while it is dragged downward, and that workspace's view centres on
    // it. Dragging another pill pulls out a second view — they coexist.
    function beginDrag(id: int, x: real, y: real): void {
        root.openFor(id);
        root.dragId = id;
        const box = root.boxFor(id);
        root.setGeometry(id, x - box.w / 2, y, box.w, box.h);
    }

    function dragTo(x: real, y: real): void {
        if (root.dragId < 0)
            return;
        const box = root.boxFor(root.dragId);
        root.setGeometry(root.dragId, x - box.w / 2, y, box.w, box.h);
    }

    function endDrag(): void {
        root.dragId = -1;
    }

    // Switching to the workspace makes its live view pointless: you are looking at
    // the real thing now.
    function switchTo(id: int): void {
        Hyprland.dispatch("hl.dsp.focus({workspace = " + id + "})");
        root.close(id);
    }

    function cycleSize(id: int): void {
        const box = root.boxFor(id);
        if (box.w < 380)
            root.setGeometry(id, box.x, box.y, 420, 300);
        else if (box.w < 560)
            root.setGeometry(id, box.x, box.y, 620, 420);
        else
            root.setGeometry(id, box.x, box.y, 320, 220);
    }

    // Workspaces that hold windows and are not the one you are on.
    readonly property var otherWorkspaces: {
        const list = Hyprland.workspaces.values.slice();
        const out = [];
        for (const ws of list) {
            if (!ws.focused && ws.toplevels.values.length > 0)
                out.push(ws);
        }
        out.sort((a, b) => a.id - b.id);
        return out;
    }

    // For scripts: open a view for the next workspace with windows.
    function cycleOther(): void {
        const others = root.otherWorkspaces;
        if (others.length === 0) {
            root.closeAll();
            return;
        }
        for (const ws of others) {
            if (root.previews.indexOf(ws.id) === -1) {
                root.openFor(ws.id);
                return;
            }
        }
        root.closeAll();
    }

    // A workspace you have just switched to no longer needs a live view.
    Connections {
        target: Hyprland

        function onFocusedWorkspaceChanged(): void {
            const ws = Hyprland.focusedWorkspace;
            if (ws && root.previews.indexOf(ws.id) !== -1)
                root.close(ws.id);
        }
    }

    IpcHandler {
        target: "pip"

        function open(id: int): void {
            root.openFor(id);
        }
        function toggle(id: int): void {
            root.toggleFor(id);
        }
        function close(id: int): void {
            root.close(id);
        }
        function closeAll(): void {
            root.closeAll();
        }
        function cycleOther(): void {
            root.cycleOther();
        }
    }
}
