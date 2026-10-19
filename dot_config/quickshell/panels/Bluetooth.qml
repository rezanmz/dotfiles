import QtQuick
import qs
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io

// Bluetooth manager.
//
// A manager, not a device list: everything you would want from a bluetooth
// tool, in one panel.
//
//   - The adapter, with its power switch and the two settings that matter:
//     whether the adapter is visible to others and whether it is bondable.
//
//   - The devices, split into the ones that are paired and the ones that are
//     merely in range. A paired device gets its connection state, its
//     battery, and a set of actions that open under it: connect, disconnect,
//     trust, block, rename, forget, and whether it should be reconnected
//     automatically.
//
//   - A scan that stops by itself. BlueZ has no scan timeout -- the radio
//     keeps scanning for as long as anything asks it to, and a manager that
//     starts a scan and walks away leaves it scanning forever. This one runs
//     the scan for twenty seconds and then stops it.
//
// The pairing is the part that needed the most care. The kernel clears the
// bondable flag on every adapter at startup, and bluetoothd only puts it back
// when `AlwaysPairable` is set in main.conf or when a pairing agent with a
// usable IO capability is registered. Quickshell cannot register an agent
// (there is no QtDBus module to reach org.bluez.Agent1 with, and the
// Bluetooth module has no agent API), so on this machine the adapter sat
// non-bondable and pairing failed with "Authentication Canceled" -- the
// pairing would go through and then the device would drop, because without
// bondability the kernel does not store the keys.
//
// So the manager makes the adapter pairable itself before it pairs, which is
// the same thing bluetoothd does when an agent appears.
//
// A device that asks for a PIN or a passkey confirmation still needs a real
// agent, and there is none here: that pairing fails with an authentication
// error. A device that uses "Just Works" -- most of them, the Galaxy Buds
// among them -- pairs without any interaction at all.
Popup {
    id: root

    name: "bluetooth"
    contentWidth: 400

    readonly property var adapter: BluetoothState.adapter
    readonly property bool adapterOn: BluetoothState.adapterOn

    // Every device the adapter knows about, split into the ones that are
    // paired and the ones that are not. A device that is only in range is
    // temporary in BlueZ and disappears about thirty seconds after it was
    // last seen; that is BlueZ's own behaviour and the panel does not fight
    // it.
    readonly property var pairedDevices: {
        const out = [];
        if (!root.adapter)
            return out;
        const devices = root.adapter.devices.values;
        for (let i = 0; i < devices.length; i++) {
            const d = devices[i];
            if (d.paired || d.trusted)
                out.push(d);
        }
        // Connected first, then by name, so the device in use is at the top
        // and the rest keep a stable order.
        out.sort((a, b) => {
            if (a.connected !== b.connected)
                return a.connected ? -1 : 1;
            return (a.name || "").localeCompare(b.name || "");
        });
        return out;
    }

    readonly property var otherDevices: {
        const out = [];
        if (!root.adapter)
            return out;
        const devices = root.adapter.devices.values;
        for (let i = 0; i < devices.length; i++) {
            const d = devices[i];
            if (!d.paired && !d.trusted && !d.blocked)
                out.push(d);
        }
        // BlueZ does not expose RSSI through the Bluetooth module, so there
        // is no signal strength to sort by. The name is what is left, and it
        // keeps the list from shuffling as devices come and go.
        out.sort((a, b) => (a.name || "").localeCompare(b.name || ""));
        return out;
    }

    // The device whose row is open, if any. One at a time: opening a second
    // row closes the first.
    property var expandedDevice: null

    function toggleDetails(device: var): void {
        if (root.expandedDevice === device)
            root.expandedDevice = null;
        else
            root.expandedDevice = device;
    }

    function isExpanded(device: var): bool {
        return root.expandedDevice === device;
    }

    component Section: Text {
        color: Theme.comment
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSmall
        font.capitalization: Font.AllUppercase
    }

    // A small on/off control, used for the adapter power and the two
    // adapter settings.
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

            Behavior on color {
                ColorAnimation {
                    duration: Theme.animationFast
                }
            }
        }

        Rectangle {
            width: parent.height - 6
            height: width
            radius: width / 2
            y: 3
            x: toggle.on ? parent.width - width - 3 : 3
            color: toggle.on ? Theme.green : Theme.comment

            Behavior on x {
                NumberAnimation {
                    duration: Theme.animationFast
                    easing.type: Easing.OutCubic
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: toggle.toggled()
        }
    }

    // One line in a list of actions.
    component ActionRow: Item {
        id: action

        required property string label
        property string detail: ""
        property bool danger: false
        signal chosen()

        width: parent.width
        implicitHeight: 26

        Rectangle {
            anchors.fill: parent
            radius: Theme.radius
            color: actionHover.hovered ? Theme.alpha(Theme.selection, 0.8) : "transparent"
        }

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 36
            anchors.verticalCenter: parent.verticalCenter
            text: action.label
            color: action.danger ? Theme.red : Theme.fg
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
        }

        Text {
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            text: action.detail
            color: Theme.comment
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
        }

        HoverHandler {
            id: actionHover
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: action.chosen()
        }
    }

    // One device in the list.
    component DeviceRow: Item {
        id: row

        required property var device
        property bool expanded: false
        // An unpaired device has nothing to configure, only the pair button.
        property bool showActions: true
        property bool renaming: false

        signal toggleDetails()

        readonly property bool paired: row.device.paired || row.device.trusted
        readonly property bool connected: row.device.connected
        readonly property bool charging: Charging.isCharging(row.device.address)
        readonly property string title: BluetoothState.displayName(row.device)

        width: parent.width
        // The actions are inside the row's column, so the column's own height
        // already includes them -- the row grows by exactly as much as the
        // actions take.
        implicitHeight: rowContent.implicitHeight + 8

        Rectangle {
            anchors.fill: parent
            radius: Theme.radius
            color: rowHover.hovered ? Theme.hoverBg : "transparent"

            HoverHandler {
                id: rowHover
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (row.showActions)
                        row.toggleDetails();
                }
            }
        }

        Column {
            id: rowContent

            width: parent.width
            spacing: 0

            Item {
                width: parent.width
                implicitHeight: 44

                // The device icon. BlueZ names it (input-mouse, audio-headset,
                // keyboard, ...) and the icon theme has a picture for it.
                Image {
                    id: icon

                    anchors.left: parent.left
                    anchors.leftMargin: 4
                    anchors.verticalCenter: parent.verticalCenter
                    width: 22
                    height: 22
                    source: row.device.icon !== "" ? Quickshell.iconPath(row.device.icon, true) : ""
                    asynchronous: true
                    fillMode: Image.PreserveAspectFit
                }

                Column {
                    anchors.left: icon.right
                    anchors.leftMargin: 10
                    anchors.right: rightSide.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 1

                    Text {
                        width: parent.width
                        text: row.title
                        elide: Text.ElideRight
                        color: row.connected ? Theme.fg : Theme.comment
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSmall
                    }

                    Text {
                        width: parent.width
                        text: row.stateText()
                        elide: Text.ElideRight
                        color: row.connected ? Theme.green : Theme.comment
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSmall - 2
                    }
                }

                // The right-hand side: the battery, and the action button.
                Row {
                    id: rightSide

                    anchors.right: parent.right
                    anchors.rightMargin: 4
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8

                    // The battery. A device that reports one gets the level
                    // and, if it is on a charger, the bolt.
                    Row {
                        visible: row.device.batteryAvailable
                        spacing: 3
                        anchors.verticalCenter: parent.verticalCenter

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: row.charging ? Charging.glyph : String.fromCodePoint(0xF240)
                            color: row.charging ? Theme.green : Theme.comment
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSmall
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: Math.round(row.device.battery * 100) + "%"
                            color: Theme.comment
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSmall
                        }
                    }

                    // Connect, disconnect -- or pair, for a device that is
                    // not paired yet.
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 26
                        height: 26
                        radius: Theme.radius
                        color: actionHover.hovered ? Theme.alpha(Theme.selection, 0.9) : "transparent"

                        HoverHandler {
                            id: actionHover
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (!row.paired) {
                                    row.pair();
                                    return;
                                }
                                if (row.connected)
                                    row.device.disconnect();
                                else
                                    row.device.connect();
                            }
                        }

                        Text {
                            anchors.centerIn: parent
                            text: row.paired ? (row.connected ? String.fromCodePoint(0xF00C) : String.fromCodePoint(0xF0DA)) : String.fromCodePoint(0xF0C7)
                            color: row.connected ? Theme.pink : Theme.fg
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSmall
                        }
                    }
                }
            }

            // ---- the actions ---------------------------------------------
            //
            // Inside the row's own column, so that they are laid out below
            // the device line rather than on top of it. A column places its
            // children one after another, so the actions push the rest of the
            // list down instead of overlapping it.
            Column {
                id: rowActions

                width: parent.width
                visible: row.expanded
                spacing: 2

                ActionRow {
                    label: row.connected ? "Disconnect" : "Connect"
                    onChosen: {
                        if (row.connected)
                            row.device.disconnect();
                        else
                            row.device.connect();
                    }
                }

                ActionRow {
                    label: "Reconnect automatically"
                    detail: BluetoothState.wantsAutoConnect(row.device.address) ? "on" : "off"
                    onChosen: BluetoothState.setAutoConnect(row.device.address, !BluetoothState.wantsAutoConnect(row.device.address))
                }

                ActionRow {
                    label: row.device.trusted ? "Trusted" : "Trust this device"
                    detail: row.device.trusted ? "yes" : "no"
                    onChosen: row.device.trusted = !row.device.trusted
                }

                ActionRow {
                    label: row.device.blocked ? "Unblock" : "Block"
                    detail: row.device.blocked ? "blocked" : ""
                    onChosen: row.device.blocked = !row.device.blocked
                }

                ActionRow {
                    label: "Rename"
                    detail: row.device.name !== row.device.deviceName ? row.device.name : ""
                    onChosen: row.renaming = !row.renaming
                }

                // The rename field, shown under the action that opened it.
                Item {
                    width: parent.width
                    height: 30
                    visible: row.renaming

                    // The rename field. TextInput, not TextField: the latter
                    // is a QtQuick Controls type, which this shell does not
                    // pull in, and the name also collides with a component in
                    // this file.
                    TextInput {
                        id: renameField

                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.rightMargin: 56
                        anchors.verticalCenter: parent.verticalCenter
                        height: 26
                        text: row.device.name
                        color: Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSmall
                        selectByMouse: true
                        onAccepted: {
                            row.device.name = text;
                            row.renaming = false;
                        }
                    }

                    Rectangle {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: 50
                        height: 26
                        radius: Theme.radius
                        color: saveHover.hovered ? Theme.alpha(Theme.selection, 0.9) : "transparent"
                        border.width: 1
                        border.color: Theme.alpha(Theme.comment, 0.5)

                        Text {
                            anchors.centerIn: parent
                            text: "Save"
                            color: Theme.fg
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSmall
                        }

                        HoverHandler {
                            id: saveHover
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                row.device.name = renameField.text;
                                row.renaming = false;
                            }
                        }
                    }
                }

                ActionRow {
                    label: "Forget"
                    detail: row.paired ? "removes the pairing" : ""
                    danger: true
                    onChosen: row.forget()
                }
            }
        }

        // What the device is doing, in the words the panel uses everywhere.
        function stateText(): string {
            if (!row.paired)
                return "not paired";
            // The state enum knows about the transitions, so a device halfway
            // through connecting does not read as "disconnected".
            if (row.device.state === BluetoothDeviceState.Connecting)
                return "connecting…";
            if (row.device.state === BluetoothDeviceState.Disconnecting)
                return "disconnecting…";
            if (row.device.pairing)
                return "pairing…";
            if (row.connected)
                return row.charging ? "connected — charging" : "connected";
            return "disconnected";
        }

        // Pairing a device. The adapter has to be bondable for the pairing
        // to stick, and it is not bondable by default on this machine, so it
        // is made bondable first -- see BluetoothState.ensurePairable.
        function pair(): void {
            BluetoothState.ensurePairable();
            row.device.pair();
        }

        // Forgetting a device removes the pairing and the stored keys. BlueZ
        // does it through the adapter, not the device.
        function forget(): void {
            BluetoothState.stopScan();
            row.device.forget();
        }
    }

    // ---- header ---------------------------------------------------------
    Item {
        width: parent.width
        implicitHeight: 40

        Text {
            id: adapterName

            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: root.adapter ? (root.adapter.name || "bluetooth") : "no adapter"
            color: root.adapterOn ? Theme.fg : Theme.comment
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            font.weight: Font.DemiBold
        }

        Text {
            anchors.left: adapterName.right
            anchors.leftMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            text: !root.adapter ? "" : (root.adapterOn ? (BluetoothState.scanning ? "scanning " + BluetoothState.scanRemaining + "s" : "ready") : "off")
            color: BluetoothState.scanning ? Theme.pink : Theme.comment
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
        }

        Toggle {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            on: root.adapterOn
            visible: root.adapter !== null
            onToggled: {
                if (root.adapter)
                    root.adapter.enabled = !root.adapter.enabled;
            }
        }
    }

    // ---- adapter settings ----------------------------------------------
    //
    // Discoverable is whether other people can see this machine. Pairable is
    // whether a new device is allowed to bond with it, and it is the one that
    // has to be on for a pairing to stick.
    //
    // The bindings below read the adapter's properties, and a binding is
    // evaluated whether or not the item is visible -- so the adapter being
    // null has to be handled in the binding itself, not only by hiding the
    // column. There is no adapter until bluetoothd answers, and the panel is
    // created the moment it is opened.
    Column {
        width: parent.width
        spacing: 2
        visible: root.adapter !== null && root.adapterOn

        Item {
            width: parent.width
            implicitHeight: 28

            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "Visible to others"
                color: Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
            }

            Text {
                anchors.right: discoverableToggle.left
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                text: {
                    if (!root.adapter)
                        return "";
                    if (!root.adapter.discoverable)
                        return "hidden";
                    return root.adapter.discoverableTimeout === 0 ? "always" : root.adapter.discoverableTimeout + "s";
                }
                color: Theme.comment
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
            }

            Toggle {
                id: discoverableToggle

                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                on: root.adapter !== null && root.adapter.discoverable
                onToggled: {
                    if (root.adapter)
                        root.adapter.discoverable = !root.adapter.discoverable;
                }
            }
        }

        Item {
            width: parent.width
            implicitHeight: 28

            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "Accept new devices"
                color: Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
            }

            Text {
                anchors.right: pairableToggle.left
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                text: root.adapter === null ? "" : (root.adapter.pairable ? "on" : "off")
                color: root.adapter !== null && root.adapter.pairable ? Theme.green : Theme.comment
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
            }

            Toggle {
                id: pairableToggle

                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                on: root.adapter !== null && root.adapter.pairable
                onToggled: {
                    if (root.adapter)
                        root.adapter.pairable = !root.adapter.pairable;
                }
            }
        }
    }

    // ---- scanning -------------------------------------------------------
    Item {
        width: parent.width
        implicitHeight: 32
        visible: root.adapter !== null && root.adapterOn

        Rectangle {
            anchors.fill: parent
            radius: Theme.radius
            color: scanHover.hovered ? Theme.hoverBg : "transparent"

            HoverHandler {
                id: scanHover
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: BluetoothState.toggleScan()
            }
        }

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            text: BluetoothState.scanning ? "stop scanning" : "search for devices"
            color: BluetoothState.scanning ? Theme.pink : Theme.fg
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
        }

        Text {
            anchors.right: parent.right
            anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            text: BluetoothState.scanning ? BluetoothState.foundCount + " found" : ""
            color: Theme.comment
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
        }
    }

    // ---- paired devices -------------------------------------------------
    Section {
        text: "paired devices"
        visible: root.pairedDevices.length > 0
    }

    Repeater {
        model: root.pairedDevices

        delegate: DeviceRow {
            required property var modelData

            device: modelData
            expanded: root.isExpanded(modelData)
            onToggleDetails: root.toggleDetails(modelData)
        }
    }

    // ---- other devices --------------------------------------------------
    Section {
        text: BluetoothState.scanning ? "found nearby" : "not paired"
        visible: root.otherDevices.length > 0
    }

    Repeater {
        model: root.otherDevices

        delegate: DeviceRow {
            required property var modelData

            device: modelData
            expanded: false
            showActions: false
        }
    }

    Text {
        width: parent.width
        visible: root.pairedDevices.length === 0 && root.otherDevices.length === 0
        text: root.adapter === null ? "no bluetooth adapter" : (root.adapterOn ? "no devices yet — search for them" : "bluetooth is off")
        color: Theme.comment
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSmall
    }
}
