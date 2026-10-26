pragma Singleton

// Which panel is open, and which widget each panel hangs under.
//
// The old bar could only run a command on click; the shell can show a real
// panel, so something has to own "only one panel at a time" — clicking a second
// widget closes the first, clicking outside closes everything. That is this
// object. Panels are addressed by a short string (`calendar`, `audio`, ...)
// which the widget sets as its `panel` property and the popup matches by name.
import QtQuick
import Quickshell

Singleton {
    // Name of the open panel, or "" when none is open.
    property string current: ""


    readonly property bool anyOpen: current !== ""

    // The widget that opened the current panel, and the window it lives in.
    // Several widgets can open the same panel (cpu, gpu, ram and disk all open
    // `system`), so the panel follows whichever was clicked instead of five
    // copies of it existing at once.
    property var anchorItem: null

    // The bar's PanelWindow object (not QtQuick's Window.window, which is a
    // ProxiedWindow and is rejected by the tray menu / popup APIs).
    property var barWindow: null

    // panel name -> { item, window } for the widgets that can open it. Lets a
    // panel be opened without a click (keyboard bind, IPC), and lets several
    // widgets share one panel.
    property var anchors: ({})

    // Used when a panel has no widget of its own (the cheatsheet, and any
    // panel opened without a click). Without it those panels open
    // unpositioned.
    property var fallbackAnchor: null


    function registerFallback(item: var): void {
        fallbackAnchor = item;
    }

    function registerAnchor(name: string, item: var): void {
        if (name === "")
            return;
        anchors[name] = {
            "item": item
        };
    }

    function toggle(name: string, item: var): void {
        if (current === name) {
            current = "";
            return;
        }
        if (item !== undefined)
            anchorItem = item;
        current = name;
    }

    // Open a panel by name using the anchor its widget registered, for callers
    // that have no widget to point at.
    function openByName(name: string): void {
        const anchor = anchors[name];
        if (anchor !== undefined)
            anchorItem = anchor.item;
        else if (fallbackAnchor !== null)
            anchorItem = fallbackAnchor;
        current = name;
    }

    function open(name: string): void {
        current = name;
    }

    function close(): void {
        if (current !== "")
        current = "";
    }

    // Panels whose own document holds the keyboard — a search field, a text
    // prompt, an xdg popup grab. The shell must not take the keyboard for Escape
    // while one of these is open: a second exclusive request would steal the
    // keys mid-typing, and these panels close on Escape themselves.
    readonly property var selfFocused: ["keys", "capture"]

    // Whether the shell's Escape surface should hold the keyboard right now.
    readonly property bool shellOwnsKeyboard: anyOpen && selfFocused.indexOf(current) === -1

    // Escape closes the panel without touching keyboard focus.
    //
    // A grabbing surface would receive every key, and every other keystroke has to
    // keep going to the focused window. Hyprland also routes clicks to the surface
    // that holds exclusive keyboard focus, so such a surface swallowed clicks too:
    // a full-screen one froze the whole bar, and a 1x1 one behaved identically,
    // because the size was never the problem. So the key is bound in the compositor
    // instead, and only while a panel that does not hold the keyboard itself is
    // open: `hl.bind` on open, `hl.unbind` on close. Escape is consumed while a
    // panel is up — that is the point — and untouched the rest of the time.
    //
    // Hyprland 0.56 dropped the hyprlang `keyword` path for binds ("keyword can't
    // work with non-legacy parsers"), so this goes through `hyprctl eval`, which
    // takes Lua. Absolute paths for both binaries: the shell's PATH is not
    // Hyprland's.
    property bool escapeBound: false

    function syncEscapeBind(): void {
        const want = shellOwnsKeyboard;
        if (want === escapeBound)
            return;
        escapeBound = want;
        if (want)
            Quickshell.execDetached(["/usr/sbin/hyprctl", "eval", 'hl.bind("Escape", hl.dsp.exec_cmd("/usr/sbin/qs ipc call shell closePanel"))']);
        else
            Quickshell.execDetached(["/usr/sbin/hyprctl", "eval", 'hl.unbind("Escape")']);
    }

    onShellOwnsKeyboardChanged: syncEscapeBind()

    // A shell that died with the bind in place would leave Escape dead in every
    // application, so clear it at startup. (A zero-delay Timer, not
    // Component.onCompleted: Quickshell's Singleton has no Component attached
    // object, and using one fails the whole config with "Non-existent attached
    // object".)
    Timer {
        running: true
        interval: 0
        onTriggered: Quickshell.execDetached(["/usr/sbin/hyprctl", "eval", 'hl.unbind("Escape")'])
    }

}
