pragma Singleton

// State for the tray item menu.
//
// Tray items publish a DBusMenu; quickshell can either hand it to Qt's own menu
// renderer (SystemTrayItem.display, which needs QApplication mode and draws a
// platform menu that looks nothing like the shell) or read it with QsMenuOpener
// and draw it here. The second is what this does: the menu is part of the shell,
// so it matches.
//
// The stack is the drill-down path. A QsMenuEntry with children is itself a menu
// handle, so entering a submenu is pushing that entry and going back is popping
// it — no second window, no hover-submenu timing to get wrong.
import Quickshell
import Quickshell.DBusMenu

Singleton {
    id: root

    // Handles, root first. Empty when no menu is open.
    property var stack: []

    // The tray item this menu belongs to, kept for the title row.
    property var item: null

    readonly property var current: root.stack.length > 0 ? root.stack[root.stack.length - 1] : null
    readonly property bool open: root.stack.length > 0

    function openFor(item: var, anchor: var): void {
        if (!item || !item.menu)
            return;
        root.item = item;
        root.stack = [item.menu];
        Panels.registerAnchor("tray", anchor);
        Panels.openByName("tray");
    }

    function drill(entry: var): void {
        root.stack = root.stack.concat([entry]);
    }

    function back(): void {
        if (root.stack.length > 1)
            root.stack = root.stack.slice(0, -1);
    }

    function close(): void {
        root.stack = [];
        Panels.close();
    }
}
