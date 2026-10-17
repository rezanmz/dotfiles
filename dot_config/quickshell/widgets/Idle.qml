import QtQuick
import qs
import Quickshell

// Idle readout.
//
// Left click opens the panel (which is where the choices live); middle click is
// the quick indefinite toggle the widget used to be.
//
// While a timed hold runs, the widget shows the time left rather than a word, so
// the countdown is visible without opening anything.
BarItem {
    id: root

    panel: "idle"

    onClicked: button => {
        if (button === Qt.MiddleButton)
            IdleGuard.toggle();
    }

    Text {
        text: IdleGuard.label
        color: IdleGuard.held ? Theme.green : Theme.comment
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
    }
}
