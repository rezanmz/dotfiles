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
// Panels are dismissed by watching what Hyprland focuses (see the Connections at
// the end of the file). There is deliberately no HyprlandFocusGrab: the protocol
// takes the keyboard for the whole seat, so a panel open on one monitor swallowed
// every keybind on the others.
ShellRoot {
    // Applications launched from the launcher inherit this; without it they
    // start in the config directory, which is where the shell was started from.
    settings.workingDirectory: Quickshell.env("HOME")

    Variants {
        model: Quickshell.screens
        delegate: Bar {}
    }

    // Escape while a panel is open: a click-through overlay that holds the
    // keyboard, because a panel window cannot. Maps and unmaps with the panel.
    Escape {}

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
        model: ["system", "audio", "bluetooth", "drives", "notifications", "media", "network", "calendar", "tray", "idle", "capture", "power", "keys"]

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
        id: drivesPanel
        Drives {}
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
        case "drives":
            return drivesPanel;
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

        // TEMPORARY verification hook: exercises DrivesState from outside the
        // shell (there is no other way to click a row from a script).
        function drivesDump(): string {
            return JSON.stringify({
                volumes: DrivesState.volumes,
                automount: DrivesState.automount,
                notifications: DrivesState.notifications,
                status: DrivesState.status
            });
        }

        function drivesMount(index: int): void {
            DrivesState.mount(DrivesState.volumes[index]);
        }

        function drivesUnmount(index: int): void {
            DrivesState.unmount(DrivesState.volumes[index]);
        }

        function drivesToggleAutomount(): void {
            DrivesState.setAutomount(!DrivesState.automount);
        }

        function drivesRefresh(): void {
            DrivesState.refresh();
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

        // Brightness keys. This desktop has no backlight and no DDC, so the only
        // brightness there is, is hyprsunset's gamma ramp (NightLight.qml). Both
        // keys go through the same adjustBrightness() the bar's readout scrolls,
        // so a keypress steps 5% — the same step, the same clamp, one place.
        function brightnessUp(): void {
            NightLight.adjustBrightness(1);
        }

        function brightnessDown(): void {
            NightLight.adjustBrightness(-1);
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

    // Dismissing a panel when the user goes elsewhere.
    //
    // This used to be a HyprlandFocusGrab — upstream's recommendation, and it
    // dismisses on any outside click. The problem is what the protocol grabs:
    // hyprland_focus_grab_v1 takes the keyboard (and pointer) for the whole seat,
    // so while any panel was open on any monitor, every keybind on every other
    // monitor was swallowed: SUPER+1 did nothing until the panel was closed by
    // hand. Only the grabbing client ever sees those keys, and the shell does not
    // want them.
    //
    // So the dismissal comes from events instead. Two things mean "the user is
    // working somewhere else, close it": a new active window (a click on any
    // window) and a workspace switch (keybind or click, on any monitor). Clicking
    // the widget that opened the panel still toggles it, and clicking the empty
    // stretch of a bar still closes it (Bar.qml).
    //
    // A null active window is ambiguous: it is what a click on the empty desktop
    // looks like, and it is also what some panel-opening paths look like. So it
    // dismisses only once the panel has been up for longer than a click, which
    // rules out closing the panel that the same click opened. Everything else
    // (a real window becoming active) dismisses immediately.
    Connections {
        target: Hyprland

        function onActiveToplevelChanged(): void {
            if (!Panels.anyOpen)
                return;
            if (Hyprland.activeToplevel === null) {
                if (Date.now() - Panels.openedAt > 250)
                    Panels.close();
                return;
            }
            Panels.close();
        }

        function onFocusedWorkspaceChanged(): void {
            if (Panels.anyOpen)
                Panels.close();
        }
    }
}
