// No `//@ pragma UseQApplication`: that was only needed to hand the tray's
// dbusmenu to Qt's platform menu renderer. The menu is drawn by the shell now
// (TrayMenu.qml + panels/Tray.qml), so QtWidgets is not pulled in at all.
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs
import qs as Qs
import qs.panels
import qs.panels as PanelTypes

// Shell entry point.
//
// One process, one bar per monitor, one window per panel, plus the notification
// popups, the volume OSD and the launcher. Panels.qml owns which panel is open
// and which widget it hangs under; everything here is wiring.
//
// The focus grab dismisses panels when the user clicks anywhere that is not the
// bar or an open panel — upstream recommends it over PopupWindow.grabFocus,
// which cannot change while the window is open.
ShellRoot {
    // Applications launched from the launcher inherit this; without it they
    // start in the config directory, which is where the shell was started from.
    settings.workingDirectory: Quickshell.env("HOME")

    Variants {
        model: Quickshell.screens
        delegate: Bar {}
    }

    // SUPER+Tab: live workspace thumbnails, most-recently-used order.
    Switcher {}

    // Dragged out of the bar: a floating live view of another workspace.
    PiPWindow {}

    // Created while something is popping up, destroyed when the stack empties:
    // an idle window costs the same ~11 MiB as a busy one.
    LazyLoader {
        active: Notifs.popups.length > 0
        component: Component {
            NotifPopups {}
        }
    }
    Osd {}
    Launcher {}

    // The floating capture thumbnail (macOS's post-shot peek), only while it is
    // up. The binding also instantiates the capture singleton at startup, so
    // its IPC handler exists before any keybind calls it.
    LazyLoader {
        active: Qs.Capture.thumbVisible
        component: Component {
            ScreenshotThumb {}
        }
    }

    // Bar panels. Each one is a window, and a Qt Quick window costs about 11 MiB
    // whether or not it is on screen (measured: seven resident panel windows
    // added ~80 MiB to the shell), so a panel is created when it opens and
    // destroyed when it closes. The compiled component is cached, so this is
    // window setup, not a re-parse.
    Variants {
        model: ["system", "audio", "bluetooth", "battery", "notifications", "media", "network", "calendar", "tray", "idle", "capture", "power", "keys"]

        delegate: LazyLoader {
            required property string modelData

            active: Panels.current === modelData
            // Quickshell's LazyLoader names this `component` (QtQuick's Loader
            // calls it sourceComponent).
            component: panelComponent(modelData)
        }
    }

    Component {
        id: systemPanel
        System {}
    }

    Component {
        id: audioPanel
        Audio {}
    }

    Component {
        id: bluetoothPanel
        Bluetooth {}
    }

    Component {
        id: batteryPanel
        PanelTypes.Battery {}
    }

    Component {
        id: notificationsPanel
        Notifications {}
    }

    Component {
        id: mediaPanel
        Media {}
    }

    Component {
        id: networkPanel
        Network {}
    }

    Component {
        id: calendarPanel
        Calendar {}
    }

    Component {
        id: trayPanel
        Tray {}
    }

    Component {
        id: idlePanel
        Idle {}
    }

    Component {
        id: keysPanel
        PanelTypes.Keys {}
    }

    Component {
        id: powerPanel
        Power {}
    }

    Component {
        id: capturePanel
        // Qualified: this file's `Capture` would otherwise have to pick between
        // the singleton and this panel type (both modules are imported).
        PanelTypes.Capture {}
    }

    function panelComponent(name: string): var {
        switch (name) {
        case "system":
            return systemPanel;
        case "audio":
            return audioPanel;
        case "bluetooth":
            return bluetoothPanel;
        case "battery":
            return batteryPanel;
        case "notifications":
            return notificationsPanel;
        case "media":
            return mediaPanel;
        case "network":
            return networkPanel;
        case "calendar":
            return calendarPanel;
        case "tray":
            return trayPanel;
        case "idle":
            return idlePanel;
        case "keys":
            return keysPanel;
        case "power":
            return powerPanel;
        case "capture":
            return capturePanel;
        }
        return null;
    }

    // Singletons are created on first reference; this is what starts Cinema and
    // NightLight at boot (they cannot be instantiated explicitly: "Composite
    // Singleton Type Cinema is not creatable").
    readonly property var startupSingletons: [Cinema, NightLight]

    // Keyboard/bind entry points. The binds that used to launch a program
    // (SUPER+N for the notification history, SUPER+SPACE for the launcher) call
    // these instead, so a panel can be opened without a widget to click.
    IpcHandler {
        target: "shell"

        function openPanel(name: string): void {
            Panels.openByName(name);
        }

        // Volume keys. These used to run `wpctl set-volume 5%±` straight from a
        // Hyprland bind, but wpctl's percentage is not exactly 5% of the value the
        // bar shows (measured: the raw sink value went 74.90 -> 69.80, a 5.1%
        // step), so with rounding a keypress could read as six points, "75 to 69".
        // Going through the shell uses the same 5% the scroll uses, and the OSD
        // still reacts because it watches the sink.
        function volumeUp(): void {
            Sound.adjustVolume(Sound.step);
        }

        function volumeDown(): void {
            Sound.adjustVolume(-Sound.step);
        }

        function toggleMute(): void {
            Sound.toggleMute();
        }

        function closePanel(): void {
            Panels.close();
        }

        function togglePanel(name: string): void {
            if (Panels.current === name)
                Panels.close();
            else
                Panels.openByName(name);
        }
    }

    // Clicking outside dismisses the panel: the bar, the open panel and the
    // keyboard seat are allowed, anything else (any window, focused already or
    // not) counts as outside. The toplevel watch below catches the rest, such as
    // a workspace switch with the keyboard.
    HyprlandFocusGrab {
        // The notification centre and the power panel take an xdg popup grab of
        // their own — the centre because its search field has to be typed into,
        // the power panel so Escape can cancel a half-armed row — and
        // hyprland_focus_grab_v1 clears "if another focus grab or similar action
        // is started" — a layer grab alongside it would close the panel the
        // instant it opened. Both dismiss themselves: their xdg grab closes on
        // outside click and the panels sync that back through Panels.close().
        // Not while the crosshair is up, and not while one is being set up: it takes
        // exclusive keyboard focus, which clears this grab regardless of what is
        // whitelisted, and the clear closes the very panel the user is trying to
        // photograph (a calendar, a tray menu).
        active: Panels.anyOpen && Panels.current !== "notifications" && Panels.current !== "power" && !Selection.starting
        windows: Panels.registry
        onCleared: Panels.close()
    }

}
