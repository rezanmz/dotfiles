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

    // One switchable row: label on the left, state detail on the right.
    component ToggleRow: Item {
        id: row

        property string label: ""
        property string detail: ""
        property bool active: false
        property color accent: Theme.purple
        property color labelColor: Theme.fg
        property color detailColor: row.active ? Theme.green : Theme.comment
        signal chosen()

        width: parent.width
        implicitHeight: 32

        Rectangle {
            anchors.fill: parent
            radius: Theme.radius
            color: hover.hovered ? Theme.hoverBg : (row.active ? Theme.alpha(Theme.selection, 0.55) : "transparent")
            Behavior on color {
                ColorAnimation {
                    duration: Theme.animationFast
                }
            }

            // The active choice carries the same left bar the launcher's
            // selection uses, so "this is the one" reads the same everywhere.
            Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.margins: 6
                width: 3
                radius: 2
                visible: row.active
                color: row.accent
            }
        }

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            text: row.label
            color: row.labelColor
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
        }

        Text {
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
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
        property color fillColour: Theme.purple
        signal moved(real value)

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
            width: track.width * Math.max(0, Math.min(1, slider.value))
            height: 6
            radius: 3
            color: slider.fillColour
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onPressed: mouse => slider.moved(mouse.x / width)
            onPositionChanged: mouse => {
                if (pressed)
                    slider.moved(mouse.x / width);
            }
        }
    }

    // Label + slider + percent, one row.
    component SliderRow: Item {
        id: sliderRow

        property string label: ""
        property real value: 0
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
            fillColour: sliderRow.fillColour
            onMoved: value => sliderRow.moved(value)
        }

        Text {
            id: percent

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: 40
            horizontalAlignment: Text.AlignRight
            text: Math.round(sliderRow.value * 100) + "%"
            color: Theme.comment
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
        }
    }

    // `loginctl lock-session` — the same call the launcher's Lock entry makes;
    // whatever lock screen the session has picks it up from there.
    Process {
        id: lock

        command: ["loginctl", "lock-session"]
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
        detail: NightLight.enabled ? "on" : "off"
        active: NightLight.enabled
        accent: Theme.pink
        onChosen: NightLight.enabled = !NightLight.enabled
    }

    SliderRow {
        label: "strength"
        value: NightLight.strength
        fillColour: Theme.pink
        onMoved: value => NightLight.strength = Math.max(0, Math.min(1, value))
    }

    ToggleRow {
        label: "Warm"
        detail: Math.round(NightLight.strengthWarm * 100) + "%"
        active: NightLight.enabled && Math.abs(NightLight.strength - NightLight.strengthWarm) < 0.005
        accent: Theme.pink
        detailColor: Theme.comment
        onChosen: NightLight.setWarm()
    }

    ToggleRow {
        label: "Warmer"
        detail: Math.round(NightLight.strengthWarmer * 100) + "%"
        active: NightLight.enabled && Math.abs(NightLight.strength - NightLight.strengthWarmer) < 0.005
        accent: Theme.pink
        detailColor: Theme.comment
        onChosen: NightLight.setWarmer()
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

    Section {
        text: "session"
    }

    ToggleRow {
        label: "Lock now"
        detail: ""
        active: false
        onChosen: lock.running = true
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
