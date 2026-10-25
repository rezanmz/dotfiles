pragma Singleton

// Small pure helpers shared by the widgets and panels. Anything that needs to
// match the output of the old waybar helper scripts lives here so the two
// implementations cannot drift.
import Quickshell
import Quickshell.Hyprland
import QtQuick

Singleton {
    // Window titles: strip the browser suffixes the waybar config used to
    // rewrite, so the bar shows the page title and not the app name it already
    // implies.
    readonly property var titleSuffixes: [
        " — Mozilla Firefox",
        " - Google Chrome",
        " - Chromium",
        " — Chromium",
        " - Mozilla Firefox"
    ]

    function cleanTitle(title: string): string {
        if (!title)
            return "";
        for (const suffix of titleSuffixes) {
            if (title.endsWith(suffix))
                return title.slice(0, -suffix.length);
        }
        return title;
    }

    function elide(s: string, max: int): string {
        if (!s)
            return "";
        return s.length > max ? s.slice(0, max - 1) + "…" : s;
    }

    // Throughput, matching the old net-speed script's shape (value + unit).
    function rate(bytesPerSecond: real): string {
        const b = Math.max(0, bytesPerSecond);
        if (b < 1024)
            return b.toFixed(0) + " B/s";
        if (b < 1024 * 1024)
            return (b / 1024).toFixed(1) + " K/s";
        if (b < 1024 * 1024 * 1024)
            return (b / 1048576).toFixed(1) + " M/s";
        return (b / 1073741824).toFixed(2) + " G/s";
    }

    function gib(bytes: real, digits: int): string {
        return (bytes / 1073741824).toFixed(digits === undefined ? 1 : digits);
    }

    // Fixed-width throughput field: the value padded to five characters, then a
    // three character unit. The old net-speed script padded for exactly this
    // reason — waybar re-rendered the module on every poll, so any change in
    // width shoved every module to its left sideways. With a monospace font
    // (Hack) padding is all it takes.
    function rateFixed(bytesPerSecond: real): string {
        let b = Math.max(0, bytesPerSecond);
        let unit = "B/s";
        if (b >= 1073741824) {
            b /= 1073741824;
            unit = "G/s";
        } else if (b >= 1048576) {
            b /= 1048576;
            unit = "M/s";
        } else if (b >= 1024) {
            b /= 1024;
            unit = "K/s";
        }
        const value = b < 1000 ? b.toFixed(1) : b.toFixed(0);
        return value.padStart(5) + " " + unit;
    }

    function pct(v: real): string {
        return Math.round(v) + "%";
    }

    // Right-aligned number for the bar's numeric readouts. Without it a value
    // crossing a digit boundary resizes its widget and shoves everything left of
    // it sideways — the same drift the old net-speed script padded against, and
    // the reason the throughput readout already uses a fixed field.
    function pad(v: real, width: int): string {
        return String(Math.round(v)).padStart(width);
    }

    // Boot age for the system panel's header: "up 3d 4h", dropping to hours and
    // minutes so the field never says "up 0d 0h".
    function uptimeText(seconds: real): string {
        if (!isFinite(seconds) || seconds <= 0)
            return "";
        const total = Math.floor(seconds);
        const days = Math.floor(total / 86400);
        const hours = Math.floor(total % 86400 / 3600);
        const minutes = Math.floor(total % 3600 / 60);
        if (days > 0)
            return "up " + days + "d " + hours + "h";
        if (hours > 0)
            return "up " + hours + "h " + minutes + "m";
        return "up " + minutes + "m";
    }

    // m:ss, used by the media player for track position.
    function duration(seconds: real): string {
        if (!isFinite(seconds) || seconds < 0)
            return "0:00";
        const total = Math.floor(seconds);
        const m = Math.floor(total / 60);
        const s = total % 60;
        return m + ":" + (s < 10 ? "0" : "") + s;
    }

    function pad2(n: int): string {
        return n < 10 ? "0" + n : "" + n;
    }

    // The shell renders on whichever output currently has focus, so a popup or
    // the OSD appears where the user is looking. Falls back to the first screen
    // when the compositor has not told us yet.
    function screenFor(name: string): var {
        const screens = Quickshell.screens;
        for (let i = 0; i < screens.length; i++) {
            if (screens[i].name === name)
                return screens[i];
        }
        return screens.length > 0 ? screens[0] : null;
    }

    function focusedScreen(): var {
        return screenFor(Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "");
    }

    // Raise the window of the app behind one of the shell's clickable surfaces
    // (a notification card, a tray entry). Nothing else can: the compositor
    // refuses the app's own activation request (misc:focus_on_activate = false,
    // see hypr/modules/40-look.lua), so an explicit click has to do it here.
    // `ids` are the names the sender is known by, most precise first: the
    // freedesktop `desktop-entry` hint (the app id verbatim for Wayland
    // clients), then the desktop-file icon, then the display name.
    function focusApp(ids: var): void {
        const wanted = [];
        for (const id of ids) {
            if (!id)
                continue;
            const name = String(id).toLowerCase().replace(/\.desktop$/, "");
            if (name.length >= 4 && wanted.indexOf(name) === -1)
                wanted.push(name);
        }
        if (wanted.length === 0)
            return;
        // Hyprland's own view of a window: the class (the Wayland app id for
        // Wayland clients, the X11 class otherwise) and the address to focus.
        // `lastIpcObject` alone is not enough — it stays partial for a window
        // that has only carried a title event so far.
        const windows = [];
        for (const win of Hyprland.toplevels.values) {
            const ipc = win.lastIpcObject || {};
            const wayland = win.wayland || {};
            windows.push({
                appId: String(ipc.class || ipc.initialClass || wayland.appId || "").toLowerCase(),
                address: String(ipc.address || win.address || "")
            });
        }
        const raise = (win) => {
            const hex = win.address;
            Hyprland.dispatch("hl.dsp.focus({window = \"address:" + (hex.startsWith("0x") ? hex : "0x" + hex) + "\"})");
        };
        // Exact app id before any substring match: "Telegram Desktop" must never
        // win over a desktop-entry hint that names another window precisely.
        for (const name of wanted) {
            for (const win of windows) {
                if (win.appId === name) {
                    raise(win);
                    return;
                }
            }
        }
        for (const name of wanted) {
            for (const win of windows) {
                if (win.appId !== "" && win.appId.indexOf(name) !== -1) {
                    raise(win);
                    return;
                }
            }
        }
    }
}
