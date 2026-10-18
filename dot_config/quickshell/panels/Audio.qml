import QtQuick
import QtQuick.Layouts
import qs
import Quickshell.Io
import Quickshell.Services.Pipewire

// Audio panel: the mixer, and where `pavucontrol` used to be launched from.
//
// Output volume, mic mute, output device switching, and per-application
// streams with their own volume — all of it through the Pipewire service, so
// the numbers here and the bar readout are the same objects.
//
// A playing stream can also be routed: press its row and drag it onto an output
// row. The move itself runs `pactl move-sink-input` (see routeStream).
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

    // --- drag-to-route state ------------------------------------------------
    // `dragNode` is the stream being dragged, `dropTarget` the output row under
    // the pointer, and `dragPos` the pointer position in this window's
    // coordinates. The row only starts floating after a few pixels of movement,
    // so an ordinary press (a slider drag, a middle-click mute) does not flash
    // the dragged copy.
    property var dragNode: null
    property var dropTarget: null
    property point dragPos: Qt.point(0, 0)
    property point dragFrom: Qt.point(0, 0)
    property bool dragArmed: false

    function beginDrag(node, x, y): void {
        root.dragNode = node;
        root.dragPos = Qt.point(x, y);
        root.dragFrom = Qt.point(x, y);
        root.dropTarget = null;
        root.dragArmed = false;
    }

    function dragTo(x, y): void {
        root.dragPos = Qt.point(x, y);
        if (!root.dragArmed) {
            const dx = x - root.dragFrom.x;
            const dy = y - root.dragFrom.y;
            if (dx * dx + dy * dy < 36)
                return;
            root.dragArmed = true;
        }
        root.dropTarget = root.hitSink(x, y);
    }

    function endDrag(commit: bool): void {
        const node = root.dragNode;
        const sink = commit && root.dragArmed ? root.dropTarget : null;
        root.dragNode = null;
        root.dropTarget = null;
        root.dragArmed = false;
        if (node && sink)
            root.routeStream(node, sink);
    }

    // The output row under a window-coordinate point, or null. The coordinates
    // are window-wide so the hit test does not care which row the drag began in.
    function hitSink(x, y): var {
        for (let i = 0; i < sinkRepeater.count; i++) {
            const item = sinkRepeater.itemAt(i);
            if (!item)
                continue;
            const p = item.mapFromItem(null, x, y);
            if (p.x >= 0 && p.x <= item.width && p.y >= 0 && p.y <= item.height)
                return item.node;
        }
        return null;
    }

    // --- routing -------------------------------------------------------------
    // A dropped stream is moved with `pactl move-sink-input <index> <sink name>`.
    // The index belongs to the pulse layer and is not part of the Pipewire node,
    // so it is resolved from `pactl list sink-inputs`, matching each stream's
    // application.name / node.name — the same keys the Pipewire node exposes.
    // (`pactl list short sink-inputs` cannot do this: its rows carry only the
    // *client* index, and the client's name is not the stream's application
    // name — observed pw-cat vs pw-play.) No match means no move (logged,
    // nothing shown): guessing an index would silently reroute the wrong stream.
    property var routePending: null

    function routeStream(node, sink): void {
        root.routePending = {
            "node": node,
            "sink": sink
        };
        routeProbe.running = true;
    }

    function applyRoute(text: string): void {
        const pending = root.routePending;
        root.routePending = null;
        if (!pending)
            return;

        // The names pactl can be matched on: application.name first, node.name
        // as the fallback.
        const props = pending.node.properties ? pending.node.properties : {};
        const names = [];
        if (props["application.name"])
            names.push(props["application.name"].toLowerCase());
        if (pending.node.name)
            names.push(pending.node.name.toLowerCase());
        if (names.length === 0) {
            console.warn("audio: dragged stream has no application name; not moving");
            return;
        }

        // `pactl list sink-inputs` prints "Sink Input #<index>" blocks whose
        // Properties carry application.name / node.name.
        let index = "";
        let current = "";
        for (const line of text.split("\n")) {
            const header = line.match(/^Sink Input #(\d+)/);
            if (header) {
                current = header[1];
                continue;
            }
            const kv = line.match(/^\s*([\w. -]+) = "(.*)"$/);
            if (current !== "" && kv && (kv[1] === "application.name" || kv[1] === "node.name") && names.indexOf(kv[2].toLowerCase()) !== -1) {
                index = current;
                break;
            }
        }
        if (index === "") {
            console.warn("audio: no sink-input for \"" + names[0] + "\"; not moving");
            return;
        }

        routeMove.command = ["pactl", "move-sink-input", index, pending.sink.name];
        routeMove.running = true;
    }

    Process {
        id: routeProbe

        command: ["pactl", "list", "sink-inputs"]
        stdout: StdioCollector {
            id: routeProbeOut

            waitForEnd: true
            // Not onExited: that fires before the collector finalises, and the
            // parse would run over empty text (Capture.qml reads its pactl
            // output the same way).
            onStreamFinished: root.applyRoute(routeProbeOut.text)
        }
    }

    Process {
        id: routeMove
    }

    component StreamRow: Item {
        id: row

        required property var node

        width: parent.width
        implicitHeight: 26

        readonly property string label: node.description || node.nickname || node.name
        readonly property bool dragging: root.dragNode === row.node && root.dragArmed

        // The dragged row floats over its neighbours; the original goes dim.
        z: row.dragging ? 100 : 0
        opacity: row.dragging ? 0.35 : 1

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

        // Press-and-move drags the row onto an output. It sits *under* the
        // slider, so the slider keeps its own press handling.
        MouseArea {
            id: dragArea

            anchors.fill: parent
            cursorShape: Qt.OpenHandCursor

            onPressed: mouse => {
                const p = dragArea.mapToItem(null, mouse.x, mouse.y);
                root.beginDrag(row.node, p.x, p.y);
            }
            onPositionChanged: mouse => {
                if (!dragArea.pressed)
                    return;
                const p = dragArea.mapToItem(null, mouse.x, mouse.y);
                root.dragTo(p.x, p.y);
            }
            onReleased: root.endDrag(true)
            onCanceled: root.endDrag(false)
        }

        Slider {
            anchors.left: name.right
            anchors.right: percent.left
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            value: row.node.audio.volume
            onMoved: value => row.node.audio.volume = Math.max(0, Math.min(1, value))
        }

        // The floating copy that follows the pointer. It lives inside the row
        // (nothing clips it) so it renders over the rows below while the row is
        // raised; slightly translucent so the drop target under it stays seen.
        Rectangle {
            id: ghost

            readonly property point at: row.mapFromItem(null, root.dragPos.x, root.dragPos.y)

            visible: row.dragging
            width: row.width
            height: row.height
            radius: Theme.radius
            color: Theme.alpha(Theme.panelBg, 0.85)
            border.width: 1
            border.color: Theme.purple
            x: ghost.at.x - width / 2
            y: ghost.at.y - height / 2

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 2
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 52
                text: row.label
                elide: Text.ElideRight
                color: Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
            }

            Text {
                anchors.right: parent.right
                anchors.rightMargin: 2
                anchors.verticalCenter: parent.verticalCenter
                width: 40
                horizontalAlignment: Text.AlignRight
                text: Math.round(row.node.audio.volume * 100) + "%"
                color: Theme.comment
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
            }
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.MiddleButton
            onClicked: row.node.audio.muted = !row.node.audio.muted
        }
    }

    // An output row. While a stream is in flight these are the drop targets:
    // every one lights up, the one under the pointer lights up harder.
    component SinkRow: Item {
        id: sinkRow

        required property var node

        width: parent.width
        implicitHeight: 24

        readonly property bool armed: root.dragArmed
        readonly property bool hovered: root.dropTarget === sinkRow.node

        Rectangle {
            anchors.fill: parent
            radius: Theme.radius
            color: sinkRow.hovered ? Theme.alpha(Theme.purple, 0.25) : (sinkRow.armed ? Theme.alpha(Theme.purple, 0.12) : "transparent")
            border.width: sinkRow.hovered ? 1 : 0
            border.color: Theme.purple
        }

        Text {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: (sinkRow.node === Sound.sink ? "\uf111  " : "\uf10c  ") + (sinkRow.node.description || sinkRow.node.name)
            color: sinkRow.node === Sound.sink || sinkRow.hovered ? Theme.purple : Theme.comment
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            elide: Text.ElideRight
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            // preferredDefaultAudioSink is the hint to pipewire about which
            // node should be default; setting it is how the output device is
            // switched without a separate tool.
            onClicked: Pipewire.preferredDefaultAudioSink = sinkRow.node
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
        id: sinkRepeater

        model: Sound.sinks

        delegate: SinkRow {
            required property var modelData

            node: modelData
            visible: Sound.sinks.length > 1
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
