import QtQuick
import qs
import Quickshell

// Night light readout. Scroll to warm it up (down cools), which also turns it on
// if it was off — the same thing dragging the panel's warmth slider does. Click
// for the Control Centre.
//
// It stays visible when off so the gesture is discoverable rather than a
// hidden control you have to already know about.
BarItem {
    id: root

    panel: "controls"

    // Right click toggles it, the way right click mutes the volume readout.
    onClicked: button => {
        if (button === Qt.RightButton)
            NightLight.enabled = !NightLight.enabled;
    }

    onScrolled: delta => {
        NightLight.temperature = Math.max(2500, Math.min(6500, NightLight.temperature + (delta > 0 ? -250 : 250)));
        NightLight.enabled = true;
    }

    Text {
        text: NightLight.enabled ? "\uf186 " + NightLight.temperature + "K" : "\uf186 off"
        color: NightLight.enabled ? Theme.pink : Theme.comment
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
    }
}
