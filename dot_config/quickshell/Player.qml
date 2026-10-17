pragma Singleton

// The media player the shell is following, and the transport actions for it.
//
// The bar widget, the media panel and the media keys all need the same answer to
// "which player", and all three had their own copy of the selection logic. It
// lives here now.
//
// This also removes the shell's last dependency on `playerctl`: the media keys
// used to call it, and playerctl was removed as a dependency of waybar when the
// waybar package went, which silently broke those keys. They call this instead
// (`qs ipc call media next`), so the shell controls playback through MPRIS
// directly.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris

Singleton {
    id: root

    // Whatever is actually playing wins; a paused player is still worth showing,
    // so the first player is the fallback.
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

    readonly property bool playing: root.player !== null && root.player.isPlaying
    readonly property string identity: root.player ? root.player.identity : ""
    readonly property string title: root.player ? root.player.trackTitle : ""
    readonly property string artist: root.player ? root.player.trackArtist : ""
    readonly property string album: root.player ? root.player.trackAlbum : ""
    readonly property string artUrl: root.player ? root.player.trackArtUrl : ""
    readonly property real position: root.player ? root.player.position : 0
    readonly property real length: root.player ? root.player.length : 0

    function toggle(): void {
        if (root.player && root.player.canTogglePlaying)
            root.player.togglePlaying();
    }

    function next(): void {
        if (root.player && root.player.canGoNext)
            root.player.next();
    }

    function previous(): void {
        if (root.player && root.player.canGoPrevious)
            root.player.previous();
    }

    IpcHandler {
        target: "player"

        function toggle(): void {
            root.toggle();
        }
        function next(): void {
            root.next();
        }
        function previous(): void {
            root.previous();
        }
    }
}
