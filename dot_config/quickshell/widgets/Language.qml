import QtQuick
import qs
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

// Active keyboard layout (US / Persian).
//
// Read-only indicator, as before: the layouts are switched by XKB's
// grp:ctrl_space_toggle (50-input.lua), and this machine's Lua Hyprland config
// exposes no switchxkblayout dispatcher to bind a click to.
//
// Two sources, because neither alone is enough: the event socket only reports
// *changes* (`activelayout`), so the initial state comes from one `hyprctl
// devices` read at startup, and every change after that arrives as an event.
Item {
    id: root

    property string layout: ""

    // XKB layout codes, in the order Hyprland reports them ("us,ir" here).
    property var codes: []

    // Keymap name (what the event carries) to layout code. Hyprland reports the
    // human name on the event, not the index, so the mapping is by name — and by
    // *prefix*, because the name carries the variant: with the `winkeys` variant
    // the Persian layout reports as "Persian (Windows)", which an exact-match
    // table missed and the bar then displayed verbatim.
    function codeFor(keymap: string): string {
        if (keymap.startsWith("English"))
            return "us";
        if (keymap.startsWith("Persian") || keymap.startsWith("Farsi"))
            return "ir";
        return "";
    }

    function labelFor(code: string): string {
        if (code === "us")
            return "EN";
        if (code === "ir")
            return "FA";
        return code.toUpperCase();
    }

    function applyDevices(text: string): void {
        const data = JSON.parse(text);
        for (const keyboard of data.keyboards) {
            if (!keyboard.layout)
                continue;
            root.codes = keyboard.layout.split(",");
            const index = keyboard.active_layout_index !== undefined ? keyboard.active_layout_index : 0;
            root.layout = root.labelFor(root.codes[Math.min(index, root.codes.length - 1)]);
            return;
        }
    }

    Process {
        id: devices

        running: true
        command: ["hyprctl", "-j", "devices"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.applyDevices(this.text)
        }
    }

    Connections {
        target: Hyprland

        function onRawEvent(event): void {
            if (event.name !== "activelayout")
                return;
            // "keyboard-name,Keymap Name"
            const keymap = event.data.slice(event.data.indexOf(",") + 1);
            const code = root.codeFor(keymap);
            root.layout = root.labelFor(code !== "" ? code : keymap);
        }
    }

    implicitWidth: root.layout === "" ? 0 : label.implicitWidth + Theme.margin * 2
    implicitHeight: Theme.barHeight

    Text {
        id: label

        anchors.centerIn: parent
        text: root.layout
        color: Theme.fg
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
    }
}
