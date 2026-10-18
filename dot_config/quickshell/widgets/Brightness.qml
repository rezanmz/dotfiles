import QtQuick
import qs
import Quickshell

// Brightness readout: hyprsunset's gamma ramp, which is the only brightness a
// desktop monitor without DDC can have. Scroll to change it in 5% steps.
//
// No panel on click. It used to open the Control Centre, which made a readout you
// merely meant to look at throw a full panel over the screen — and since the
// brightness, warmth and control-centre widgets all claimed that one panel, the
// panel could anchor under a different readout than the one clicked. Right click
// resets to 100%. There is no panel for this by design: scrolling is the control.
//
// The colour tells you whether it is still at its native value: grey at 100%,
// purple once it has moved, so a dimmed screen is visible in the bar.
BarItem {
    id: root

    onScrolled: steps => NightLight.adjustBrightness(steps)

    // Right click: back to the panel's native output.
    onClicked: button => {
        if (button === Qt.RightButton)
            NightLight.brightness = 100;
    }

    Text {
        text: "\uf185 " + NightLight.brightness + "%"
        color: NightLight.brightness === 100 ? Theme.comment : Theme.purple
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
    }
}
