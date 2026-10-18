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
// TWO WORKSPACES PER VIEW
//   target — whose live content is shown (the pill that was dragged).
//   home   — the workspace the view belongs to: the one that was focused when it
//            was dragged out. A view is visible only while `home` is focused, so
//            switching workspaces leaves it behind instead of dragging it along;
//            you can watch workspace 10's build from workspace 1, and it stays
//            there when you move on.
// When you switch *to* the target's workspace the view closes: you are looking at
// the real thing then.
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

    // [{ target, home }], in creation order.
    property var previews: []

    // target -> { x, y, w, h }. Replaced, never mutated.
    property var geometry: ({})

    // The target currently being pulled out of the bar, or -1.
    property int dragId: -1

    readonly property int defaultWidth: 420
    readonly property int defaultHeight: 300

    readonly property var screenInfo: Util.focusedScreen()

    readonly property int focusedId: Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : -1

    function isFocused(id: int): bool {
        return root.focusedId === id;
    }

    function homeOf(target: int): int {
        for (const p of root.previews) {
            if (p.target === target)
                return p.home;
        }
        return -1;
    }

    function hasPreview(target: int): bool {
        for (const p of root.previews) {
            if (p.target === target)
                return true;
        }
        return false;
    }

    function boxFor(target: int): var {
        const box = root.geometry[target];
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

    function setGeometry(target: int, x: real, y: real, width: real, height: real): void {
        const next = Object.assign({}, root.geometry);
        next[target] = {
            "x": root.clampX(x, width),
            "y": root.clampY(y, height),
            "w": width,
            "h": height
        };
        root.geometry = next;
    }

    // The window a view shows: the workspace's last focused toplevel, falling back
    // to any window it holds.
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

    // `home` defaults to the workspace you are on: a view belongs to the desktop
    // it was pulled out on.
    function openFor(target: int, home: int): void {
        if (root.hasPreview(target))
            return;
        const box = root.boxFor(target);
        const next = Object.assign({}, root.geometry);
        next[target] = box;
        root.geometry = next;
        root.previews = root.previews.concat([{
            "target": target,
            "home": home >= 0 ? home : root.focusedId
        }]);
    }

    function toggleFor(target: int): void {
        if (root.hasPreview(target))
            root.close(target);
        else
            root.openFor(target, -1);
    }

    function close(target: int): void {
        root.previews = root.previews.filter(p => p.target !== target);
        const next = Object.assign({}, root.geometry);
        delete next[target];
        root.geometry = next;
        if (root.dragId === target)
            root.dragId = -1;
    }

    function closeAll(): void {
        root.previews = [];
        root.geometry = ({});
        root.dragId = -1;
    }

    // Pulled out of the bar: a workspace pill hands over the pointer's screen
    // position while it is dragged downward, and the view centres on it. Its home
    // is the workspace you were on, its target is the pill's.
    function beginDrag(target: int, x: real, y: real): void {
        root.openFor(target, root.focusedId);
        root.dragId = target;
        const box = root.boxFor(target);
        root.setGeometry(target, x - box.w / 2, y, box.w, box.h);
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

    // Switching to the workspace a view shows makes the view pointless.
    function switchTo(target: int): void {
        Hyprland.dispatch("hl.dsp.focus({workspace = " + target + "})");
        root.close(target);
    }

    function cycleSize(target: int): void {
        const box = root.boxFor(target);
        if (box.w < 380)
            root.setGeometry(target, box.x, box.y, 420, 300);
        else if (box.w < 560)
            root.setGeometry(target, box.x, box.y, 620, 420);
        else
            root.setGeometry(target, box.x, box.y, 320, 220);
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
            if (!root.hasPreview(ws.id)) {
                root.openFor(ws.id, -1);
                return;
            }
        }
        root.closeAll();
    }

    // A view whose *target* has just been focused is redundant — you are looking
    // at the real thing. Views whose home is elsewhere simply stop being visible;
    // they are not closed, so returning to that workspace brings them back.
    Connections {
        target: Hyprland

        function onFocusedWorkspaceChanged(): void {
            const ws = Hyprland.focusedWorkspace;
            if (ws && root.hasPreview(ws.id))
                root.close(ws.id);
        }
    }

    IpcHandler {
        target: "pip"

        function open(id: int): void {
            root.openFor(id, -1);
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
