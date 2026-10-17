import QtQuick
import qs
import Quickshell
import Quickshell.Hyprland

// Focused window title.
//
// The suffix stripping that waybar did with `rewrite` rules lives in
// Util.cleanTitle, so the bar shows the page name and not the browser that is
// already obvious from context. Empty when nothing is focused, and then it takes
// no space at all.
Item {
    id: root

    readonly property var toplevel: Hyprland.activeToplevel
    readonly property string title: Util.cleanTitle(root.toplevel ? root.toplevel.title : "")

    implicitWidth: root.title === "" ? 0 : label.implicitWidth + Theme.margin * 2
    implicitHeight: Theme.barHeight

    Text {
        id: label

        anchors.centerIn: parent
        text: Util.elide(root.title, 70)
        color: Theme.comment
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
    }
}
