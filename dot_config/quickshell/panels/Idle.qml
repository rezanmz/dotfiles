import QtQuick
import qs
import Quickshell

// Idle-inhibitor panel.
//
// The widget used to be a single word that toggled something invisible: nothing
// said what it did, and "hold" had no way to end by itself. This explains the
// mechanism in one line and offers the holds people actually want — a timed hold
// for a film or a build, or an indefinite one for when you know.
//
// What it blocks is hypridle (dot_config/hypr/hypridle.conf): display off, screen
// lock, and suspend after their idle timeouts. It does not touch anything else.
Popup {
    id: root

    name: "idle"
    contentWidth: 340

    component Section: Text {
        color: Theme.comment
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSmall
        font.capitalization: Font.AllUppercase
    }

    component Choice: Item {
        id: choice

        required property string label
        required property string detail
        required property bool active
        signal chosen()

        width: parent.width
        implicitHeight: 34

        Rectangle {
            anchors.fill: parent
            radius: Theme.radius
            color: hover.hovered ? Theme.alpha(Theme.selection, 0.85) : (choice.active ? Theme.alpha(Theme.selection, 0.55) : "transparent")
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
                visible: choice.active
                color: Theme.purple
            }
        }

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            text: choice.label
            color: choice.active ? Theme.fg : Theme.fg
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
        }

        Text {
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            text: choice.detail
            color: Theme.comment
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
        }

        HoverHandler {
            id: hover
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: choice.chosen()
        }
    }

    Text {
        width: parent.width
        text: {
            if (IdleGuard.auto)
                return "held — something is playing";
            if (IdleGuard.manual)
                return "held — " + IdleGuard.label;
            return "idle timers are live";
        }
        color: IdleGuard.held ? Theme.green : Theme.comment
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSmall
    }

    Text {
        width: parent.width
        text: "holds off blank, lock and suspend"
        color: Theme.alpha(Theme.comment, 0.85)
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSmall
    }

    Choice {
        label: "Hold while media plays"
        detail: IdleGuard.playing ? "playing now" : "auto"
        active: IdleGuard.autoInhibit
        onChosen: IdleGuard.autoInhibit = !IdleGuard.autoInhibit
    }

    Section {
        text: "hold for"
    }

    Choice {
        label: "15 minutes"
        detail: ""
        active: IdleGuard.manual && !IdleGuard.indefinite && IdleGuard.minutes === 15
        onChosen: IdleGuard.holdFor(15)
    }

    Choice {
        label: "30 minutes"
        detail: ""
        active: IdleGuard.manual && !IdleGuard.indefinite && IdleGuard.minutes === 30
        onChosen: IdleGuard.holdFor(30)
    }

    Choice {
        label: "1 hour"
        detail: ""
        active: IdleGuard.manual && !IdleGuard.indefinite && IdleGuard.minutes === 60
        onChosen: IdleGuard.holdFor(60)
    }

    Choice {
        label: "2 hours"
        detail: ""
        active: IdleGuard.manual && !IdleGuard.indefinite && IdleGuard.minutes === 120
        onChosen: IdleGuard.holdFor(120)
    }

    Choice {
        label: "Until I release it"
        detail: ""
        active: IdleGuard.manual && IdleGuard.indefinite
        onChosen: IdleGuard.holdIndefinitely()
    }

    Choice {
        label: "Release now"
        detail: ""
        active: false
        onChosen: IdleGuard.release()
    }
}
