import QtQuick
import qs
import Quickshell

// The device closest to dying.
//
// One readout -- the lowest battery of anything that reports one (mouse,
// keyboard, receiver) -- because the useful question is which device is about
// to go silent mid-sentence, not the average. Only exists while something
// reports: in the bar's RowLayout an invisible item is not laid out at all
// (see Rec.qml), so a machine with no battery devices has no widget at all,
// not an empty gap.
BarItem {
    id: root

    panel: "battery"

    readonly property var lowest: Batteries.lowest

    // True when the device this readout is about is on its charger. The
    // kernel is the only source for that (see Charging.qml): BlueZ and
    // Quickshell both have no charging flag, so it comes from the HID++
    // power supply node.
    readonly property bool charging: root.lowest ? Charging.isCharging(root.lowest.address) : false

    // Collapse the whole item when nothing reports a battery. Hiding it is not
    // enough: an invisible item is not laid out in the bar's RowLayout, and
    // flipping `visible` afterwards does not reliably re-run the layout, so the
    // readout would stay missing until something else changed the bar. Sizing from
    // the label (not from the content area) keeps this out of the binding-loop
    // territory BarItem warns about.
    //
    // The bolt's width is added only while it is showing: childrenRect counts
    // invisible children, so the content area is always as wide as label plus
    // bolt, and the item would keep a gap for a bolt that is not there.
    implicitWidth: root.lowest ? label.implicitWidth + (root.charging ? bolt.width + 3 : 0) + Theme.modulePadding * 2 : 0

    // A mouse reads as a mouse, a keyboard as a keyboard. Anything generic
    // (laptop battery, receiver) falls back to the battery glyph series, which
    // tracks the level. Colour follows the level the other way round -- red is
    // low -- through Batteries.colorFor.
    //
    // Glyphs are built from codepoints, not typed: these are the Hack Nerd
    // Font points verified by rendering (mouse F037D, keyboard F11C, headset
    // F02CE, battery empty->full F240..F244). fromCodePoint, not fromCharCode:
    // the font points sit above the BMP and fromCharCode truncates to 16 bits.
    //
    // The battery series runs F244 (empty) to F240 (full) -- the glyphs were
    // checked by rendering them and measuring the fill, because the codepoint
    // order is the opposite of the level order and picking by number alone
    // gets it backwards: a full battery would draw as an empty one.
    function glyph(kind: string, percent: int): string {
        if (kind === "mouse")
            return String.fromCodePoint(0xF037D);
        if (kind === "keyboard")
            return String.fromCodePoint(0xF11C);
        if (kind === "headset")
            return String.fromCodePoint(0xF02CE);
        if (percent >= 80)
            return String.fromCodePoint(0xF240);
        if (percent >= 60)
            return String.fromCodePoint(0xF241);
        if (percent >= 40)
            return String.fromCodePoint(0xF242);
        if (percent >= 20)
            return String.fromCodePoint(0xF243);
        return String.fromCodePoint(0xF244);
    }

    // The bolt for a device on its charger. Its own element, and its own
    // colour, so the mark stands out from the level next to it.
    Text {
        id: bolt

        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        visible: root.charging
        text: Charging.glyph
        color: Theme.green
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
    }

    Text {
        id: label

        anchors.left: bolt.visible ? bolt.right : parent.left
        anchors.leftMargin: bolt.visible ? 3 : 0
        anchors.verticalCenter: parent.verticalCenter
        text: root.lowest ? root.glyph(root.lowest.kind, root.lowest.percent) + " " + root.lowest.percent + "%" : ""
        color: root.lowest ? Batteries.colorFor(root.lowest.percent) : Theme.fg
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
    }
}
