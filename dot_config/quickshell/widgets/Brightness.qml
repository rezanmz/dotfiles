import QtQuick
import qs
import Quickshell

// Brightness readout: hyprsunset's gamma ramp, which is the only brightness a
// desktop monitor without DDC can have. Scroll to change it in 5% steps, click
// for the Control Centre (where the slider lives).
//
// The colour tells you whether it is still at its native value: grey at 100%,
// purple once it has moved, so a dimmed screen is visible in the bar.
BarItem {
    id: root

    panel: "controls"

    onScrolled: delta => {
        if (delta !== 0)
            NightLight.adjustBrightness(delta > 0 ? 1 : -1);
    }

    Text {
        text: "\uf185 " + NightLight.brightness + "%"
        color: NightLight.brightness === 100 ? Theme.comment : Theme.purple
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
    }
}
