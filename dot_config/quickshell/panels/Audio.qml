import QtQuick
import QtQuick.Layouts
import qs
import Quickshell.Io

// Audio panel: the mixer, and where `pavucontrol` used to be launched from.
//
// Output volume, mic mute, output device switching, and per-application
// streams with their own volume — all of it through the Pipewire service, so
// the numbers here and the bar readout are the same objects. The default
// device pickers (output and input) and the volume feedback toggle live here
// too, moved over when the Control Centre was dismantled: choosing devices is
// the mixer's job.
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
        root.dropTarget = outputPicker.hitNode(x, y);
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

    // `pactl set-default-sink/-source <name>` — the pickers' way to move the
    // pipewire default (verified to take effect; wpctl's ids are its own
    // numbering and did not match pipewire's).
    Process {
        id: defaultRun
    }

    function setDefault(kind: string, name: string): void {
        defaultRun.command = ["pactl", "set-default-" + kind, name];
        defaultRun.running = true;
        if (kind === "source")
            root.defaultSourceName = name;
    }

    // The current default *input*, as the pulse layer names it. Quickshell's
    // defaultAudioSource is null whenever the default input is a sink monitor
    // (this machine's usual state — there is no microphone), so the panel asks
    // `pactl`, the same interface set-default-source speaks. Re-asked on open,
    // on each pick, and every couple of seconds while the panel is open, so an
    // outside change (pavucontrol, the pickers themselves) is reflected.
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

    onOpenChanged: {
        if (root.open)
            sourceProbe.running = true;
    }

    Timer {
        interval: 2000
        repeat: true
        running: root.open
        onTriggered: sourceProbe.running = true
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

    // One switchable row, the shell's row idiom (the idle panel's and the power
    // panel's): hover fills the row, the active choice carries the purple left
    // bar, and the right-hand detail is green while a thing is on and
    // comment-grey while it is off. Used by the volume feedback toggle and as
    // the device pickers' header.
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
        implicitHeight: Math.max(32, detailText.implicitHeight + 10)

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

    // One choice in a device picker: filled dot on the current default, hollow
    // on the rest, purple while it is the one or under the pointer. The output
    // picker's rows are also the drag-to-route drop targets: while a stream is
    // in flight every one lights up, the one under the pointer harder.
    component DeviceRow: Item {
        id: deviceRow

        property var node: null
        property bool current: false
        property bool drops: false
        signal choose()

        readonly property bool dropArmed: deviceRow.drops && root.dragArmed
        readonly property bool dropHover: deviceRow.drops && root.dropTarget === deviceRow.node

        width: parent.width
        implicitHeight: 24

        Rectangle {
            anchors.fill: parent
            radius: Theme.radius
            color: deviceRow.dropHover || hover.hovered ? Theme.alpha(Theme.purple, 0.25) : (deviceRow.dropArmed ? Theme.alpha(Theme.purple, 0.12) : "transparent")
            border.width: deviceRow.dropHover ? 1 : 0
            border.color: Theme.purple
        }

        Text {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: (deviceRow.current ? String.fromCodePoint(0xF111) + "  " : String.fromCodePoint(0xF10C) + "  ") + (deviceRow.node.description || deviceRow.node.name)
            color: deviceRow.current || hover.hovered || deviceRow.dropHover ? Theme.purple : Theme.comment
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
    // changes made outside the shell, by pavucontrol or a pactl call), and a
    // click widens the row into the device list with the current one marked.
    // With one device (or none) there is nothing to pick and the row stays a
    // readout. The rows double as the stream-dragging drop surface, so they
    // show while a drag is in flight even when the list is folded.
    component DevicePicker: Item {
        id: picker

        property string label: ""
        property var devices: []
        // Pulse name of the current default ("a sink's node name for output,
        // `<sink>.monitor` or the node name for input).
        property string currentName: ""
        property string noneText: ""
        property bool expanded: false
        property bool drops: false
        signal pick(string name)

        readonly property bool choosable: picker.devices.length > 1
        readonly property bool dropRows: picker.drops && root.dragArmed

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
                id: rows

                model: picker.expanded || picker.dropRows ? picker.devices : null
                delegate: DeviceRow {
                    required property var modelData

                    node: modelData
                    current: modelData.name === picker.currentName
                    drops: picker.drops
                    onChoose: picker.pick(modelData.name)
                }
            }
        }

        // The row under a window-coordinate point, or null. The coordinates
        // are window-wide so the hit test does not care which row the drag
        // began in.
        function hitNode(x: real, y: real): var {
            for (let i = 0; i < rows.count; i++) {
                const item = rows.itemAt(i);
                if (!item)
                    continue;
                const p = item.mapFromItem(null, x, y);
                if (p.x >= 0 && p.x <= item.width && p.y >= 0 && p.y <= item.height)
                    return item.node;
            }
            return null;
        }
    }

    Section {
        text: "output"
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

    // Volume feedback (macOS's "Play feedback when volume is changed") and the
    // default-device pickers, moved here from the Control Centre when it was
    // dismantled: the mixer is where device choice and volume behaviour live.
    ToggleRow {
        label: "volume feedback"
        detail: Feedback.enabled ? "on" : "off"
        active: Feedback.enabled
        onChosen: Feedback.enabled = !Feedback.enabled
    }

    // Device pickers: output and input, both following the current default
    // wherever it was set — here, or pavucontrol. The output picker is also
    // where a dragged stream is dropped (see DeviceRow), so its rows show up
    // whenever a drag is in flight.
    DevicePicker {
        id: outputPicker

        label: "output"
        devices: Sound.sinks
        currentName: Sound.sink ? Sound.sink.name : ""
        noneText: "no output device"
        drops: true
        onPick: name => root.setDefault("sink", name)
    }

    DevicePicker {
        label: "input"
        devices: Sound.sources
        currentName: root.defaultSourceName
        noneText: "no input device"
        onPick: name => root.setDefault("source", name)
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
