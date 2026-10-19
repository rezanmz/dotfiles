import QtQuick
import qs
import Quickshell.Networking

// Network state: wifi signal, ethernet link, or offline.
//
// The device comes from Stats, which already resolves the connected device from
// NetworkManager (and uses the same one for the throughput counters), so there is
// one definition of "the active interface" in the shell. The network panel (the
// `nmtui` replacement) is opened by the group in Bar.qml, not by this readout.
Item {
    id: root

    implicitWidth: label.implicitWidth + Theme.modulePadding
    implicitHeight: Theme.barHeight
    width: implicitWidth
    height: implicitHeight

    readonly property var device: Stats.activeDevice
    readonly property bool wifi: root.device !== null && root.device.type === DeviceType.Wifi

    // The connected network is the entry in the device's scan list that is
    // itself connected. Note signalStrength is a 0.0-1.0 fraction, not a
    // percentage (waybar's {signalStrength} was already 0-100).
    readonly property var connectedNetwork: {
        if (!root.wifi || !root.device || !root.device.networks)
            return null;
        const networks = root.device.networks.values;
        for (let i = 0; i < networks.length; i++) {
            if (networks[i].connected)
                return networks[i];
        }
        return null;
    }

    readonly property int signal: root.connectedNetwork ? Math.round(root.connectedNetwork.signalStrength * 100) : 0

    readonly property bool online: root.device !== null && root.device.connected

    Text {
        id: label

        anchors.centerIn: parent
        // The ethernet glyph is U+F0E8 (a network tree), not the U+F6FF the
        // waybar config used: that codepoint is not in Hack Nerd Font, so it
        // drew as an empty tofu box. It was carried over from the waybar
        // config, where the same substitution happened.
        text: !root.online ? "offline \uf127" : (root.wifi ? Util.pad(root.signal, 3) + "% \uf1eb" : "eth \uf0e8")
        color: root.online ? Theme.cyan : Theme.red
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
    }
}
