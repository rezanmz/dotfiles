import QtQuick
import QtQuick.Layouts
import qs
import Quickshell.Services.Mpris

// Now-playing panel: artwork, transport, seek, and the player's own volume.
//
// The bar readout is one line; this is everything else the waybar mpris module
// could not show — artwork, a seek bar, shuffle/loop, and volume. It is also why
// the media widget moved its panel to the middle button: left click keeps the old
// play/pause behaviour.
Popup {
    id: root

    name: "media"
    contentWidth: 380

    readonly property var player: {
        const players = Mpris.players.values;
        if (players.length === 0)
            return null;
        for (let i = 0; i < players.length; i++) {
            if (players[i].isPlaying)
                return players[i];
        }
        return players[0];
    }

    component IconButton: Text {
        id: button

        property bool active: false
        signal invoked()

        color: !button.enabled ? Theme.comment : (active ? Theme.purple : Theme.fg)
        font.family: Theme.fontFamily
        font.pixelSize: 18
        opacity: hover.hovered ? 1 : 0.85

        HoverHandler {
            id: hover
        }

        MouseArea {
            anchors.fill: parent
            enabled: button.enabled
            cursorShape: Qt.PointingHandCursor
            onClicked: button.invoked()
        }
    }

    Text {
        width: parent.width
        visible: root.player === null
        text: "nothing is playing"
        color: Theme.comment
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSmall
    }

    RowLayout {
        width: parent.width
        spacing: 12
        visible: root.player !== null

        Rectangle {
            Layout.preferredWidth: 96
            Layout.preferredHeight: 96
            radius: Theme.radius
            color: Theme.alpha(Theme.comment, 0.25)

            Image {
                anchors.fill: parent
                anchors.margins: 1
                visible: root.player !== null && root.player.trackArtUrl !== ""
                source: root.player !== null ? root.player.trackArtUrl : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                sourceSize.width: 96
                sourceSize.height: 96
            }

            Text {
                anchors.centerIn: parent
                visible: root.player === null || root.player.trackArtUrl === ""
                text: "\uf001"
                color: Theme.comment
                font.family: Theme.fontFamily
                font.pixelSize: 28
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            Text {
                Layout.fillWidth: true
                text: root.player ? (root.player.trackTitle || "unknown title") : ""
                elide: Text.ElideRight
                color: Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
            }

            Text {
                Layout.fillWidth: true
                text: root.player ? (root.player.trackArtist || "") : ""
                elide: Text.ElideRight
                visible: text !== ""
                color: Theme.comment
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
            }

            Text {
                Layout.fillWidth: true
                text: root.player ? (root.player.trackAlbum || "") : ""
                elide: Text.ElideRight
                visible: text !== ""
                color: Theme.comment
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
            }

            Text {
                Layout.fillWidth: true
                text: root.player ? root.player.identity : ""
                elide: Text.ElideRight
                color: Theme.alpha(Theme.comment, 0.8)
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
            }
        }
    }

    RowLayout {
        width: parent.width
        spacing: 10
        visible: root.player !== null && root.player.lengthSupported

        Text {
            text: Util.duration(root.player ? root.player.position : 0)
            color: Theme.comment
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
        }

        Item {
            Layout.fillWidth: true
            implicitHeight: 16

            Rectangle {
                id: seekTrack

                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                height: 4
                radius: 2
                color: Theme.alpha(Theme.comment, 0.45)
            }

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: seekTrack.width * (root.player && root.player.length > 0 ? Math.min(1, root.player.position / root.player.length) : 0)
                height: 4
                radius: 2
                color: Theme.purple
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                // position is writable, so the click seeks directly; no need for
                // seek()'s relative offsets.
                onPressed: mouse => {
                    if (root.player && root.player.length > 0)
                        root.player.position = (mouse.x / width) * root.player.length;
                }
            }
        }

        Text {
            text: Util.duration(root.player ? root.player.length : 0)
            color: Theme.comment
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
        }
    }

    RowLayout {
        width: parent.width
        spacing: 18
        visible: root.player !== null

        Item {
            Layout.fillWidth: true
        }

        IconButton {
            text: "\uf048"
            enabled: root.player !== null && root.player.canGoPrevious
            onInvoked: root.player.previous()
        }

        IconButton {
            text: root.player && root.player.isPlaying ? "\uf04c" : "\uf04b"
            enabled: root.player !== null && root.player.canTogglePlaying
            onInvoked: root.player.togglePlaying()
        }

        IconButton {
            text: "\uf051"
            enabled: root.player !== null && root.player.canGoNext
            onInvoked: root.player.next()
        }

        IconButton {
            text: "\uf074"
            enabled: root.player !== null && root.player.shuffleSupported
            active: root.player !== null && root.player.shuffle
            onInvoked: root.player.shuffle = !root.player.shuffle
        }

        IconButton {
            text: "\uf01e"
            enabled: root.player !== null && root.player.loopSupported
            active: root.player !== null && root.player.loopState !== MprisLoopState.None
            onInvoked: {
                // None -> Track -> Playlist -> None, which is what the player's own
                // loop button does.
                if (root.player.loopState === MprisLoopState.None)
                    root.player.loopState = MprisLoopState.Track;
                else if (root.player.loopState === MprisLoopState.Track)
                    root.player.loopState = MprisLoopState.Playlist;
                else
                    root.player.loopState = MprisLoopState.None;
            }
        }

        Item {
            Layout.fillWidth: true
        }
    }

    RowLayout {
        width: parent.width
        spacing: 10
        visible: root.player !== null && root.player.volumeSupported

        Text {
            text: "\uf028"
            color: Theme.comment
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
        }

        Rectangle {
            id: volumeTrack

            Layout.fillWidth: true
            Layout.preferredHeight: 4
            radius: 2
            color: Theme.alpha(Theme.comment, 0.45)

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: volumeTrack.width * (root.player ? Math.max(0, Math.min(1, root.player.volume)) : 0)
                height: 4
                radius: 2
                color: Theme.yellow
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onPressed: mouse => {
                    if (root.player)
                        root.player.volume = Math.max(0, Math.min(1, mouse.x / width));
                }
                onPositionChanged: mouse => {
                    if (pressed && root.player)
                        root.player.volume = Math.max(0, Math.min(1, mouse.x / width));
                }
            }
        }

        Text {
            Layout.preferredWidth: 40
            horizontalAlignment: Text.AlignRight
            text: root.player ? Math.round(root.player.volume * 100) + "%" : ""
            color: Theme.comment
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
        }
    }
}
