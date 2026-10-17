import QtQuick
import QtQuick.Layouts
import qs
import Quickshell
import Quickshell.Io
import Quickshell.Networking

// Network panel: what we are connected to, and what is around us.
//
// This is where `kitty -e nmtui` was launched from. Everything comes from
// NetworkManager through Quickshell's Networking service: the active device, its
// address, the scan list with signal strength, and connecting (including a
// password prompt for a network that is not saved yet).
Popup {
    id: root

    name: "network"
    contentWidth: 400

    readonly property var device: Stats.activeDevice
    readonly property var wifi: root.device !== null && root.device.type === DeviceType.Wifi ? root.device : null

    // Scanning is a radio-state change, so it is only on while this panel is
    // open. Turning it on populates the device's network list.
    onOpenChanged: {
        if (root.wifi)
            root.wifi.scannerEnabled = open;
        if (open && root.device !== null)
            ipLookup.running = true;
    }

    // The network the password prompt belongs to, if any.
    property var pendingNetwork: null
    property string password: ""

    // NetworkDevice.address is the *hardware* address (XX:XX:...), not the IP, so
    // the address the old tooltip showed comes from NetworkManager's CLI. It is
    // read when the panel opens rather than polled.
    property string ipAddress: ""

    Process {
        id: ipLookup

        command: ["nmcli", "-g", "IP4.ADDRESS", "device", "show", root.device ? root.device.name : ""]
        stdout: StdioCollector {
            id: ipOut

            waitForEnd: true
            onStreamFinished: root.ipAddress = ipOut.text.trim().split("\n")[0]
        }
    }

    readonly property var networks: {
        if (!root.wifi)
            return [];
        const out = root.wifi.networks.values.slice();
        out.sort((a, b) => {
            if (a.connected !== b.connected)
                return a.connected ? -1 : 1;
            return b.signalStrength - a.signalStrength;
        });
        return out;
    }

    component Section: Text {
        color: Theme.comment
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSmall
        font.capitalization: Font.AllUppercase
    }

    // Signal strength drawn rather than glyphed: four bars whose fill follows the
    // 0.0-1.0 strength, so it cannot break with a font change.
    component SignalBars: Item {
        id: bars

        required property real strength

        implicitWidth: 18
        implicitHeight: 12

        Row {
            anchors.bottom: parent.bottom
            spacing: 2

            Repeater {
                model: 4

                delegate: Rectangle {
                    required property int index

                    width: 3
                    height: 4 + index * 2.5
                    anchors.bottom: parent.bottom
                    radius: 1
                    color: bars.strength * 4 > index + 0.5 ? Theme.cyan : Theme.alpha(Theme.comment, 0.4)
                }
            }
        }
    }

    component NetworkRow: Item {
        id: row

        required property var network

        width: parent.width
        implicitHeight: 26

        SignalBars {
            id: bars

            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            strength: row.network.signalStrength
        }

        Text {
            id: name

            anchors.left: bars.right
            anchors.leftMargin: 8
            anchors.right: state.left
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            text: (row.network.security !== WifiSecurityType.Open ? "\uf023 " : "") + row.network.name
            elide: Text.ElideRight
            color: row.network.connected ? Theme.fg : Theme.comment
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
        }

        Text {
            id: state

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: row.network.connected ? "connected" : (row.network.known ? "saved" : "")
            color: row.network.connected ? Theme.green : Theme.comment
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (row.network.connected) {
                    row.network.disconnect();
                } else if (row.network.known) {
                    // A saved network has its secrets in NetworkManager already.
                    root.pendingNetwork = null;
                    row.network.connect();
                } else if (row.network.security === WifiSecurityType.Open) {
                    root.pendingNetwork = null;
                    row.network.connect();
                } else {
                    root.pendingNetwork = row.network;
                    root.password = "";
                }
            }
        }
    }

    Section {
        text: "connection"
    }

    RowLayout {
        width: parent.width
        spacing: 10

        Text {
            text: {
                if (root.device === null)
                    return "offline";
                if (root.wifi)
                    return "wifi " + (root.wifi.connected ? "connected" : "disconnected");
                return root.device.type === DeviceType.Wired ? "ethernet" : "device";
            }
            color: root.device !== null && root.device.connected ? Theme.cyan : Theme.red
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
        }

        Item {
            Layout.fillWidth: true
        }

        Text {
            visible: root.wifi !== null
            text: Networking.wifiEnabled ? "wifi on" : "wifi off"
            color: Networking.wifiEnabled ? Theme.fg : Theme.comment
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: Networking.wifiEnabled = !Networking.wifiEnabled
            }
        }
    }

    Text {
        width: parent.width
        visible: root.device !== null
        text: {
            if (root.device === null)
                return "";
            const address = root.ipAddress !== "" ? root.ipAddress : "no address";
            if (root.wifi && root.wifi.mode === WifiDeviceMode.Station)
                return root.device.name + "  " + address;
            if (root.device.linkSpeed !== undefined)
                return root.device.name + "  " + address + "  " + root.device.linkSpeed + " Mb/s";
            return root.device.name + "  " + address;
        }
        color: Theme.comment
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSmall
    }

    // Password prompt for a network that is not saved yet. Enter connects,
    // Escape closes the prompt.
    RowLayout {
        width: parent.width
        spacing: 8
        visible: root.pendingNetwork !== null

        Text {
            text: "password for " + (root.pendingNetwork ? root.pendingNetwork.name : "")
            color: Theme.comment
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 24
            radius: Theme.radius
            color: Theme.alpha(Theme.selection, 0.6)
            border.width: 1
            border.color: Theme.borderStrong

            TextInput {
                id: passwordField

                anchors.fill: parent
                anchors.leftMargin: 6
                anchors.rightMargin: 6
                verticalAlignment: TextInput.AlignVCenter
                echoMode: TextInput.Password
                color: Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                // Focus follows the prompt so the password can be typed straight
                // away; the panel's popup takes keyboard focus for this.
                focus: root.pendingNetwork !== null
                onTextChanged: root.password = text
                onAccepted: {
                    if (root.pendingNetwork) {
                        root.pendingNetwork.connectWithPsk(root.password);
                        root.pendingNetwork = null;
                        root.password = "";
                    }
                }
                Keys.onEscapePressed: {
                    root.pendingNetwork = null;
                    root.password = "";
                }
            }
        }
    }

    Section {
        text: root.wifi !== null ? "networks" : "devices"
        visible: root.wifi !== null ? root.networks.length > 0 : Networking.devices.values.length > 0
    }

    Repeater {
        model: root.networks

        delegate: NetworkRow {
            required property var modelData

            network: modelData
        }
    }

    Repeater {
        model: root.wifi === null ? Networking.devices.values : []

        delegate: Text {
            required property var modelData

            width: parent.width
            text: (modelData.connected ? "\uf111  " : "\uf10c  ") + modelData.name + "  " + modelData.address
            color: modelData.connected ? Theme.fg : Theme.comment
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            elide: Text.ElideRight
        }
    }
}
