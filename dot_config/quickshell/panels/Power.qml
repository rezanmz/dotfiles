import QtQuick
import qs
import Quickshell
import Quickshell.Wayland
import Quickshell.Io

// Power panel: the way out of the session, one click from the bar.
//
// This is the Control Centre's power section as a panel of its own — the one
// thing the centre had that clicking the other tray icons did not. The
// commands are the launcher's power-menu commands verbatim (Launcher.qml,
// powerActions — keep the two in step) so the two entry points always do the
// same thing: the session is uwsm-managed, so log out is `uwsm stop`, and the
// destructive commands carry the launcher's `||` fallbacks. They run through
// `sh -c` exactly as the launcher runs them.
//
// Lock runs at once. The four destructive rows arm first: one click turns the
// row red and names what a confirming second click runs, and the arming
// expires after four seconds or when the panel closes, so a stale "yes" can
// never fire later.
//
// Escape is the cancel key for a half-armed row, so this panel takes the
// keyboard the way the notification centre does: a popup has no keyboard focus
// of its own (see Popup.qml), and grabFocus (the xdg popup grab) is what puts
// it there. The compositor's dismissal of that grab (popup_done just hides the
// window) is synced back through Panels.close(), copied from the notification
// centre.
Popup {
    id: root

    name: "power"
    contentWidth: 340

    // This panel has something to type into (search field, password
    // prompt), so it asks for the keyboard -- but on demand, not
    // exclusive. Exclusive makes the surface the click target as well,
    // which locks out every click on the screen; on_demand hands focus
    // over when the surface is clicked, so the field works and the
    // catcher still sees clicks elsewhere.
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    // The compositor dismisses the grab behind Panels' back (popup_done just
    // hides the window), so close the panel for real when that happens. The
    // `open` check keeps the normal close animation out of this path.
    onVisibleChanged: {
        if (!visible && open)
            Panels.close();
    }

    // The card's Keys.onEscapePressed only fires when a child item holds active
    // focus, and this panel has no focusable child — so Escape is a window
    // shortcut instead, the same way the cheatsheet closes (panels/Keys.qml).
    Shortcut {
        sequence: "Escape"
        onActivated: Panels.close()
    }

    // One switchable row: label on the left, state detail on the right. A row
    // can also be *armed* — the first click on a destructive action — which
    // turns it red and spells out in the detail what a confirming second click
    // will run; the detail wraps to a second line for that.
    component ToggleRow: Item {
        id: row

        property string label: ""
        property string detail: ""
        property bool active: false
        property bool armed: false
        property color accent: Theme.purple
        property color labelColor: row.armed ? Theme.red : Theme.fg
        property color detailColor: row.armed ? Theme.red : (row.active ? Theme.green : Theme.comment)
        signal chosen()

        width: parent.width
        implicitHeight: Math.max(32, detailText.implicitHeight + 10)

        Rectangle {
            anchors.fill: parent
            radius: Theme.radius
            color: row.armed ? Theme.alpha(Theme.red, 0.25) : (hover.hovered ? Theme.hoverBg : (row.active ? Theme.alpha(Theme.selection, 0.55) : "transparent"))
            Behavior on color {
                ColorAnimation {
                    duration: Theme.animationFast
                }
            }

            // The active choice carries the same left bar the launcher's
            // selection uses, so "this is the one" reads the same everywhere;
            // an armed row borrows it in red.
            Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.margins: 6
                width: 3
                radius: 2
                visible: row.active || row.armed
                color: row.armed ? Theme.red : row.accent
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

    // The power menu's commands, kept verbatim from the launcher's power menu
    // (Launcher.qml, powerActions) so the two stay in step: the session is
    // uwsm-managed, so log out is `uwsm stop`, and the destructive commands
    // carry the launcher's `||` fallbacks. They run through `sh -c` exactly as
    // the launcher runs them.
    Process {
        id: powerRun
    }

    // Destructive rows arm first: the first click names the row here and turns
    // it red, a second click within four seconds runs its command. The arming
    // expires on its own and is dropped whenever the panel closes, so a stale
    // "yes" can never fire later. Lock is not destructive and runs at once.
    property string armed: ""

    onOpenChanged: {
        if (!root.open) {
            root.armed = "";
            armTimer.stop();
        }
    }

    Timer {
        id: armTimer

        interval: 4000
        onTriggered: root.armed = ""
    }

    function armOrRun(key: string, command: string): void {
        if (root.armed !== key) {
            root.armed = key;
            armTimer.restart();
            return;
        }
        root.armed = "";
        armTimer.stop();
        powerRun.command = ["sh", "-c", command];
        powerRun.running = true;
    }

    ToggleRow {
        label: "Lock now"
        detail: "lock the session screen"
        onChosen: {
            root.armed = "";
            powerRun.command = ["sh", "-c", "loginctl lock-session"];
            powerRun.running = true;
        }
    }

    ToggleRow {
        label: "Log out"
        detail: root.armed === "logout" ? "ends the session — click again to confirm" : "end the session"
        armed: root.armed === "logout"
        onChosen: root.armOrRun("logout", "uwsm stop")
    }

    ToggleRow {
        label: "Suspend"
        detail: root.armed === "suspend" ? "suspends, then hibernates after 45 min — click again to confirm" : "suspend, then hibernate after 45 min"
        armed: root.armed === "suspend"
        onChosen: root.armOrRun("suspend", "systemctl suspend-then-hibernate")
    }

    ToggleRow {
        label: "Hibernate"
        detail: root.armed === "hibernate" ? "writes memory to disk and powers off — click again to confirm" : "write memory to disk and power off"
        armed: root.armed === "hibernate"
        onChosen: root.armOrRun("hibernate", "systemctl hibernate")
    }

    ToggleRow {
        label: "Restart"
        detail: root.armed === "restart" ? "restarts the system — click again to confirm" : "restart the system"
        armed: root.armed === "restart"
        onChosen: root.armOrRun("restart", "systemctl reboot || reboot")
    }

    ToggleRow {
        label: "Shut down"
        detail: root.armed === "shutdown" ? "shuts the system down — click again to confirm" : "shut the system down"
        armed: root.armed === "shutdown"
        onChosen: root.armOrRun("shutdown", "systemctl poweroff || poweroff")
    }

    // Only while a recording is running; hidden rows leave the column entirely.
    ToggleRow {
        label: "Stop recording"
        detail: "wf-recorder"
        active: true
        accent: Theme.red
        labelColor: Theme.red
        detailColor: Theme.red
        visible: Recorder.recording
        onChosen: Recorder.stop()
    }
}
