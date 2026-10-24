import QtQuick
import qs
import Quickshell
import Quickshell.Io
import Quickshell.Networking

// Network panel: the radio, what we are connected to, that connection's
// settings, and what is around us.
//
// The radio switch is the reason this panel was rewritten. It used to hang off
// `Stats.activeDevice`, and with wifi switched off there is no active device, so
// the one control that could switch the radio back on was the thing that
// disappeared. Everything the panel needs about the devices now comes from
// NetworkState, which looks them up by type and therefore keeps the radio's
// device when the radio is off (see NetworkState.qml).
//
// The address, gateway and DNS fields are typed into, and a popup window only
// sees key presses with an xdg popup grab (Popup.qml explains why), so this panel
// takes one. That is the same trade the notification centre makes, and the xdg
// grab dismisses the popup on an outside click by itself.
//
// Settings are written with `nmcli connection modify` and are never activated
// from here on their own: switching a live connection's profile means dropping
// it, and dropping the wifi link drops the session. "apply now" exists, but it is
// a second click and it says what it does.
Popup {
    id: root

    name: "network"
    contentWidth: 400

    grabFocus: true

    // The compositor can dismiss the grab behind Panels' back (popup_done just
    // hides the window), so close the panel for real when that happens. The
    // `open` check keeps the normal close animation out of this path.
    onVisibleChanged: {
        if (!visible && open)
            Panels.close();
    }

    readonly property string phase: NetworkState.phase
    readonly property var wifi: NetworkState.wifiDevice

    // The scan list: connected first, then by signal, and capped. A full scan
    // returns dozens of networks and the panel has no scrollbar, so the tail is
    // counted rather than pushed off the screen.
    readonly property var networks: {
        if (root.wifi === null)
            return [];
        const out = root.wifi.networks.values.slice();
        out.sort((a, b) => {
            if (a.connected !== b.connected)
                return a.connected ? -1 : 1;
            return b.signalStrength - a.signalStrength;
        });
        return out;
    }

    readonly property var visibleNetworks: root.networks.slice(0, 12)

    // ---- live connection details ----------------------------------------
    //
    // Read from nmcli: Quickshell's networking module exposes the device and its
    // MAC, but not the addresses, the gateway or DNS, and it has no profile API
    // at all. One read while the panel is open, refreshed on a slow timer because
    // a DHCP lease can change under it.
    property string connectionName: ""
    property string ipv4: ""
    property string ipv6: ""
    property string gateway: ""
    property string dns: ""
    property string mac: ""

    // ---- the editable profile -------------------------------------------
    property bool settingsOpen: false
    property bool dirty: false
    // Set while the profile read is copied into the fields: those writes are not
    // edits and must not mark the form dirty.
    property bool loading: false
    property string editMethod: "auto"
    property string editAddress: ""
    property string editGateway: ""
    property string editDns: ""
    property string editIpv6: "auto"
    property bool editAutoconnect: true

    property string status: ""
    property bool statusError: false
    property bool busy: false
    property int lastExit: -1
    property int lastApplyExit: -1

    // The two-step flags: applying restarts IP configuration, disconnecting and
    // forgetting drop the link, so each takes a second click to confirm.
    property bool applyArmed: false
    property bool disconnectArmed: false
    property bool forgetArmed: false

    // The network the password prompt belongs to, if any.
    property var pendingNetwork: null
    property string password: ""

    // ---- scanning and the connectivity check ----------------------------
    //
    // Both are radio/network activity, so they are only on while the panel is
    // open: a scan that outlives the panel keeps the card busy, and the
    // connectivity check is NetworkManager's own request.
    //
    // The panel is created exactly when it is opened, so `onOpenChanged` never
    // fires for the opening itself; Component.onCompleted does the first run.
    Component.onCompleted: {
        if (root.open)
            root.start();
    }

    onOpenChanged: {
        if (open) {
            root.start();
        } else {
            if (root.wifi !== null)
                root.wifi.scannerEnabled = false;
            Networking.connectivityCheckEnabled = false;
            root.settingsOpen = false;
            root.pendingNetwork = null;
            root.password = "";
            root.status = "";
            root.applyArmed = false;
            root.disconnectArmed = false;
            root.forgetArmed = false;
        }
    }

    function start(): void {
        if (root.wifi !== null)
            root.wifi.scannerEnabled = true;
        Networking.connectivityCheckEnabled = true;
        Networking.checkConnectivity();
        root.refreshDetails();
    }

    // The device appears after the panel is already open when the shell has just
    // started, or when the radio is switched on while the panel is open.
    Connections {
        target: NetworkState

        function onWifiDeviceChanged(): void {
            if (root.open && root.wifi !== null)
                root.wifi.scannerEnabled = true;
        }

        function onActiveDeviceChanged(): void {
            root.refreshDetails();
            root.refreshProfile();
        }
    }

    // Destroyed on close, so the scan has to be stopped here too: the wifi device
    // outlives the panel and would otherwise keep scanning.
    Component.onDestruction: {
        if (root.wifi !== null)
            root.wifi.scannerEnabled = false;
    }

    function refreshDetails(): void {
        if (!root.open || NetworkState.activeDevice === null)
            return;
        detailProc.running = true;
    }

    function refreshProfile(): void {
        if (!root.open || root.connectionName === "")
            return;
        profileProc.running = true;
    }

    function applyDetails(text: string): void {
        const map = NetworkState.parseMultiline(text);
        const first = key => map[key] !== undefined && map[key].length > 0 ? map[key][0] : "";
        root.connectionName = first("GENERAL.CONNECTION");
        root.ipv4 = first("IP4.ADDRESS");
        root.gateway = first("IP4.GATEWAY");
        root.dns = (map["IP4.DNS"] !== undefined ? map["IP4.DNS"] : []).join(", ");
        root.mac = first("GENERAL.HWADDR");
        // Link-local addresses are noise here; show the first global one.
        const global6 = (map["IP6.ADDRESS"] !== undefined ? map["IP6.ADDRESS"] : []).filter(address => address.indexOf("fe80:") !== 0);
        root.ipv6 = global6.length > 0 ? global6[0] : "";
        root.refreshProfile();
    }

    function applyProfile(text: string): void {
        // Edits in progress win over a refresh, otherwise the timer that keeps
        // the addresses current would erase what is being typed.
        if (root.dirty)
            return;
        const profile = NetworkState.parseProfile(text);
        root.loading = true;
        root.editMethod = profile.method;
        root.editAddress = profile.address;
        root.editGateway = profile.gateway;
        root.editDns = profile.dns;
        root.editIpv6 = profile.ipv6;
        root.editAutoconnect = profile.autoconnect;
        root.loading = false;
    }

    function markDirty(): void {
        if (!root.loading)
            root.dirty = true;
    }

    function save(): void {
        if (root.connectionName === "")
            return;
        const address = root.editAddress.trim();
        const gateway = root.editGateway.trim();
        const dns = root.editDns.split(",").map(part => part.trim()).filter(part => part !== "").join(",");
        const problem = NetworkState.validate(root.editMethod, address, gateway, dns);
        if (problem !== "") {
            root.status = problem;
            root.statusError = true;
            return;
        }
        root.busy = true;
        root.status = "";
        modifyProc.exec(NetworkState.modifyArgs(root.connectionName, root.editMethod, address, gateway, dns, root.editIpv6, root.editAutoconnect));
    }

    function finishModify(): void {
        root.busy = false;
        if (root.lastExit === 0) {
            root.status = "saved \u2014 apply now, or on the next reconnect";
            root.statusError = false;
            root.dirty = false;
            root.refreshProfile();
        } else {
            const lines = modifyErr.text.trim().split("\n").filter(line => line !== "");
            root.status = lines.length > 0 ? lines[lines.length - 1] : "nmcli failed (" + root.lastExit + ")";
            root.statusError = true;
        }
    }

    // Applying is `device reapply`, not bring-down-and-up: it rewrites the live
    // device's configuration from the profile without reassociating the wifi
    // link. It still restarts IP configuration, which is why it is a second click.
    function apply(): void {
        root.applyArmed = false;
        if (NetworkState.activeDevice === null)
            return;
        root.busy = true;
        root.status = "";
        applyProc.exec(["nmcli", "device", "reapply", NetworkState.activeDevice.name]);
    }

    function finishApply(): void {
        root.busy = false;
        if (root.lastApplyExit === 0) {
            root.status = "applied";
            root.statusError = false;
            root.refreshDetails();
        } else {
            root.status = "reapply failed (" + root.lastApplyExit + ")";
            root.statusError = true;
        }
    }

    // A row click: the network we are on opens its settings, any other one
    // connects (with a password prompt when NetworkManager has no secrets for
    // it). Disconnecting is deliberately not a row click any more -- it is the
    // one action that drops the whole session, so it lives behind its own row.
    function activate(network: var): void {
        if (network.connected) {
            root.settingsOpen = true;
            return;
        }
        root.pendingNetwork = null;
        root.password = "";
        if (network.known || network.security === WifiSecurityType.Open)
            network.connect();
        else
            root.pendingNetwork = network;
    }

    // ---- processes -------------------------------------------------------
    Process {
        id: detailProc

        command: ["nmcli", "-m", "multiline", "-f", "GENERAL.CONNECTION,IP4.ADDRESS,IP4.GATEWAY,IP4.DNS,IP6.ADDRESS,GENERAL.HWADDR", "device", "show", NetworkState.activeDevice !== null ? NetworkState.activeDevice.name : ""]
        running: false

        stdout: StdioCollector {
            id: detailOut

            waitForEnd: true
            onStreamFinished: root.applyDetails(detailOut.text)
        }
    }

    Timer {
        interval: 5000
        running: root.open
        repeat: true
        onTriggered: root.refreshDetails()
    }

    Process {
        id: profileProc

        command: ["nmcli", "-m", "multiline", "-f", "ipv4.method,ipv4.addresses,ipv4.gateway,ipv4.dns,ipv6.method,connection.autoconnect", "connection", "show", root.connectionName]
        running: false

        stdout: StdioCollector {
            id: profileOut

            waitForEnd: true
            onStreamFinished: root.applyProfile(profileOut.text)
        }
    }

    Process {
        id: modifyProc

        // Not onExited: that fires before the collector finalises, so the status
        // is handled one event-loop turn later (see panels/Audio.qml).
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: Qt.callLater(root.finishModify)
        }
        stderr: StdioCollector {
            id: modifyErr

            waitForEnd: true
        }
        onExited: (exitCode, exitStatus) => root.lastExit = exitCode
    }

    Process {
        id: applyProc

        stderr: StdioCollector {
            waitForEnd: true
            onStreamFinished: Qt.callLater(root.finishApply)
        }
        onExited: (exitCode, exitStatus) => root.lastApplyExit = exitCode
    }

    // ---- components ------------------------------------------------------
    component Section: Text {
        color: Theme.comment
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSmall
        font.capitalization: Font.AllUppercase
    }

    // The radio switch and the profile's autoconnect switch. Same control as the
    // bluetooth panel's, for the same reason: a pill reads as state, not as a
    // button.
    component Toggle: Item {
        id: toggle

        required property bool on
        signal toggled()

        width: 34
        height: 18

        Rectangle {
            anchors.fill: parent
            radius: parent.height / 2
            color: toggle.on ? Theme.alpha(Theme.green, 0.35) : Theme.alpha(Theme.comment, 0.25)
            border.width: 1
            border.color: toggle.on ? Theme.green : Theme.alpha(Theme.comment, 0.5)
        }

        Rectangle {
            width: parent.height - 6
            height: width
            radius: width / 2
            y: 3
            x: toggle.on ? parent.width - width - 3 : 3
            color: toggle.on ? Theme.green : Theme.comment
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: toggle.toggled()
        }
    }

    // Two mutually exclusive values, both visible: the current one is
    // highlighted, and one click picks the other.
    component Segmented: Row {
        id: segmented

        property var options: []
        property string value: ""
        signal chosen(string value)

        spacing: 4

        Repeater {
            model: segmented.options

            delegate: Rectangle {
                required property string modelData

                width: Math.max(56, option.implicitWidth + 16)
                height: 22
                radius: Theme.radius
                color: segmented.value === modelData ? Theme.alpha(Theme.cyan, 0.22) : "transparent"
                border.width: 1
                border.color: segmented.value === modelData ? Theme.cyan : Theme.alpha(Theme.comment, 0.5)

                Text {
                    id: option

                    anchors.centerIn: parent
                    text: modelData
                    color: segmented.value === modelData ? Theme.fg : Theme.comment
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: segmented.chosen(modelData)
                }
            }
        }
    }

    // One labelled text field. TextInput, not TextField: the latter is a
    // QtQuick Controls type, which this shell does not pull in.
    component Field: Item {
        id: field

        property string label: ""
        property string placeholder: ""
        property alias text: entry.text
        signal edited()

        width: parent.width
        implicitHeight: 46

        Text {
            id: caption

            anchors.left: parent.left
            anchors.leftMargin: 4
            anchors.top: parent.top
            text: field.label
            color: Theme.comment
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall - 1
        }

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: caption.bottom
            anchors.topMargin: 3
            height: 24
            radius: Theme.radius
            color: Theme.alpha(Theme.selection, 0.6)
            border.width: 1
            border.color: entry.activeFocus ? Theme.borderStrong : Theme.border

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                visible: entry.text === ""
                text: field.placeholder
                color: Theme.alpha(Theme.comment, 0.7)
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
            }

            TextInput {
                id: entry

                anchors.fill: parent
                anchors.leftMargin: 6
                anchors.rightMargin: 6
                verticalAlignment: TextInput.AlignVCenter
                color: Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                selectByMouse: true
                onTextChanged: field.edited()
            }
        }
    }

    component Button: Rectangle {
        id: button

        property string label: ""
        property bool usable: true
        signal clicked()

        implicitWidth: buttonLabel.implicitWidth + 20
        implicitHeight: 24
        radius: Theme.radius
        opacity: button.usable ? 1 : 0.5
        color: !button.usable ? "transparent" : (buttonHover.hovered ? Theme.alpha(Theme.selection, 0.9) : Theme.alpha(Theme.selection, 0.5))
        border.width: 1
        border.color: Theme.alpha(Theme.comment, 0.6)

        HoverHandler {
            id: buttonHover
            enabled: button.usable
        }

        Text {
            id: buttonLabel

            anchors.centerIn: parent
            text: button.label
            color: Theme.fg
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
        }

        MouseArea {
            anchors.fill: parent
            enabled: button.usable
            cursorShape: Qt.PointingHandCursor
            onClicked: button.clicked()
        }
    }

    // A line of text that acts as an action. The rows that drop the link ask for
    // the click twice, and read red once armed.
    component ActionRow: Item {
        id: action

        property string label: ""
        property bool danger: false
        property bool armed: false
        signal chosen()

        width: parent.width
        implicitHeight: 24

        Rectangle {
            anchors.fill: parent
            radius: Theme.radius
            color: actionHover.hovered ? Theme.hoverBg : "transparent"
        }

        HoverHandler {
            id: actionHover
        }

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            text: action.armed ? action.label + " \u2014 sure?" : action.label
            color: action.danger ? Theme.red : Theme.fg
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: action.chosen()
        }
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

    // One network in the scan list.
    component NetworkRow: Item {
        id: row

        required property var network

        readonly property bool connected: row.network.connected
        readonly property bool busy: row.network.state === ConnectionState.Connecting
        readonly property bool known: row.network.known
        readonly property bool secured: row.network.security !== WifiSecurityType.Open

        property bool confirmingForget: false

        width: parent.width
        implicitHeight: 30

        Rectangle {
            anchors.fill: parent
            radius: Theme.radius
            color: rowHover.hovered ? Theme.hoverBg : "transparent"
        }

        HoverHandler {
            id: rowHover
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.activate(row.network)
        }

        SignalBars {
            id: bars

            anchors.left: parent.left
            anchors.leftMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            strength: row.network.signalStrength
        }

        Text {
            id: name

            anchors.left: bars.right
            anchors.leftMargin: 8
            anchors.right: rightSide.left
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            text: (row.secured ? "\uf023 " : "") + row.network.name
            elide: Text.ElideRight
            color: row.connected ? Theme.fg : Theme.comment
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
        }

        Row {
            id: rightSide

            anchors.right: parent.right
            anchors.rightMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: row.busy ? "connecting\u2026" : (row.connected ? "connected" : (row.known ? "saved" : NetworkState.securityLabel(row.network.security)))
                color: row.busy ? Theme.cyan : (row.connected ? Theme.green : Theme.comment)
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
            }

            // Forget, in two clicks, and only for a saved network that is not the
            // one we are on: forgetting the active profile drops the link.
            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: row.known && !row.connected && !row.busy
                text: row.confirmingForget ? "forget?" : "\uf00d"
                color: row.confirmingForget ? Theme.red : Theme.alpha(Theme.comment, 0.9)
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall

                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -4
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (row.confirmingForget) {
                            row.confirmingForget = false;
                            row.network.forget();
                        } else {
                            row.confirmingForget = true;
                            forgetTimer.restart();
                        }
                    }
                }
            }
        }

        Timer {
            id: forgetTimer

            interval: 2500
            onTriggered: row.confirmingForget = false
        }
    }

    // ---- header ----------------------------------------------------------
    Item {
        width: parent.width
        implicitHeight: 34

        Text {
            id: title

            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: root.wifi !== null ? root.wifi.name : "network"
            color: Theme.fg
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            font.weight: Font.DemiBold
        }

        Text {
            anchors.left: title.right
            anchors.leftMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            text: NetworkState.statusWord(root.phase)
            color: root.phaseColor
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
        }

        // The radio. Visible whenever there is a wifi device, whether or not the
        // device is connected or its radio is on -- which is the whole point.
        Toggle {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            visible: root.wifi !== null
            on: NetworkState.radioOn
            onToggled: Networking.wifiEnabled = !Networking.wifiEnabled
        }
    }

    // One colour per state, shared with the bar readout.
    readonly property color phaseColor: NetworkState.phaseColor(root.phase)

    // ---- connection ------------------------------------------------------
    Section {
        text: "connection"
    }

    Column {
        width: parent.width
        spacing: 2

        Item {
            width: parent.width
            implicitHeight: 20

            Text {
                id: connectionLabel

                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: {
                    if (NetworkState.connectedNetwork !== null)
                        return NetworkState.connectedNetwork.name;
                    if (NetworkState.activeDevice !== null)
                        return NetworkState.activeDevice.name;
                    return NetworkState.statusWord(root.phase);
                }
                color: root.phaseColor
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
            }

            // NetworkManager's own check, once it has run: "connected" with no
            // internet is a different situation from connected.
            Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: NetworkState.connectivityLabel(Networking.connectivity)
                visible: root.phase === "connected" && text !== ""
                color: Networking.connectivity === NetworkConnectivity.Full ? Theme.green : Theme.orange
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
            }
        }

        // Throughput, which used to be two fixed-width fields on the bar. Shown
        // whenever an interface is up rather than only when connected: a link
        // that carries no address still moves packets, and that is exactly when
        // the numbers are interesting.
        Text {
            width: parent.width
            visible: Stats.iface !== ""
            text: "\u2193 " + Util.rate(Stats.netRx) + "   \u2191 " + Util.rate(Stats.netTx)
            color: Theme.comment
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
        }

        // What to do next, for every state that is not connected. Connected has
        // addresses instead of advice.
        Text {
            width: parent.width
            visible: root.phase !== "connected"
            text: NetworkState.hint(root.phase, NetworkState.connectingNetwork !== null ? NetworkState.connectingNetwork.name : "")
            wrapMode: Text.Wrap
            color: Theme.comment
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
        }

        Text {
            width: parent.width
            visible: root.phase === "connected" && text !== ""
            text: root.ipv4 + (root.gateway !== "" ? "   gw " + root.gateway : "")
            color: Theme.comment
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
        }

        Text {
            width: parent.width
            visible: root.phase === "connected" && text !== ""
            text: root.dns !== "" ? "dns " + root.dns : ""
            color: Theme.comment
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
        }

        Text {
            width: parent.width
            visible: root.phase === "connected" && text !== ""
            text: {
                if (NetworkState.activeDevice === null)
                    return "";
                const parts = [NetworkState.activeDevice.name];
                if (root.mac !== "")
                    parts.push(root.mac);
                if (root.ipv6 !== "")
                    parts.push(root.ipv6);
                return parts.join("   ");
            }
            elide: Text.ElideRight
            color: Theme.comment
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
        }
    }

    // ---- settings --------------------------------------------------------
    //
    // Collapsed by default: this is the least-used part of the panel, and the
    // network list belongs above the fold. Everything here writes the profile;
    // nothing is activated until "apply now" is clicked twice.
    Item {
        width: parent.width
        implicitHeight: 26
        visible: root.phase === "connected" && root.connectionName !== ""

        Rectangle {
            anchors.fill: parent
            radius: Theme.radius
            color: settingsHover.hovered ? Theme.hoverBg : "transparent"
        }

        HoverHandler {
            id: settingsHover
        }

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            text: "settings"
            color: Theme.fg
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
        }

        Text {
            anchors.right: parent.right
            anchors.rightMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            text: {
                if (root.dirty)
                    return "unsaved";
                if (root.settingsOpen)
                    return root.editMethod === "manual" ? "manual" : "automatic";
                return root.editMethod === "manual" ? "ip / dns \u00b7 manual" : "ip / dns \u00b7 automatic";
            }
            color: root.dirty ? Theme.yellow : Theme.comment
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.settingsOpen = !root.settingsOpen
        }
    }

    Column {
        width: parent.width
        spacing: 6
        visible: root.settingsOpen && root.phase === "connected" && root.connectionName !== ""

        Item {
            width: parent.width
            implicitHeight: 24

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 4
                anchors.verticalCenter: parent.verticalCenter
                text: "IPv4"
                color: Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
            }

            Segmented {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                options: ["auto", "manual"]
                value: root.editMethod
                onChosen: value => {
                    root.editMethod = value;
                    root.markDirty();
                }
            }
        }

        Field {
            visible: root.editMethod === "manual"
            label: "address (ip/prefix)"
            placeholder: "192.168.1.50/24"
            text: root.editAddress
            onEdited: root.markDirty()
        }

        Field {
            visible: root.editMethod === "manual"
            label: "gateway"
            placeholder: "192.168.1.1"
            text: root.editGateway
            onEdited: root.markDirty()
        }

        Field {
            label: "dns (blank = from dhcp)"
            placeholder: "1.1.1.1, 9.9.9.9"
            text: root.editDns
            onEdited: root.markDirty()
        }

        Item {
            width: parent.width
            implicitHeight: 24

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 4
                anchors.verticalCenter: parent.verticalCenter
                text: "IPv6"
                color: Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
            }

            Segmented {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                options: ["auto", "ignore"]
                value: root.editIpv6
                onChosen: value => {
                    root.editIpv6 = value;
                    root.markDirty();
                }
            }
        }

        Item {
            width: parent.width
            implicitHeight: 24

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 4
                anchors.verticalCenter: parent.verticalCenter
                text: "reconnect automatically"
                color: Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
            }

            Toggle {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                on: root.editAutoconnect
                onToggled: {
                    root.editAutoconnect = !root.editAutoconnect;
                    root.markDirty();
                }
            }
        }

        Row {
            width: parent.width
            spacing: 8

            Button {
                label: "save"
                usable: !root.busy
                onClicked: root.save()
            }

            // Two clicks: reapplying restarts the device's IP configuration, which
            // interrupts whatever is using the link.
            Button {
                label: root.applyArmed ? "apply \u2014 sure?" : "apply now"
                usable: !root.busy
                onClicked: {
                    if (root.applyArmed) {
                        root.apply();
                        return;
                    }
                    root.applyArmed = true;
                    disarmTimer.restart();
                }
            }
        }

        Text {
            width: parent.width
            visible: root.status !== ""
            text: root.status
            wrapMode: Text.Wrap
            color: root.statusError ? Theme.red : Theme.comment
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
        }

        // The two actions that drop the link. Both ask twice.
        ActionRow {
            label: "disconnect"
            visible: root.phase === "connected"
            danger: true
            armed: root.disconnectArmed
            onChosen: {
                if (!root.disconnectArmed) {
                    root.disconnectArmed = true;
                    disarmTimer.restart();
                    return;
                }
                root.disconnectArmed = false;
                if (NetworkState.activeDevice !== null)
                    NetworkState.activeDevice.disconnect();
            }
        }

        ActionRow {
            label: "forget this network"
            visible: root.phase === "connected"
            danger: true
            armed: root.forgetArmed
            onChosen: {
                if (!root.forgetArmed) {
                    root.forgetArmed = true;
                    disarmTimer.restart();
                    return;
                }
                root.forgetArmed = false;
                if (NetworkState.connectedNetwork !== null)
                    NetworkState.connectedNetwork.forget();
            }
        }

        Timer {
            id: disarmTimer

            interval: 2500
            onTriggered: {
                root.applyArmed = false;
                root.disconnectArmed = false;
                root.forgetArmed = false;
            }
        }
    }

    // ---- networks --------------------------------------------------------
    Item {
        width: parent.width
        implicitHeight: 18
        visible: root.wifi !== null && NetworkState.radioOn

        Section {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "networks"
        }

        Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.wifi !== null && root.wifi.scannerEnabled ? "scanning" : "rescan"
            color: root.wifi !== null && root.wifi.scannerEnabled ? Theme.pink : Theme.comment
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall

            MouseArea {
                anchors.fill: parent
                anchors.margins: -4
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (root.wifi !== null)
                        root.wifi.scannerEnabled = !root.wifi.scannerEnabled;
                }
            }
        }
    }

    // Password prompt for a network that is not saved yet. Enter connects, Escape
    // closes the prompt (the panel itself has the keyboard, see grabFocus above).
    Row {
        width: parent.width
        spacing: 8
        visible: root.pendingNetwork !== null

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "password for " + (root.pendingNetwork ? root.pendingNetwork.name : "")
            color: Theme.comment
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
        }

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 210
            height: 24
            radius: Theme.radius
            color: Theme.alpha(Theme.selection, 0.6)
            border.width: 1
            border.color: Theme.borderStrong

            TextInput {
                anchors.fill: parent
                anchors.leftMargin: 6
                anchors.rightMargin: 6
                verticalAlignment: TextInput.AlignVCenter
                echoMode: TextInput.Password
                color: Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                // Focus follows the prompt so the password can be typed straight
                // away; the panel's xdg grab is what lets the keys arrive.
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

    // The scan list, most useful first. Capped: a full scan returns dozens of
    // networks and the panel has no scrollbar, so the tail is summarised rather
    // than pushed off the bottom of the screen.
    Repeater {
        model: root.wifi !== null && NetworkState.radioOn ? root.visibleNetworks : []

        delegate: NetworkRow {
            required property var modelData

            network: modelData
        }
    }

    Text {
        width: parent.width
        visible: root.wifi !== null && NetworkState.radioOn && root.networks.length > root.visibleNetworks.length
        text: "+" + (root.networks.length - root.visibleNetworks.length) + " more"
        color: Theme.alpha(Theme.comment, 0.8)
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSmall
    }

    Text {
        width: parent.width
        visible: root.wifi !== null && NetworkState.radioOn && root.networks.length === 0
        text: root.wifi !== null && root.wifi.scannerEnabled ? "scanning\u2026" : "no networks in range"
        color: Theme.comment
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSmall
    }

    // Ethernet, or anything else that is not wifi: show what exists and what it
    // is doing, since those devices have no scan list to click.
    Section {
        text: "interfaces"
        visible: root.wifi === null && NetworkState.devices.length > 0
    }

    Repeater {
        model: root.wifi === null ? NetworkState.devices : []

        delegate: Item {
            id: interfaceRow

            required property var modelData

            readonly property string stateText: {
                switch (modelData.state) {
                case ConnectionState.Connected:
                    return "connected";
                case ConnectionState.Connecting:
                    return "connecting\u2026";
                case ConnectionState.Disconnecting:
                    return "disconnecting\u2026";
                }
                return modelData.hasLink === false ? "no cable" : "not connected";
            }

            width: parent.width
            implicitHeight: 24

            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: (modelData.connected ? "\uf111  " : "\uf10c  ") + modelData.name + "  " + modelData.address
                color: modelData.connected ? Theme.fg : Theme.comment
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
            }

            Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: {
                    const parts = [interfaceRow.stateText];
                    if (modelData.linkSpeed !== undefined && modelData.linkSpeed > 0)
                        parts.push(modelData.linkSpeed + " Mb/s");
                    return parts.join("  ");
                }
                color: modelData.connected ? Theme.green : Theme.comment
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
            }
        }
    }
}
