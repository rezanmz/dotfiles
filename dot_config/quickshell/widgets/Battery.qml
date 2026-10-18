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

    // Collapse the whole item when nothing reports a battery. Hiding it is not
    // enough: an invisible item is not laid out in the bar's RowLayout, and
    // flipping `visible` afterwards does not reliably re-run the layout, so the
    // readout would stay missing until something else changed the bar. Sizing from
    // the label (not from the content area) keeps this out of the binding-loop
    // territory BarItem warns about.
    implicitWidth: root.lowest ? label.implicitWidth + Theme.modulePadding * 2 : 0

    // A mouse reads as a mouse, a keyboard as a keyboard. Anything generic
    // (laptop battery, receiver) falls back to the battery glyph series, which
    // tracks the level. Colour follows the level the other way round -- red is
    // low -- through Batteries.colorFor.
    //
    // Glyphs are built from codepoints, not typed: these are the Hack Nerd
    // Font points verified by rendering (mouse F037D, keyboard F11C, headset
    // F02CE, battery empty->full F240..F244). fromCodePoint, not fromCharCode:
    // the font points sit above the BMP and fromCharCode truncates to 16 bits.
    function glyph(kind: string, percent: int): string {
        if (kind === "mouse")
            return String.fromCodePoint(0xF037D);
        if (kind === "keyboard")
            return String.fromCodePoint(0xF11C);
        if (kind === "headset")
            return String.fromCodePoint(0xF02CE);
        if (percent >= 80)
            return String.fromCodePoint(0xF244);
        if (percent >= 60)
            return String.fromCodePoint(0xF243);
        if (percent >= 40)
            return String.fromCodePoint(0xF242);
        if (percent >= 20)
            return String.fromCodePoint(0xF241);
        return String.fromCodePoint(0xF240);
    }

    Text {
        id: label

        text: root.lowest ? root.glyph(root.lowest.kind, root.lowest.percent) + " " + root.lowest.percent + "%" : ""
        color: root.lowest ? Batteries.colorFor(root.lowest.percent) : Theme.fg
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
    }
}
