import QtQuick
import qs
import Quickshell

// Notification bell: how much is waiting, and the way into the notification
// centre.
//
// The old bar had no notification indicator at all — dunst popped up and that was
// it, with history only reachable through a script bound to SUPER+N. This is the
// widget that makes the history (and do-not-disturb) visible.
BarItem {
    id: root

    panel: "notifications"

    readonly property int unseen: Notifs.unseen

    // The whole history, not just what has not been read. Showing only the unseen
    // count meant the bell went blank the moment you looked at the centre — with
    // entries still sitting there — which reads as "there is nothing here".
    readonly property int total: Notifs.count

    onClicked: button => {
        if (button === Qt.MiddleButton)
            Notifs.toggleDnd();
    }

    Text {
        text: Notifs.dnd ? "\uf1f6" : (root.total > 0 ? "\uf0f3 " + root.total : "\uf0f3")
        // Pink while something is unread, normal while the history is only old
        // news, muted when there is nothing at all.
        color: Notifs.dnd ? Theme.comment : (root.unseen > 0 ? Theme.pink : (root.total > 0 ? Theme.fg : Theme.comment))
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
    }
}
