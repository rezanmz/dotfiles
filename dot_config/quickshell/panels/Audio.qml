import QtQuick
import QtQuick.Layouts
import qs
import Quickshell.Services.Pipewire

// Audio panel: the mixer, and where `pavucontrol` used to be launched from.
//
// Output volume, mic mute, output device switching, and per-application
// streams with their own volume — all of it through the Pipewire service, so
// the numbers here and the bar readout are the same objects.
Popup {
    id: root

    name: "audio"
    contentWidth: 380

    // A click/drag bar. Small enough to keep local: the panel needs three of
    // them and nothing else in the shell does.
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

    component Section: Text {
        color: Theme.comment
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSmall
        font.capitalization: Font.AllUppercase
    }

    component StreamRow: Item {
        id: row

        required property var node

        width: parent.width
        implicitHeight: 26

        readonly property string label: node.description || node.nickname || node.name

        Text {
            id: name

            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: 130
            text: row.label
            elide: Text.ElideRight
            color: row.node.audio.muted ? Theme.comment : Theme.fg
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
        }

        Slider {
            anchors.left: name.right
            anchors.right: percent.left
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            value: row.node.audio.volume
            onMoved: value => row.node.audio.volume = Math.max(0, Math.min(1, value))
        }

        Text {
            id: percent

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: 40
            horizontalAlignment: Text.AlignRight
            text: Math.round(row.node.audio.volume * 100) + "%"
            color: Theme.comment
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.MiddleButton
            onClicked: row.node.audio.muted = !row.node.audio.muted
        }
    }

    Section {
        text: "output"
    }

    Text {
        text: Sound.sinkName === "" ? "no output device" : Sound.sinkName
        color: Theme.fg
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
        elide: Text.ElideRight
        width: parent.width
    }

    RowLayout {
        width: parent.width
        spacing: 10

        Text {
            text: Sound.muted ? "\uf026" : (Sound.volume < 0.34 ? "\uf026" : (Sound.volume < 0.67 ? "\uf027" : "\uf028"))
            color: Sound.muted ? Theme.comment : Theme.purple
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: Sound.toggleMute()
            }
        }

        Slider {
            Layout.fillWidth: true
            value: Sound.volume
            fillColour: Sound.muted ? Theme.comment : Theme.purple
            onMoved: value => Sound.setVolume(value)
        }

        Text {
            Layout.preferredWidth: 40
            horizontalAlignment: Text.AlignRight
            text: Math.round(Sound.volume * 100) + "%"
            color: Theme.fg
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
        }
    }

    Text {
        width: parent.width
        text: Sound.micMuted ? "microphone muted — click to unmute" : "microphone live — click to mute"
        color: Sound.micMuted ? Theme.red : Theme.comment
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSmall

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: Sound.toggleMicMute()
        }
    }

    Section {
        text: "outputs"
        visible: Sound.sinks.length > 1
    }

    Repeater {
        model: Sound.sinks

        delegate: Text {
            required property var modelData

            width: parent.width
            text: (modelData === Sound.sink ? "\uf111  " : "\uf10c  ") + (modelData.description || modelData.name)
            color: modelData === Sound.sink ? Theme.purple : Theme.comment
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            elide: Text.ElideRight
            visible: Sound.sinks.length > 1

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                // preferredDefaultAudioSink is the hint to pipewire about which
                // node should be default; setting it is how the output device is
                // switched without a separate tool.
                onClicked: Pipewire.preferredDefaultAudioSink = modelData
            }
        }
    }

    Section {
        text: "playing"
        visible: Sound.streams.length > 0
    }

    Repeater {
        model: Sound.streams

        delegate: StreamRow {
            required property var modelData

            node: modelData
        }
    }

    Text {
        width: parent.width
        text: "no applications are playing"
        visible: Sound.streams.length === 0
        color: Theme.comment
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSmall
    }
}
