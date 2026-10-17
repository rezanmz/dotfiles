import QtQuick
import qs
import Quickshell

// Volume readout.
//
// Same shape as the waybar pulseaudio module: "34% " normally, "muted " when
// muted, purple accent, and scroll to change the volume in 5% steps.
// Left click opens the mixer panel (which is where pavucontrol used to be
// launched from); right click toggles mute, as before.
BarItem {
    id: root

    panel: "audio"

    readonly property real volume: Sound.volume
    readonly property bool muted: Sound.muted

    // waybar picked from three icons by level; same three glyphs here, written
    // as escapes so the file stays ASCII.
    readonly property string icon: root.volume < 0.34 ? "\uf026" : (root.volume < 0.67 ? "\uf027" : "\uf028")

    onScrolled: delta => Sound.adjustVolume(delta > 0 ? Sound.step : -Sound.step)
    onClicked: button => {
        if (button === Qt.RightButton)
            Sound.toggleMute();
    }

    Text {
        text: root.muted ? "muted \uf026" : Math.round(root.volume * 100) + "% " + root.icon
        color: root.muted ? Theme.comment : Theme.purple
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
    }
}
