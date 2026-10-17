import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs
import "Fuzzy.js" as Fuzzy

// Launcher: applications and the clipboard history.
//
// Replaces anyrun, whose two jobs were "run an app" (applications plugin) and
// "pick a line from stdin" (the stdin plugin that clipboard-pick and dunst's
// dmenu fed). Both live here now, and the clipboard mode also removes the
// `cliphist list | anyrun | cliphist decode | wl-copy` pipeline: the shell decodes
// the entry and writes it to the clipboard itself.
//
// Ranking is Fuzzy.js (the same shape anyrun's rink plugin had), searched over
// name + genericName + keywords + comment + exec basename with the name
// weighted highest, and ordered by frecency — applications come from
// DesktopEntries, so nothing is re-read from disk per keystroke.
Scope {
    id: root

    property bool showing: false
    property string mode: "apps"
    property string query: ""
    property int selected: 0
    property var clipboardLines: []
    property string pendingLine: ""

    // Launch history: {id: {count, last}} with `last` in ms since the epoch,
    // persisted as JSON by frecencyLoad/frecencySave below. Reassigned (never
    // mutated in place) so the results binding re-evaluates.
    property var frecency: ({})

    // Card surface: the design language's near-black (darker than Theme.bg),
    // not a Theme token.
    readonly property color cardBg: "#1e1f29"

    // Cap on how many matches are materialised. The list scrolls, so this is a
    // sanity bound rather than the old "8 rows and no scrolling" limit anyrun had
    // upstream (which made rows past the cap unreachable).
    readonly property int maxResults: 300
    readonly property int rowHeight: 38
    readonly property int visibleRows: 10

    function open(mode: string): void {
        root.mode = mode;
        root.query = "";
        root.selected = 0;
        root.showing = true;
        if (mode === "clipboard")
            clipList.running = true;
    }

    function close(): void {
        root.showing = false;
    }

    function toggle(mode: string): void {
        if (root.showing && root.mode === mode)
            root.close();
        else
            root.open(mode);
    }

    // ---- applications --------------------------------------------------
    readonly property var applications: {
        const out = [];
        const apps = DesktopEntries.applications.values;
        for (let i = 0; i < apps.length; i++) {
            // NoDisplay entries are the ones that exist for mime-type handling,
            // not for launching by hand.
            if (!apps[i].noDisplay)
                out.push(apps[i]);
        }
        return out;
    }

    // Basename of the executable, e.g. "google-chrome-stable" for
    // Exec=/usr/bin/google-chrome-stable %U. Searches "chrome" by command.
    function execBasename(app: var): string {
        const cmd = app.command;
        const first = cmd.length > 0 ? cmd[0] : app.execString.trim().split(/\s+/)[0];
        const parts = first.split("/");
        return parts[parts.length - 1];
    }

    // The weighted fields an application is searched over. The name carries the
    // biggest weight so name matches outrank the rest; each keyword is its own
    // field so a token cannot match across keyword boundaries.
    function appFields(app: var): var {
        const fields = [
            { "text": app.name, "weight": 3 },
            { "text": app.genericName, "weight": 1.5 },
            { "text": root.execBasename(app), "weight": 1.2 },
            { "text": app.comment, "weight": 0.8 }
        ];
        const kws = app.keywords;
        for (let i = 0; i < kws.length; i++)
            fields.push({ "text": kws[i], "weight": 1 });
        return fields;
    }

    // Frecency value: launch count decayed by the age of the last launch, so
    // "most used first" still reacts to something launched once this morning
    // versus fifty times last month. 0 for never launched.
    function frecencyValue(id: string): real {
        const rec = root.frecency[id];
        if (rec === undefined)
            return 0;
        const ageDays = Math.max(0, Date.now() - rec.last) / 86400000;
        return rec.count / (1 + ageDays);
    }

    function byFrecency(entries: var): var {
        const out = entries.slice();
        // Stable sort: never-launched apps keep their natural order at the tail.
        out.sort((a, b) => root.frecencyValue(b.id) - root.frecencyValue(a.id));
        return out;
    }

    function noteLaunch(entry: var): void {
        const rec = root.frecency[entry.id];
        const next = Object.assign({}, root.frecency);
        next[entry.id] = {
            "count": (rec === undefined ? 0 : rec.count) + 1,
            "last": Date.now()
        };
        root.frecency = next;
        frecencySave.running = false;
        frecencySave.json = JSON.stringify(next);
        frecencySave.running = true;
    }

    readonly property var results: {
        if (root.mode === "clipboard") {
            if (root.query === "")
                return root.clipboardLines;
            const out = [];
            const needle = root.query.toLowerCase();
            for (const line of root.clipboardLines) {
                if (line.toLowerCase().indexOf(needle) !== -1)
                    out.push(line);
            }
            return out;
        }
        if (root.query === "")
            return root.byFrecency(root.applications);
        return Fuzzy.rank(root.query, root.applications, app => root.appFields(app),
                          app => Math.min(8, root.frecencyValue(app.id)));
    }

    readonly property var visibleResults: root.results.slice(0, root.maxResults)

    function move(delta: int): void {
        const count = root.visibleResults.length;
        if (count === 0)
            return;
        root.selected = Math.max(0, Math.min(count - 1, root.selected + delta));
    }

    function activate(): void {
        if (root.visibleResults.length === 0)
            return;
        const choice = root.visibleResults[root.selected];

        if (root.mode === "clipboard") {
            root.pendingLine = choice;
            clipDecode.running = true;
            return;
        }

        root.close();
        root.noteLaunch(choice);
        choice.execute();
    }

    // ---- clipboard -----------------------------------------------------
    Process {
        id: clipList

        command: ["cliphist", "list"]
        stdout: StdioCollector {
            id: clipListOut

            waitForEnd: true
            onStreamFinished: root.clipboardLines = clipListOut.text.split("\n").filter(line => line.trim() !== "")
        }
    }

    Process {
        id: clipDecode

        // cliphist decode takes the "id<TAB>preview" line on stdin, which is why
        // the line is passed as an argv element rather than interpolated into a
        // shell string — clipboard contents must never be parsed as shell code.
        command: ["sh", "-c", "printf %s \"$1\" | cliphist decode", "sh", root.pendingLine]
        stdout: StdioCollector {
            id: clipDecodeOut

            waitForEnd: true
            onStreamFinished: {
                // Writing clipboardText puts it on the wayland clipboard; wl-copy
                // is no longer needed for this path.
                Quickshell.clipboardText = clipDecodeOut.text;
                root.close();
            }
        }
    }

    // ---- frecency -----------------------------------------------------
    // Read once at startup; the file is created empty if missing and a corrupt
    // or unparseable file degrades to "no history" instead of an error.
    Process {
        id: frecencyLoad

        command: ["sh", "-c", "mkdir -p \"$(dirname \"$1\")\" && touch \"$1\" && cat \"$1\"", "sh", Quickshell.statePath("launcher-frecency.json")]
        running: true

        stdout: StdioCollector {
            id: frecencyLoadOut

            waitForEnd: true
            onStreamFinished: {
                try {
                    const parsed = JSON.parse(frecencyLoadOut.text);
                    root.frecency = (parsed !== null && typeof parsed === "object") ? parsed : {};
                } catch (e) {
                    root.frecency = {};
                }
            }
        }
    }

    // Written on every launch. json is assigned first, then the process is
    // restarted so the command binding picks the new payload up.
    Process {
        id: frecencySave

        property string json: "{}"
        command: ["sh", "-c", "mkdir -p \"$(dirname \"$1\")\" && printf %s \"$2\" > \"$1\"", "sh", Quickshell.statePath("launcher-frecency.json"), frecencySave.json]
    }

    IpcHandler {
        target: "launcher"

        function openApps(): void {
            root.open("apps");
        }
        function openClipboard(): void {
            root.open("clipboard");
        }
        function toggleApps(): void {
            root.toggle("apps");
        }
        function close(): void {
            root.close();
        }
    }

    LazyLoader {
        active: root.showing

        PanelWindow {
            id: window

            screen: Util.focusedScreen()
            anchors.top: true
            anchors.left: true
            anchors.right: true
            anchors.bottom: true
            color: "transparent"
            // Full-screen, so it takes the whole input region while open; the
            // exclusive zone stays untouched.
            exclusiveZone: -1
            // Typing has to reach the search field, so this one *does* take
            // keyboard focus — unlike every other window in the shell.
            WlrLayershell.namespace: "quickshell-launcher"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

            Rectangle {
                anchors.fill: parent
                color: Theme.alpha("#000000", 0.35)

                MouseArea {
                    anchors.fill: parent
                    onClicked: root.close()
                }
            }

            Rectangle {
                id: card

                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                width: 720
                implicitHeight: content.implicitHeight + 28
                // The design language's card radius: 14, generous.
                radius: 14
                color: root.cardBg
                border.width: 1
                // Hairline border in translucent purple.
                border.color: Theme.alpha(Theme.purple, 0.35)

                // Clicks inside the card must not dismiss.
                MouseArea {
                    anchors.fill: parent
                }

                Column {
                    id: content

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 14
                    spacing: 10

                    RowLayout {
                        width: parent.width
                        spacing: 10

                        Text {
                            text: root.mode === "clipboard" ? "\uf0ea" : "\uf002"
                            color: Theme.purple
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                        }

                        TextInput {
                            id: search

                            Layout.fillWidth: true
                            color: Theme.fg
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                            focus: true
                            selectByMouse: true
                            clip: true

                            // The placeholder doubles as the mode indicator.
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.mode === "clipboard" ? "search clipboard history" : "search applications"
                                color: Theme.comment
                                font: search.font
                                visible: search.text === ""
                            }

                            onTextChanged: {
                                root.query = text;
                                root.selected = 0;
                            }

                            Keys.onUpPressed: root.move(-1)
                            Keys.onDownPressed: root.move(1)
                            Keys.onReturnPressed: root.activate()
                            Keys.onEnterPressed: root.activate()
                            Keys.onEscapePressed: root.close()
                        }

                        // Small pill with the active mode.
                        Rectangle {
                            radius: 8
                            color: Theme.alpha(Theme.purple, 0.15)
                            border.width: 1
                            border.color: Theme.alpha(Theme.purple, 0.35)
                            implicitWidth: modeChipLabel.implicitWidth + 18
                            implicitHeight: modeChipLabel.implicitHeight + 8

                            Text {
                                id: modeChipLabel

                                anchors.centerIn: parent
                                text: root.mode === "clipboard" ? "clipboard" : "apps"
                                color: Theme.purple
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSmall
                            }
                        }
                    }

                    // The one gradient flourish on this surface: purple →
                    // pink → cyan hairline under the search row.
                    Rectangle {
                        width: parent.width
                        height: 2
                        radius: 1

                        gradient: Gradient {
                            orientation: Gradient.Horizontal

                            GradientStop {
                                position: 0.0
                                color: Theme.purple
                            }
                            GradientStop {
                                position: 0.5
                                color: Theme.pink
                            }
                            GradientStop {
                                position: 1.0
                                color: Theme.cyan
                            }
                        }
                    }

                    ListView {
                        id: list

                        width: parent.width
                        // Fixed height so the wheel scrolls the list instead of the
                        // card growing to fit hundreds of clipboard entries.
                        height: Math.min(contentHeight, root.visibleRows * root.rowHeight)
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        model: root.visibleResults

                        // Keyboard navigation has to drag the view along, or the
                        // selection walks off the bottom.
                        onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
                        currentIndex: root.selected

                        delegate: Rectangle {
                            id: row

                            required property var modelData
                            required property int index

                            readonly property bool current: index === root.selected

                            width: list.width
                            height: root.rowHeight
                            radius: 8
                            color: row.current ? Theme.alpha(Theme.selection, 0.55)
                                              : (rowMouse.containsMouse ? Theme.alpha(Theme.selection, 0.25) : "transparent")
                            Behavior on color {
                                ColorAnimation {
                                    duration: Theme.animationFast
                                }
                            }

                            // Selection marker: 3px purple left bar; the row
                            // content indents slightly around it.
                            Rectangle {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                width: 3
                                height: row.height - 12
                                radius: 2
                                color: Theme.purple
                                visible: row.current
                            }

                            Image {
                                id: icon

                                anchors.left: parent.left
                                anchors.leftMargin: row.current ? 14 : 10
                                anchors.verticalCenter: parent.verticalCenter
                                width: 22
                                height: 22
                                sourceSize.width: 22
                                sourceSize.height: 22
                                visible: root.mode === "apps" && row.modelData.icon !== ""
                                source: root.mode === "apps" && row.modelData.icon !== "" ? Quickshell.iconPath(row.modelData.icon, true) : ""
                                fillMode: Image.PreserveAspectFit
                            }

                            Text {
                                id: label

                                anchors.left: icon.visible ? icon.right : parent.left
                                anchors.leftMargin: icon.visible ? 10 : (row.current ? 14 : 10)
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.right: detail.left
                                anchors.rightMargin: 10
                                text: root.mode === "clipboard" ? row.modelData : row.modelData.name
                                elide: Text.ElideRight
                                // The selection reads brighter than the rest.
                                color: row.current ? Theme.fg : Theme.alpha(Theme.fg, 0.85)
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSmall
                            }

                            Text {
                                id: detail

                                anchors.right: parent.right
                                anchors.rightMargin: 12
                                anchors.verticalCenter: parent.verticalCenter
                                width: 200
                                horizontalAlignment: Text.AlignRight
                                text: root.mode === "apps" ? row.modelData.genericName : ""
                                elide: Text.ElideRight
                                // Detail column stays dimmed, the name reads first.
                                color: Theme.alpha(Theme.comment, 0.8)
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSmall
                            }

                            MouseArea {
                                id: rowMouse

                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onEntered: root.selected = row.index
                                onClicked: {
                                    root.selected = row.index;
                                    root.activate();
                                }
                            }
                        }
                    }

                    RowLayout {
                        width: parent.width

                        Text {
                            text: root.visibleResults.length === 0
                                ? "nothing matches"
                                : root.results.length + (root.mode === "clipboard" ? " entries" : " apps")
                            color: Theme.comment
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSmall
                        }

                        Item {
                            Layout.fillWidth: true
                        }

                        Text {
                            text: "↵ run   ↑↓ move   esc close"
                            color: Theme.comment
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSmall
                        }
                    }
                }
            }
        }
    }
}
