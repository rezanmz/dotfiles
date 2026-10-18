import QtQuick
import qs
import Quickshell

// Night light readout. Scroll to warm it up (down cools), which also turns it on
// if it was off — the same thing dragging the panel's warmth slider does. Right
// click toggles the filter.
//
// No panel on left click, like the brightness readout next to it: scrolling is the
// control, and a readout that opens a panel is a surprise rather than a shortcut.
//
// It stays visible when off so the gesture is discoverable rather than a
// hidden control you have to already know about.
BarItem {
    id: root

    // Right click toggles it, the way right click mutes the volume readout.
    onClicked: button => {
        if (button === Qt.RightButton)
            NightLight.enabled = !NightLight.enabled;
    }

    onScrolled: steps => NightLight.adjustWarmth(steps)

    Text {
        text: NightLight.enabled ? "\uf186 " + NightLight.temperature + "K" : "\uf186 off"
        color: NightLight.enabled ? Theme.pink : Theme.comment
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
    }
}
