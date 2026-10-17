import QtQuick
import qs
import Quickshell
import Quickshell.Services.Mpris

// Now-playing readout.
//
// Same contract as the waybar mpris module: only visible while a player exists,
// italic yellow, dimmed while paused, and the same click bindings —
//
//   left click   play/pause
//   right click  next
//   scroll       previous / next
//
// so the panel lives on the middle button instead. The track line is
// "identity  title - artist", the fields waybar showed with
// dynamic-order title artist album.
BarItem {
    id: root

    panel: "media"
    panelButton: Qt.MiddleButton

    readonly property var player: {
        const players = Mpris.players.values;
        if (players.length === 0)
            return null;
        // Prefer whatever is actually playing; fall back to the first player so
        // a paused track is still visible.
        for (let i = 0; i < players.length; i++) {
            if (players[i].isPlaying)
                return players[i];
        }
        return players[0];
    }

    readonly property bool playing: root.player !== null && root.player.isPlaying

    readonly property string dynamic: {
        if (!root.player)
            return "";
        const title = root.player.trackTitle || "";
        const artist = root.player.trackArtist || "";
        if (title && artist)
            return title + " - " + artist;
        return title || artist || root.player.trackAlbum || "";
    }

    // The module disappears entirely when nothing is playing, like before.
    implicitWidth: root.player === null ? 0 : Math.min(label.implicitWidth + Theme.modulePadding * 2, 620)

    onClicked: button => {
        if (!root.player)
            return;
        if (button === Qt.LeftButton)
            root.player.togglePlaying();
        else if (button === Qt.RightButton && root.player.canGoNext)
            root.player.next();
    }

    onScrolled: delta => {
        if (!root.player)
            return;
        if (delta > 0 && root.player.canGoPrevious)
            root.player.previous();
        else if (delta < 0 && root.player.canGoNext)
            root.player.next();
    }

    Text {
        id: label

        text: {
            if (!root.player)
                return "";
            const status = root.playing ? "\u25b6" : (root.player.playbackState === MprisPlaybackState.Paused ? "\u275a\u275a" : "\u25a0");
            return root.player.identity + " " + status + " " + Util.elide(root.dynamic, 40);
        }
        color: root.playing ? Theme.yellow : Theme.comment
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
        font.italic: true
    }
}
