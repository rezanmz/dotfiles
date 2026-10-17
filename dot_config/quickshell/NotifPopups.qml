import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Notifications
import qs

// Notification popups.
//
// dunst's job, in the shell: the top-right stack, under the bar, with the same
// Dracula treatment dunstrc used (bg #282a36, a 2px frame coloured by urgency,
// 6px corners, a progress bar for the remaining time). What is new is that the
// body can carry action buttons — dunst only offered actions through a middle
// click, with no way to see that they existed.
//
// The window never reserves space (exclusiveZone: -1) and sits on the overlay
// layer: a notification must not push windows around, and must be visible over
// whatever is on screen. shell.qml creates it only while something is popping up.
//
// Every read of the notification is null-guarded: the window is destroyed as the
// stack empties, and the delegates' bindings re-evaluate during teardown, when
// `entry` is already null.
PanelWindow {
    id: root

    readonly property int maxVisible: 4

    screen: Util.focusedScreen()
    anchors.top: true
    anchors.right: true
    margins.top: Theme.barHeight + Theme.margin
    margins.right: Theme.margin
    implicitWidth: 380
    implicitHeight: Math.min(column.implicitHeight, 720)
    color: "transparent"
    exclusiveZone: -1
    WlrLayershell.namespace: "quickshell-notifications"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    component Card: Rectangle {
        id: card

        required property var entry

        readonly property var notif: card.entry && card.entry.notification ? card.entry.notification : null

        // expireTimeout is the sender's request in milliseconds (-1 when the
        // sender leaves it to the server). The fallbacks are dunstrc's:
        // low 5s, normal 8s, critical sticky.
        readonly property int lifetime: {
            if (!card.notif)
                return 0;
            if (card.notif.expireTimeout > 0)
                return card.notif.expireTimeout;
            if (card.notif.urgency === NotificationUrgency.Critical)
                return 0;
            return card.notif.urgency === NotificationUrgency.Low ? 5000 : 8000;
        }

        readonly property color frame: {
            if (!card.notif || card.notif.urgency === NotificationUrgency.Critical)
                return Theme.red;
            return card.notif.urgency === NotificationUrgency.Low ? Theme.comment : Theme.purple;
        }

        readonly property string summary: card.notif ? card.notif.summary : ""
        readonly property string body: card.notif ? card.notif.body : ""
        readonly property string image: card.notif ? card.notif.image : ""
        readonly property string appIcon: card.notif ? card.notif.appIcon : ""
        readonly property var actions: card.notif ? card.notif.actions : []

        // Hovering holds a notification open: it is about to be read, not missed.
        readonly property bool held: hover.hovered

        width: column.width
        implicitHeight: content.implicitHeight + 20
        color: Theme.bg
        radius: Theme.radius
        border.width: 2
        border.color: card.frame

        // Slides in from the right edge it lives on.
        transform: Translate {
            id: slide

            x: 40

            Component.onCompleted: slide.x = 0

            Behavior on x {
                NumberAnimation {
                    duration: Theme.animationNormal
                    easing.type: Easing.OutCubic
                }
            }
        }

        // Urgency edge: the card's whole state in one glance, without reading
        // the border colour off a rounded corner.
        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.margins: 4
            width: 3
            radius: 2
            color: card.frame
        }

        HoverHandler {
            id: hover
        }

        Timer {
            interval: card.lifetime
            running: card.lifetime > 0 && !card.held && card.notif !== null
            onTriggered: card.notif.expire()
        }

        Column {
            id: content

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 10
            spacing: 4

            Row {
                width: parent.width
                spacing: 8

                // Sender icon: either a file/URL in `image`, or a themed name in
                // `appIcon` (which is what most applications send).
                Image {
                    width: 22
                    height: 22
                    sourceSize.width: 22
                    sourceSize.height: 22
                    visible: card.image !== ""
                    source: card.image
                    fillMode: Image.PreserveAspectFit
                }

                Image {
                    width: 22
                    height: 22
                    sourceSize.width: 22
                    sourceSize.height: 22
                    visible: card.image === "" && card.appIcon !== ""
                    source: card.image === "" && card.appIcon !== "" ? Quickshell.iconPath(card.appIcon, true) : ""
                    fillMode: Image.PreserveAspectFit
                }

                Text {
                    width: parent.width - 22 - closeButton.width - 16
                    text: card.summary
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    color: Theme.fg
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                    font.bold: true
                }

                Text {
                    id: closeButton

                    text: "\uf00d"
                    color: hover.hovered ? Theme.fg : Theme.comment
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (card.notif)
                                card.notif.dismiss();
                        }
                    }
                }
            }

            Text {
                width: parent.width
                text: card.body
                // PlainText: bodyMarkupSupported is off, so a body that happens
                // to contain markup must render literally.
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                maximumLineCount: 6
                elide: Text.ElideRight
                visible: card.body !== ""
                color: Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
            }

            Row {
                spacing: 8
                visible: card.actions.length > 0

                Repeater {
                    model: card.actions

                    delegate: Rectangle {
                        required property var modelData

                        implicitWidth: actionLabel.implicitWidth + 16
                        implicitHeight: 22
                        radius: Theme.radius
                        color: actionHover.hovered ? Theme.selection : "transparent"
                        border.width: 1
                        border.color: Theme.borderStrong

                        Text {
                            id: actionLabel

                            anchors.centerIn: parent
                            text: modelData.text
                            color: Theme.fg
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSmall
                        }

                        HoverHandler {
                            id: actionHover
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: modelData.invoke()
                        }
                    }
                }
            }

            // Remaining-time bar, like dunstrc's progress_bar.
            Rectangle {
                width: parent.width
                height: 3
                radius: 1.5
                color: Theme.alpha(card.frame, 0.25)
                visible: card.lifetime > 0

                Rectangle {
                    id: progress

                    anchors.left: parent.left
                    height: parent.height
                    radius: parent.radius
                    color: card.frame
                    width: parent.width

                    NumberAnimation on width {
                        from: progress.parent.width
                        to: 0
                        duration: card.lifetime
                        running: card.lifetime > 0 && !card.held
                    }
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
            z: -1

            onClicked: mouse => {
                if (!card.notif)
                    return;
                if (mouse.button === Qt.RightButton)
                    Notifs.clearPopups();
                else if (mouse.button === Qt.MiddleButton && card.actions.length > 0)
                    card.actions[0].invoke();
                else
                    card.notif.dismiss();
            }
        }
    }

    Column {
        id: column

        anchors.right: parent.right
        anchors.top: parent.top
        width: parent.width
        spacing: 6

        Repeater {
            model: Notifs.popups.slice(0, root.maxVisible)

            delegate: Card {
                required property var modelData

                entry: modelData
            }
        }
    }
}
