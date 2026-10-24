pragma Singleton

// Which panel is open, and which widget each panel hangs under.
//
// The old bar could only run a command on click; the shell can show a real
// panel, so something has to own "only one panel at a time" — clicking a second
// widget closes the first, clicking outside closes everything. That is this
// object. Panels are addressed by a short string (`calendar`, `audio`, ...)
// which the widget sets as its `panel` property and the popup matches by name.
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


}
