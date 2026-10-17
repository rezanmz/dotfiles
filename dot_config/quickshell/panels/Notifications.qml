import QtQuick
import QtQuick.Layouts
import qs
import Quickshell
import Quickshell.Services.Notifications

// Notification centre: history, do-not-disturb, clear.
//
// This is the `notif-history` script's job (SUPER+N), except the list is already
// in memory — the old one re-read `dunstctl history`, piped JSON through python
// and fed the result to anyrun's stdin plugin.
Popup {
    id: root

    name: "notifications"
    contentWidth: 420

    // Ages only need refreshing while the panel is on screen.
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

    function age(entry): string {
        const seconds = Math.max(0, (Date.now() - entry.time) / 1000);
        if (seconds < 60)
            return Math.round(seconds) + "s";
        if (seconds < 3600)
            return Math.round(seconds / 60) + "m";
        return Math.round(seconds / 3600) + "h";
    }

    component EntryRow: Item {
        id: row

        required property var entry

        readonly property var notif: entry.notification

        width: parent.width
        implicitHeight: body.visible ? 44 : 28

        Text {
            id: summary

            anchors.left: parent.left
            anchors.top: parent.top
            anchors.right: age.left
            anchors.rightMargin: 10
            text: row.notif.summary
            textFormat: Text.PlainText
            elide: Text.ElideRight
            maximumLineCount: 1
            color: Theme.fg
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
        }

        Text {
            id: age

            anchors.right: parent.right
            anchors.top: parent.top
            text: root.age(row.entry)
            color: Theme.comment
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
        }

        Text {
            id: body

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: summary.bottom
            anchors.topMargin: 2
            text: row.notif.body
            textFormat: Text.PlainText
            elide: Text.ElideRight
            maximumLineCount: 1
            visible: row.notif.body !== ""
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

    Text {
        width: parent.width
        text: "nothing yet"
        visible: Notifs.count === 0
        color: Theme.comment
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSmall
    }

    Repeater {
        model: Notifs.entries

        delegate: EntryRow {
            required property var modelData

            entry: modelData
        }
    }
}
