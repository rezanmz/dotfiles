pragma Singleton

// State for the tray menu.
//
// Tray items publish a DBusMenu; quickshell can either hand it to Qt's own menu
// renderer (SystemTrayItem.display, which needs QApplication mode and draws a
// platform menu that looks nothing like the shell) or read it with QsMenuOpener
// and draw it here. The second is what this does: the menu is part of the shell,
// so it matches.
//
// TWO LEVELS OF STATE
//   stack empty -> the panel lists every tray item. This is what the bar's
//                  single tray icon opens: five icons in the bar pushed the
//                  readouts the user watches out of the way, and the list is one
//                  click away either way.
//   stack full  -> the menu of the item picked from that list, with the
//                  drill-down path inside it.
// A QsMenuEntry with children is itself a menu handle, so entering a submenu is
// pushing that entry and going back is popping it — no second window, no
// hover-submenu timing to get wrong.
import QtQuick
import Quickshell
import Quickshell.DBusMenu

Singleton {
    id: root

    // Handles, root first. Empty means "show the item list".
    property var stack: []

    // The tray item this menu belongs to, kept for the title row.
    property var item: null

    readonly property bool atList: root.stack.length === 0
    readonly property var current: root.stack.length > 0 ? root.stack[root.stack.length - 1] : null
    readonly property bool open: root.stack.length > 0

    // Closing the panel always returns the panel to the item list, so the tray
    // icon never reopens on a half-navigated submenu of an item the user has
    // forgotten about.
    Connections {
        target: Panels

        function onCurrentChanged(): void {
            if (Panels.current !== "tray")
                root.reset();
        }
    }

    function reset(): void {
        root.stack = [];
        root.item = null;
    }

    // Called from the panel's item list.
    function openFor(item: var): void {
        if (!item || !item.menu)
            return;
        root.item = item;
        root.stack = [item.menu];
    }

    function drill(entry: var): void {
        root.stack = root.stack.concat([entry]);
    }

    // One level up: out of a submenu, and out of the item's menu back to the
    // item list.
    function back(): void {
        if (root.stack.length > 1)
            root.stack = root.stack.slice(0, -1);
        else
            root.reset();
    }

    function close(): void {
        root.reset();
        Panels.close();
    }
}
