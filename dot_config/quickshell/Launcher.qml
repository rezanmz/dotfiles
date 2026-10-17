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
// Ranking is Fuzzy.js (the same shape anyrun's rink plugin had), applications come
// from DesktopEntries — Quickshell tracks .desktop files in-process, so nothing is
// re-read from disk per keystroke.
Scope {
    id: root

    property bool showing: false
    property string mode: "apps"
    property string query: ""
    property int selected: 0
    property var clipboardLines: []
    property string pendingLine: ""

    // Cap on how many matches are materialised. The list scrolls, so this is a
    // sanity bound rather than the old "8 rows and no scrolling" limit anyrun had
    // upstream (which made rows past the cap unreachable).
    readonly property int maxResults: 300
    readonly property int rowHeight: 38
    readonly property int visibleRows: 8

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
        return Fuzzy.rank(root.query, root.applications, app => app.name);
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
                // A little above centre, like anyrun's runner.
                y: parent.height * 0.22
                width: 640
                implicitHeight: content.implicitHeight + 20
                radius: Theme.panelRadius
                color: Theme.panelBg
                border.width: 1
                border.color: Theme.border

                // Clicks inside the card must not dismiss.
                MouseArea {
                    anchors.fill: parent
                }

                Column {
                    id: content

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 10
                    spacing: 8

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

                        Text {
                            text: root.results.length + (root.mode === "clipboard" ? " entries" : " apps")
                            color: Theme.comment
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSmall
                        }
                    }

                    Rectangle {
                        width: parent.width
                        height: 1
                        color: Theme.border
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
                            radius: Theme.radius
                            color: row.current ? Theme.alpha(Theme.selection, 0.9) : "transparent"

                                Image {
                                    id: icon

                                    anchors.left: parent.left
                                    anchors.leftMargin: 6
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
                                    anchors.leftMargin: 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.right: detail.left
                                    anchors.rightMargin: 10
                                    text: root.mode === "clipboard" ? row.modelData : row.modelData.name
                                    elide: Text.ElideRight
                                    color: row.current ? Theme.fg : Theme.alpha(Theme.fg, 0.9)
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeSmall
                                }

                                Text {
                                    id: detail

                                    anchors.right: parent.right
                                    anchors.rightMargin: 8
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 180
                                    horizontalAlignment: Text.AlignRight
                                    text: root.mode === "apps" ? row.modelData.genericName : ""
                                    elide: Text.ElideRight
                                    color: Theme.comment
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeSmall
                                }

                                MouseArea {
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

                    Text {
                        width: parent.width
                        text: root.visibleResults.length === 0 ? "nothing matches" : "\u21b5 run   \u2191\u2193 move   esc close"
                        color: Theme.comment
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSmall
                    }
                }
            }
        }
    }
}
