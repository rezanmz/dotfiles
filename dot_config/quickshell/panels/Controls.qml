import QtQuick
import qs
import Quickshell
import Quickshell.Io
import Quickshell.Networking as Net
import Quickshell.Bluetooth as BT

// Controls panel: the switches that used to be one-off keybinds or
// `nmcli`/`bluetoothctl` invocations, in one place.
//
// Row semantics are the idle panel's: hover fills the row, the active choice
// carries the purple left bar, and the right-hand detail is green while a thing
// is on and comment-grey while it is off. Cinema mode is a three-state readout —
// "active" while a fullscreen window is focused, "auto" while armed, "off" when
// the behaviour is disabled — because it is normally driven by the window state,
// not by the user.
//
// The sound section carries the device pickers: output and input widen into the
// mixer's device list and set the pipewire default through `pactl`. The power
// section at the bottom runs the launcher's power-menu commands; the four
// destructive rows arm first (red row, detail says what a second click runs)
// and the arming expires after four seconds or when the panel closes.
//
// The Bluetooth and Networking service singletons are aliased (`BT`, `Net`):
// `Bluetooth` would otherwise collide with the sibling panels/Bluetooth.qml
// type in this directory, which resolves silently and wrongly.
Popup {
    id: root

    name: "controls"
    contentWidth: 340

    component Section: Text {
        color: Theme.comment
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSmall
        font.capitalization: Font.AllUppercase
    }

    // One switchable row: label on the left, state detail on the right. A row
    // can also be *armed* — the first click on a destructive action — which
    // turns it red and spells out in the detail what a confirming second click
    // will run; the detail wraps to a second line for that.
    component ToggleRow: Item {
        id: row

        property string label: ""
        property string detail: ""
        property bool active: false
        property bool armed: false
        property color accent: Theme.purple
        property color labelColor: row.armed ? Theme.red : Theme.fg
        property color detailColor: row.armed ? Theme.red : (row.active ? Theme.green : Theme.comment)
        signal chosen()

        width: parent.width
        implicitHeight: Math.max(32, detailText.implicitHeight + 10)

        Rectangle {
            anchors.fill: parent
            radius: Theme.radius
            color: row.armed ? Theme.alpha(Theme.red, 0.25) : (hover.hovered ? Theme.hoverBg : (row.active ? Theme.alpha(Theme.selection, 0.55) : "transparent"))
            Behavior on color {
                ColorAnimation {
                    duration: Theme.animationFast
                }
            }

            // The active choice carries the same left bar the launcher's
            // selection uses, so "this is the one" reads the same everywhere;
            // an armed row borrows it in red.
            Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.margins: 6
                width: 3
                radius: 2
                visible: row.active || row.armed
                color: row.armed ? Theme.red : row.accent
            }
        }

        Text {
            id: labelText

            anchors.left: parent.left
            anchors.leftMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            text: row.label
            color: row.labelColor
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
        }

        Text {
            id: detailText

            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(0, row.width - labelText.width - 40)
            horizontalAlignment: Text.AlignRight
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            text: row.detail
            color: row.detailColor
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
        }

        HoverHandler {
            id: hover
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: row.chosen()
        }
    }

    // A click/drag bar, the same shape the mixer panel uses.
    component Slider: Item {
        id: slider

        property real value: 0
        property real from: 0
        property real to: 1
        property color fillColour: Theme.purple
        signal moved(real value)

        // Where the fill ends: the value as a fraction of the slider's range.
        readonly property real fraction: (slider.to - slider.from) === 0 ? 0 : Math.max(0, Math.min(1, (slider.value - slider.from) / (slider.to - slider.from)))

        // A click at x reports the value that position stands for.
        function valueAt(x: real): real {
            const f = Math.max(0, Math.min(1, x / width));
            return slider.from + f * (slider.to - slider.from);
        }

        implicitHeight: 20

        Rectangle {
            id: track

            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            height: 6
            radius: 3
            color: Theme.alpha(Theme.comment, 0.45)
        }

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: track.width * slider.fraction
            height: 6
            radius: 3
            color: slider.fillColour
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor

            // One notch moves a twentieth of the row's range, the same gesture the
            // volume row and the bar readouts use. Wheel.steps counts the detents
            // (one per 120 units) instead of trusting the event count: the input
            // stack packs one detent into one, several or merged events, and the
            // panel must step once per notch like the bar and the OSD.
            onWheel: wheel => {
                const n = Wheel.steps(wheel.angleDelta.y !== 0 ? wheel.angleDelta.y : wheel.angleDelta.x, wheel.pixelDelta.y !== 0 ? wheel.pixelDelta.y : wheel.pixelDelta.x, "controls");
                if (n !== 0)
                    slider.moved(Math.max(slider.from, Math.min(slider.to, slider.value + n * (slider.to - slider.from) / 20)));
            }

            onPressed: mouse => slider.moved(slider.valueAt(mouse.x))
            onPositionChanged: mouse => {
                if (pressed)
                    slider.moved(slider.valueAt(mouse.x));
            }
        }
    }

    // Label + slider + percent, one row.
    component SliderRow: Item {
        id: sliderRow

        property string label: ""
        property real value: 0
        property real from: 0
        property real to: 1
        // Shown on the right; empty means the 0..1 percent form.
        property string valueText: ""
        property color fillColour: Theme.purple
        signal moved(real value)

        width: parent.width
        implicitHeight: 30

        Text {
            id: name

            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: 80
            text: sliderRow.label
            color: Theme.fg
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
        }

        Slider {
            anchors.left: name.right
            anchors.right: percent.left
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            value: sliderRow.value
            from: sliderRow.from
            to: sliderRow.to
            fillColour: sliderRow.fillColour
            onMoved: value => sliderRow.moved(value)
        }

        Text {
            id: percent

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: 40
            horizontalAlignment: Text.AlignRight
            text: sliderRow.valueText !== "" ? sliderRow.valueText : Math.round(sliderRow.value * 100) + "%"
            color: Theme.comment
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
        }
    }

    // One choice in a device picker: the mixer's sink row — filled dot on the
    // current default, hollow on the rest, purple while it is the one or under
    // the pointer.
    component DeviceRow: Item {
        id: deviceRow

        property var node: null
        property bool current: false
        signal choose()

        width: parent.width
        implicitHeight: 24

        Rectangle {
            anchors.fill: parent
            radius: Theme.radius
            color: hover.hovered ? Theme.alpha(Theme.purple, 0.25) : "transparent"
        }

        Text {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: (deviceRow.current ? "\uf111  " : "\uf10c  ") + (deviceRow.node.description || deviceRow.node.name)
            color: deviceRow.current || hover.hovered ? Theme.purple : Theme.comment
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            elide: Text.ElideRight
        }

        HoverHandler {
            id: hover
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: deviceRow.choose()
        }
    }

    // A pick-one device row: the header reads the current default (following
    // changes made outside the shell, by the mixer or pavucontrol), and a click
    // widens the row into the mixer's device list with the current one marked.
    // With one device (or none) there is nothing to pick and the row stays a
    // readout.
    component DevicePicker: Item {
        id: picker

        property string label: ""
        property var devices: []
        // Pulse name of the current default ("a sink's node name for output,
        // `<sink>.monitor` or the node name for input).
        property string currentName: ""
        property string noneText: ""
        property bool expanded: false
        signal pick(string name)

        readonly property bool choosable: picker.devices.length > 1

        // The current device's human name, whatever list it came from.
        readonly property string currentLabel: {
            for (let i = 0; i < picker.devices.length; i++) {
                if (picker.devices[i].name === picker.currentName)
                    return picker.devices[i].description || picker.devices[i].name;
            }
            return picker.currentName !== "" ? picker.currentName : picker.noneText;
        }

        width: parent.width
        implicitHeight: header.implicitHeight + list.height

        ToggleRow {
            id: header

            label: picker.label
            detail: picker.currentLabel
            enabled: picker.choosable
            onChosen: picker.expanded = !picker.expanded
        }

        Column {
            id: list

            anchors.top: header.bottom
            width: parent.width

            Repeater {
                model: picker.expanded ? picker.devices : null
                delegate: DeviceRow {
                    required property var modelData

                    node: modelData
                    current: modelData.name === picker.currentName
                    onChoose: picker.pick(modelData.name)
                }
            }
        }
    }

    // The power menu's commands, kept verbatim from the launcher's power menu
    // (Launcher.qml, powerActions) so the two stay in step: the session is
    // uwsm-managed, so log out is `uwsm stop`, and the destructive commands
    // carry the launcher's `||` fallbacks. They run through `sh -c` exactly as
    // the launcher runs them.
    Process {
        id: powerRun
    }

    // Destructive rows arm first: the first click names the row here and turns
    // it red, a second click within four seconds runs its command. The arming
    // expires on its own and is dropped whenever the panel closes, so a stale
    // "yes" can never fire later. Lock is not destructive and runs at once.
    property string armed: ""

    onOpenChanged: {
        if (!root.open) {
            root.armed = "";
            armTimer.stop();
        } else {
            sourceProbe.running = true;
        }
    }

    Timer {
        id: armTimer

        interval: 4000
        onTriggered: root.armed = ""
    }

    function armOrRun(key: string, command: string): void {
        if (root.armed !== key) {
            root.armed = key;
            armTimer.restart();
            return;
        }
        root.armed = "";
        armTimer.stop();
        powerRun.command = ["sh", "-c", command];
        powerRun.running = true;
    }

    // `pactl set-default-sink/-source <name>` — verified to move the pipewire
    // default (wpctl's ids are its own numbering and did not match pipewire's).
    Process {
        id: defaultRun
    }

    function setDefault(kind: string, name: string): void {
        root.armed = "";
        defaultRun.command = ["pactl", "set-default-" + kind, name];
        defaultRun.running = true;
        if (kind === "source")
            root.defaultSourceName = name;
    }

    // The current default *input*, as the pulse layer names it. Quickshell's
    // defaultAudioSource is null whenever the default input is a sink monitor
    // (this machine's usual state — there is no microphone), so the panel asks
    // `pactl`, the same interface set-default-source speaks. Re-asked on open,
    // after picking, and every couple of seconds while the panel is open, so an
    // outside change (pavucontrol, the mixer) is reflected.
    property string defaultSourceName: ""

    Process {
        id: sourceProbe

        command: ["pactl", "get-default-source"]
        stdout: StdioCollector {
            id: sourceProbeOut

            waitForEnd: true
            onStreamFinished: root.defaultSourceName = sourceProbeOut.text.trim()
        }
    }

    Timer {
        interval: 2000
        repeat: true
        running: root.open
        onTriggered: sourceProbe.running = true
    }

    readonly property var adapter: BT.Bluetooth.defaultAdapter

    Section {
        text: "focus"
    }

    ToggleRow {
        label: "Do not disturb"
        detail: Notifs.dnd ? "on" : "off"
        active: Notifs.dnd
        onChosen: Notifs.toggleDnd()
    }

    ToggleRow {
        label: "Cinema mode"
        detail: Cinema.active ? "active" : (Cinema.enabled ? "auto" : "off")
        active: Cinema.active || Cinema.enabled
        detailColor: Cinema.active ? Theme.green : (Cinema.enabled ? Theme.cyan : Theme.comment)
        onChosen: Cinema.enabled = !Cinema.enabled
    }

    Section {
        text: "screen"
    }

    ToggleRow {
        label: "Night light"
        detail: !NightLight.available ? "hyprsunset not running" : (NightLight.enabled ? NightLight.temperature + " K" : "off")
        active: NightLight.enabled
        accent: Theme.pink
        detailColor: !NightLight.available ? Theme.red : (NightLight.enabled ? Theme.pink : Theme.comment)
        onChosen: NightLight.enabled = !NightLight.enabled
    }

    // Warmth, not strength: the same control everyone else has, in Kelvin. The
    // slider runs neutral -> warmest, so dragging right warms, and moving it turns
    // the filter on rather than leaving a change you cannot see.
    SliderRow {
        label: "warmth"
        from: 0
        to: 4000
        value: NightLight.neutral - NightLight.temperature
        valueText: NightLight.temperature + " K"
        fillColour: Theme.pink
        onMoved: value => {
            NightLight.temperature = Math.round(NightLight.neutral - value);
            NightLight.enabled = true;
        }
    }

    ToggleRow {
        label: "Warm"
        detail: NightLight.warm + " K"
        active: NightLight.enabled && NightLight.temperature === NightLight.warm
        accent: Theme.pink
        detailColor: Theme.comment
        onChosen: NightLight.setWarm()
    }

    ToggleRow {
        label: "Warmer"
        detail: NightLight.warmer + " K"
        active: NightLight.enabled && NightLight.temperature === NightLight.warmer
        accent: Theme.pink
        detailColor: Theme.comment
        onChosen: NightLight.setWarmer()
    }

    // Brightness is hyprsunset's gamma ramp: 100% leaves the panel alone, below
    // that dims, above lifts past what the monitor's own controls allow. It is the
    // only brightness a desktop monitor without DDC can have, and unlike a shader
    // it stays out of screenshots.
    SliderRow {
        label: "brightness"
        from: 60
        to: NightLight.brightnessMax
        value: NightLight.brightness
        valueText: NightLight.brightness + "%"
        fillColour: Theme.purple
        onMoved: value => NightLight.brightness = Math.round(value)
    }

    Section {
        text: "devices"
    }

    ToggleRow {
        label: "Wi-Fi"
        detail: Net.Networking.wifiEnabled ? "on" : "off"
        active: Net.Networking.wifiEnabled
        onChosen: Net.Networking.wifiEnabled = !Net.Networking.wifiEnabled
    }

    ToggleRow {
        label: "Bluetooth"
        detail: root.adapter ? (root.adapter.enabled ? "on" : "off") : "no adapter"
        active: root.adapter !== null && root.adapter.enabled
        enabled: root.adapter !== null
        onChosen: root.adapter.enabled = !root.adapter.enabled
    }

    Section {
        text: "sound"
    }

    SliderRow {
        label: "Volume"
        value: Sound.volume
        onMoved: value => Sound.setVolume(value)
    }

    ToggleRow {
        label: "volume feedback"
        detail: Feedback.enabled ? "on" : "off"
        active: Feedback.enabled
        accent: Theme.purple
        onChosen: Feedback.enabled = !Feedback.enabled
    }

    // Device pickers: output and input, both following the current default
    // wherever it was set — this panel, the mixer, or pavucontrol.
    DevicePicker {
        label: "output"
        devices: Sound.sinks
        currentName: Sound.sink ? Sound.sink.name : ""
        noneText: "no output device"
        onPick: name => root.setDefault("sink", name)
    }

    DevicePicker {
        label: "input"
        devices: Sound.sources
        currentName: root.defaultSourceName
        noneText: "no input device"
        onPick: name => root.setDefault("source", name)
    }

    // The power menu: the launcher's commands verbatim (Launcher.qml,
    // powerActions — keep the two in step), so the two entry points always do
    // the same thing. Lock runs at once; the four destructive rows arm first —
    // one click turns the row red and names what a confirming second click
    // runs, and the arming expires after four seconds or when the panel closes.
    Section {
        text: "power"
    }

    ToggleRow {
        label: "Lock now"
        detail: "lock the session screen"
        onChosen: {
            root.armed = "";
            powerRun.command = ["sh", "-c", "loginctl lock-session"];
            powerRun.running = true;
        }
    }

    ToggleRow {
        label: "Log out"
        detail: root.armed === "logout" ? "ends the session — click again to confirm" : "end the session"
        armed: root.armed === "logout"
        onChosen: root.armOrRun("logout", "uwsm stop")
    }

    ToggleRow {
        label: "Suspend"
        detail: root.armed === "suspend" ? "suspends to RAM — click again to confirm" : "suspend to RAM"
        armed: root.armed === "suspend"
        onChosen: root.armOrRun("suspend", "systemctl suspend || suspend")
    }

    ToggleRow {
        label: "Restart"
        detail: root.armed === "restart" ? "restarts the system — click again to confirm" : "restart the system"
        armed: root.armed === "restart"
        onChosen: root.armOrRun("restart", "systemctl reboot || reboot")
    }

    ToggleRow {
        label: "Shut down"
        detail: root.armed === "shutdown" ? "shuts the system down — click again to confirm" : "shut the system down"
        armed: root.armed === "shutdown"
        onChosen: root.armOrRun("shutdown", "systemctl poweroff || poweroff")
    }

    // Only while a recording is running; hidden rows leave the column entirely.
    ToggleRow {
        label: "Stop recording"
        detail: "wf-recorder"
        active: true
        accent: Theme.red
        labelColor: Theme.red
        detailColor: Theme.red
        visible: Recorder.recording
        onChosen: Recorder.stop()
    }
}
