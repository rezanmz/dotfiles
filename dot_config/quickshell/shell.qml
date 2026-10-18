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
        model: ["system", "audio", "bluetooth", "battery", "notifications", "media", "network", "calendar", "tray", "idle", "capture", "controls", "keys"]

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
        id: controlsPanel
        Controls {}
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
        case "controls":
            return controlsPanel;
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

    HyprlandFocusGrab {
        // The notification centre takes keyboard focus for its search field
        // (Popup.grabFocus = an xdg popup grab), and hyprland_focus_grab_v1
        // clears "if another focus grab or similar action is started" — which
        // would close the panel the instant it opens. Stand down for it: an
        // xdg popup grab dismisses itself on outside click, and the panel's
        // Popup syncs that back through Panels.close().
        active: Panels.anyOpen && Panels.current !== "notifications"
        windows: Panels.registry
        onCleared: Panels.close()
    }
}
