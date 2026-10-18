import QtQuick
import QtQuick.Layouts
import qs
import Quickshell
import Quickshell.Services.Notifications

// Notification centre: history, search, per-app mutes, do-not-disturb, clear.
//
// This is the `notif-history` script's job (SUPER+N), except the list is already
// in memory — the old one re-read `dunstctl history`, piped JSON through python
// and fed the result to anyrun's stdin plugin.
Popup {
    id: root

    name: "notifications"
    contentWidth: 420

    // Typing has to reach the search field, and only an xdg popup grab (what
    // grabFocus maps to) puts keyboard focus in a popup. That grab contends
    // with the HyprlandFocusGrab in shell.qml (hyprland_focus_grab_v1 clears
    // "if another focus grab or similar action is started"), so shell.qml
    // stands its grab down while this panel is open — see the note to the
    // integrator: `active: Panels.anyOpen && Panels.current !== "notifications"`.
    // Dismissal is free either way: xdg popup grabs close on outside click.
    grabFocus: true

    // The compositor dismisses the grab behind Panels' back (popup_done just
    // hides the window), so close the panel for real when that happens. The
    // `open` check keeps the normal close animation out of this path.
    onVisibleChanged: {
        if (!visible && open)
            Panels.close();
    }

    // The search query filters the history by app, summary and body.
    property string query: ""

    // Ages only need refreshing while the panel is on screen. The labels pass
    // `tick` into their bindings on purpose: a bare `age()` call would not
    // depend on it and the timer below would do nothing.
    property int tick: 0

    // Opening the centre is what marks notifications as seen.
    onOpenChanged: {
        if (open)
            Notifs.markSeen();
    }

    Timer {
        interval: 30000
        running: root.open
        repeat: true
        onTriggered: root.tick++
    }

    // The history as shown: everything when the query is empty, otherwise the
    // entries whose app, summary or body contain it (case-insensitive).
    readonly property var filtered: {
        const q = root.query.trim().toLowerCase();
        const out = [];
        for (const entry of Notifs.entries) {
            if (q === "") {
                out.push(entry);
                continue;
            }
            const notif = entry.notification;
            const fields = [
                entry.app !== undefined ? entry.app : (notif ? notif.appName : ""),
                entry.summary !== undefined ? entry.summary : (notif ? notif.summary : ""),
                entry.body !== undefined ? entry.body : (notif ? notif.body : "")
            ];
            for (const field of fields) {
                if (field.toLowerCase().includes(q)) {
                    out.push(entry);
                    break;
                }
            }
        }
        return out;
    }

    function age(entry, tick): string {
        const seconds = Math.max(0, (Date.now() - entry.time) / 1000);
        if (seconds < 60)
            return Math.round(seconds) + "s";
        if (seconds < 3600)
            return Math.round(seconds / 60) + "m";
        return Math.round(seconds / 3600) + "h";
    }

    // How much longer a timed mute still has to run. `tick` is the refresh hook
    // (see above).
    function muteLeft(mute, tick): string {
        const minutes = Math.round((mute.until - Date.now()) / 60000);
        if (minutes >= 60)
            return Math.round(minutes / 60) + "h";
        return Math.max(1, minutes) + "m";
    }

    component EntryRow: Item {
        id: row

        required property var entry

        // Null-guarded: the list is rebuilt as entries are removed, and the
        // delegates' bindings re-evaluate during teardown with `entry` already
        // gone (this produced "Cannot read property 'body' of null").
        readonly property var notif: row.entry && row.entry.notification ? row.entry.notification : null
        // From the entry's snapshot: a notification that has closed has no fields
        // left to read, and the row must still say what it said (see Notifs.add).
        readonly property string app: row.entry && row.entry.app !== undefined ? row.entry.app : (row.notif ? row.notif.appName : "")
        // An entry whose notification object is gone *and* which carries no
        // snapshot — one written by a build before fields were copied — has nothing
        // to show but its age. Say so rather than drawing a blank row, which reads
        // as an empty notification.
        readonly property bool unknown: row.entry !== undefined && row.entry !== null && row.entry.app === undefined
        readonly property string summary: row.entry && row.entry.summary !== undefined ? row.entry.summary : (row.notif ? row.notif.summary : "")
        readonly property string body: row.entry && row.entry.body !== undefined ? row.entry.body : (row.notif ? row.notif.body : "")

        width: parent.width
        implicitHeight: row.body !== "" ? 44 : 28

        Text {
            id: summary

            anchors.left: parent.left
            anchors.top: parent.top
            anchors.right: appLabel.left
            anchors.rightMargin: 10
            text: row.unknown ? "notification closed" : row.summary
            textFormat: Text.PlainText
            elide: Text.ElideRight
            maximumLineCount: 1
            color: Theme.fg
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
        }

        // Which app the mute glyph silences. Invisible keeps its slot when an
        // entry has no app name, so age and glyph never shift.
        Text {
            id: appLabel

            anchors.right: age.left
            anchors.rightMargin: 6
            anchors.top: parent.top
            text: row.app
            textFormat: Text.PlainText
            elide: Text.ElideRight
            maximumLineCount: 1
            visible: row.app !== ""
            color: Theme.comment
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
        }

        Text {
            id: age

            anchors.right: mute.left
            anchors.rightMargin: 8
            anchors.top: parent.top
            text: root.age(row.entry, root.tick)
            color: Theme.comment
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
        }

        // One click on the bell-slash = an hour of quiet from this app. Pink
        // while the app is already muted, so a row says so on its own.
        Text {
            id: mute

            anchors.right: parent.right
            anchors.top: parent.top
            text: "\uf1f6"
            visible: row.app !== ""
            color: muteMouse.containsMouse || Notifs.isMuted(row.app) ? Theme.pink : Theme.comment
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall

            MouseArea {
                id: muteMouse

                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: Notifs.muteApp(row.app, 60)
            }
        }

        Text {
            id: body

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: summary.bottom
            anchors.topMargin: 2
            text: row.body
            textFormat: Text.PlainText
            elide: Text.ElideRight
            maximumLineCount: 1
            visible: row.body !== ""
            color: Theme.comment
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: Notifs.remove(row.entry)
        }
    }

    RowLayout {
        width: parent.width
        spacing: 10

        Text {
            text: "\uf002"
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

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "search notifications"
                color: Theme.comment
                font: search.font
                visible: search.text === ""
            }

            onTextChanged: root.query = text
        }
    }

    // The launcher's purple → pink → cyan hairline under its search row.
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

    RowLayout {
        width: parent.width
        spacing: 10

        Text {
            text: Notifs.dnd ? "\uf1f6  do not disturb is ON" : "\uf0f3  notifications are on"
            color: Notifs.dnd ? Theme.pink : Theme.comment
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: Notifs.toggleDnd()
            }
        }

        Item {
            Layout.fillWidth: true
        }

        Text {
            text: "clear"
            color: Theme.comment
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            visible: Notifs.count > 0

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: Notifs.clearAll()
            }
        }
    }

    // Muted apps, with the undo. `activeMutes` only lists mutes still in force,
    // so this section empties itself when a timed mute runs out.
    Text {
        width: parent.width
        text: "muted apps"
        visible: muteRepeater.count > 0
        color: Theme.comment
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSmall
        font.capitalization: Font.AllUppercase
    }

    Repeater {
        id: muteRepeater

        model: Notifs.activeMutes

        delegate: Item {
            id: muteRow

            required property var modelData

            width: parent.width
            implicitHeight: 22

            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: muteRow.modelData.app
                textFormat: Text.PlainText
                elide: Text.ElideRight
                color: Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
            }

            Text {
                anchors.right: unmute.left
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                text: muteRow.modelData.until === 0 ? "until unmuted" : root.muteLeft(muteRow.modelData, root.tick)
                color: Theme.comment
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
            }

            Text {
                id: unmute

                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: "unmute"
                color: Theme.pink
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Notifs.unmuteApp(muteRow.modelData.app)
                }
            }
        }
    }

    Text {
        width: parent.width
        text: "nothing yet"
        visible: Notifs.count === 0
        color: Theme.comment
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSmall
    }

    Text {
        width: parent.width
        text: "no matches"
        visible: Notifs.count > 0 && root.filtered.length === 0
        color: Theme.comment
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSmall
    }

    Repeater {
        model: root.filtered

        delegate: EntryRow {
            required property var modelData

            entry: modelData
        }
    }
}
