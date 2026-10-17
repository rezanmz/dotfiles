import QtQuick
import qs
import Quickshell

// Notification bell: unread count, and the way into the notification centre.
//
// The old bar had no notification indicator at all — dunst popped up and that was
// it, with history only reachable through a script bound to SUPER+N. This is the
// widget that makes the history (and do-not-disturb) visible.
BarItem {
    id: root

    panel: "notifications"

    readonly property int unseen: Notifs.unseen

    onClicked: button => {
        if (button === Qt.MiddleButton)
            Notifs.toggleDnd();
    }

    Text {
        text: Notifs.dnd ? "\uf1f6" : (root.unseen > 0 ? "\uf0f3 " + root.unseen : "\uf0f3")
        color: Notifs.dnd || root.unseen === 0 ? Theme.comment : Theme.pink
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
    }
}
