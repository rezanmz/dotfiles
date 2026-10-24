import QtQuick
import qs
import Quickshell
import Quickshell.Services.Mpris

// Now-playing readout.
//
// Same contract as the waybar mpris module: italic yellow, dimmed while paused,
// and the same click bindings —
//
//   left click   play/pause
//   right click  next
//   scroll       previous / next
//
// so the panel lives on the middle button instead. The track line is
// "identity  title - artist", the fields waybar showed with
// dynamic-order title artist album.
//
// The slot itself stays when there is no player. It used to collapse to zero
// width, which shifted every readout after it leftwards whenever a player exited,
// and left nothing to click: with no widget there was no way back to the media
// panel. The idle slot is a dimmed note glyph, and any click opens the panel,
// which is where "nothing is playing" is explained.
BarItem {
    id: root

    panel: "media"
    // With no player there is no transport to control, so the left button is free
    // to open the panel; while a player exists it stays on the middle button.
    panelButton: root.player === null ? Qt.LeftButton : Qt.MiddleButton

    // Which player, and whether it is playing, come from the Player singleton so
    // the bar, the panel and the media keys cannot disagree.
    readonly property var player: Player.player
    readonly property bool playing: Player.playing

    readonly property string dynamic: {
        if (!root.player)
            return "";
        const title = root.player.trackTitle || "";
        const artist = root.player.trackArtist || "";
        if (title && artist)
            return title + " - " + artist;
        return title || artist || root.player.trackAlbum || "";
    }

    // Sized by whichever line is showing: the track while a player exists, the
    // idle glyph when none does.
    implicitWidth: root.player === null ? idle.implicitWidth + Theme.modulePadding * 2 : Math.min(label.implicitWidth + Theme.modulePadding * 2, 620)

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

    // The idle slot: a note, dimmed, so the space the module occupies reads as
    // "media, nothing playing" instead of as a gap.
    Text {
        id: idle

        visible: root.player === null
        text: "\uf001"
        color: Theme.alpha(Theme.comment, 0.55)
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
    }
}
