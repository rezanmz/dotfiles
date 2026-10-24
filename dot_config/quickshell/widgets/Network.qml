import QtQuick
import qs

// Network state: wifi signal, ethernet link, or the reason there is neither.
//
// The radio is its own state, not another flavour of "offline". A radio that is
// off can be switched back on from the panel, a radio that is on with no
// connection wants a network picked, and "no interface at all" is a third thing
// again -- three different next actions, so three different readouts. Both the
// state and its wording come from NetworkState, which the panel uses too, so the
// bar and the panel cannot disagree about what "offline" means.
//
// Throughput used to sit next to this readout as two fixed-width fields, about a
// third of the cluster for numbers that are only interesting while a transfer is
// running. It is the first row of the panel now: click here, and the rates,
// addresses and settings are all in one place.
BarItem {
    id: root

    panel: "network"

    readonly property string phase: NetworkState.phase

    // The ethernet glyph is U+F0E8 (a network tree), not the U+F6FF the
    // waybar config used: that codepoint is not in Hack Nerd Font, so it drew as
    // an empty tofu box.
    Text {
        text: NetworkState.barText(root.phase, NetworkState.signal, NetworkState.onWifi)
        color: NetworkState.phaseColor(root.phase)
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
    }
}
