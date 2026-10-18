pragma Singleton

// Cinema mode: a fullscreen window is focused.
//
// Two shared flags, one condition. While it is active:
//   Notifs.suppress  — notifications are kept in the history but do not pop up
//                      (the same path dnd uses; see Notifs.add).
//   IdleGuard.cinema — the idle inhibitor is held, so hypridle cannot blank or
//                      lock the screen mid-film.
// Both are cleared when the fullscreen window loses focus or is un-fullscreened.
//
// "Fullscreen" is hyprctl's `fullscreen` field on the focused client (0 = no,
// 1 = maximized, 2 = fullscreen) — verified against `hyprctl -j activewindow`.
// `Hyprland.activeToplevel` is the focused one (the entry that would carry
// `activated` in a scan of `Hyprland.toplevels`).
//
// The state itself comes from the window's ext-foreign-toplevel handle
// (`wayland.fullscreen` / `wayland.maximized`, which map 1:1 onto the hyprctl
// modes 2 and 1): those are pushed with change signals. The IPC mirror
// (`lastIpcObject.fullscreen`) is only a snapshot from the last `hyprctl
// clients` query — measured stale across fullscreen changes, re-hydrated only
// by Hyprland.refreshToplevels() — so it is used only for windows that have no
// wayland handle yet.
//
// `enabled` is the panel's off switch for the behaviour; it clears both flags
// when it goes false, so nothing is left held.
import QtQuick
import Quickshell
import Quickshell.Hyprland

Singleton {
    id: root

    property bool enabled: true

    // The focused window is fullscreen or maximized (hyprland's `fullscreen`
    // field is non-zero for both).
    readonly property bool fullscreen: {
        const top = Hyprland.activeToplevel;
        if (!top)
            return false;
        const wl = top.wayland;
        if (wl)
            return wl.fullscreen || wl.maximized;
        return (top.lastIpcObject && (top.lastIpcObject.fullscreen || 0) !== 0);
    }

    readonly property bool active: root.enabled && root.fullscreen

    onActiveChanged: root.sync()
    Component.onCompleted: root.sync()

    function sync(): void {
        Notifs.suppress = root.active;
        IdleGuard.cinema = root.active;
    }
}
