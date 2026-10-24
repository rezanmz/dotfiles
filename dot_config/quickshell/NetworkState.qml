pragma Singleton

// The network, as one truth: which devices exist, what the radio is doing, and
// how that becomes a sentence.
//
// Two surfaces ask the same question — the bar readout and the network panel —
// and they used to answer it by looking for a *connected* device. That loses the
// radio: with wifi switched off there is no connected device, so the panel's
// power switch disappeared together with the connection it belonged to, and the
// bar drew the same "offline" for a radio that is off as for a radio that is on
// and idle. The lookups here are by type instead, so the radio keeps its device
// when it is off, and `phase` separates the states that used to share a glyph.
//
// The nmcli helpers at the bottom are here, not in the panel, because they are
// the parts with branches: nmcli has no QML module and no API, so the profile
// text and the argument vector are the interface, and both can be checked
// without touching a live connection.
import QtQuick
import Quickshell
import Quickshell.Networking

Singleton {
    id: root

    // NetworkManager's backend answers asynchronously: until it does,
    // Networking.wifiEnabled reads false and the device list is empty. Drawing
    // that as "wifi is off" would be a lie for the first second of every boot.
    readonly property bool ready: Networking.devices.values.length > 0

    readonly property var devices: Networking.devices.values

    // The interface you would connect with, not merely a wifi one:
    // wpa_supplicant's P2P interface is listed as a wifi device too, and it is
    // never the one in station mode.
    readonly property var wifiDevice: {
        const devices = Networking.devices.values;
        let fallback = null;
        for (let i = 0; i < devices.length; i++) {
            const device = devices[i];
            if (device.type !== DeviceType.Wifi)
                continue;
            if (device.name.indexOf("p2p-") === 0)
                continue;
            if (device.mode === WifiDeviceMode.Station)
                return device;
            if (fallback === null)
                fallback = device;
        }
        return fallback;
    }

    readonly property var wiredDevice: {
        const devices = Networking.devices.values;
        for (let i = 0; i < devices.length; i++) {
            if (devices[i].type === DeviceType.Wired)
                return devices[i];
        }
        return null;
    }

    // The device carrying traffic: what Stats samples, and what the panel reads
    // its addresses from.
    readonly property var activeDevice: {
        const devices = Networking.devices.values;
        for (let i = 0; i < devices.length; i++) {
            if (devices[i].connected)
                return devices[i];
        }
        return null;
    }

    readonly property var connectingDevice: {
        const devices = Networking.devices.values;
        for (let i = 0; i < devices.length; i++) {
            if (devices[i].state === ConnectionState.Connecting)
                return devices[i];
        }
        return null;
    }

    readonly property bool radioOn: Networking.wifiEnabled
    readonly property bool hardwareOn: Networking.wifiHardwareEnabled

    // The network we are on. The scan list holds it as connected; signalStrength
    // is a 0.0-1.0 fraction, not a percentage (waybar's {signalStrength} was
    // already 0-100).
    readonly property var connectedNetwork: {
        const device = root.wifiDevice;
        if (device === null || !device.connected || !device.networks)
            return null;
        const networks = device.networks.values;
        for (let i = 0; i < networks.length; i++) {
            if (networks[i].connected)
                return networks[i];
        }
        return null;
    }

    readonly property var connectingNetwork: {
        const device = root.wifiDevice;
        if (device === null || !device.networks)
            return null;
        const networks = device.networks.values;
        for (let i = 0; i < networks.length; i++) {
            if (networks[i].state === ConnectionState.Connecting)
                return networks[i];
        }
        return null;
    }

    readonly property int signal: root.connectedNetwork !== null ? Math.round(root.connectedNetwork.signalStrength * 100) : 0

    readonly property bool onWifi: root.activeDevice !== null && root.activeDevice.type === DeviceType.Wifi
    readonly property bool onWired: root.activeDevice !== null && root.activeDevice.type === DeviceType.Wired

    readonly property string phase: root.classify(root.ready, root.activeDevice !== null, root.connectingDevice !== null, root.wifiDevice !== null, root.wiredDevice !== null, root.hardwareOn, root.radioOn)

    // The state machine, kept as a function of its inputs so every branch can be
    // exercised without unplugging the machine or switching its radio off.
    function classify(ready: bool, connected: bool, connecting: bool, wifiPresent: bool, wiredPresent: bool, hardwareOn: bool, radioOn: bool): string {
        if (!ready)
            return "starting";
        if (connected)
            return "connected";
        if (connecting)
            return "connecting";
        if (wifiPresent) {
            if (!hardwareOn)
                return "blocked";
            if (!radioOn)
                return "off";
            return "disconnected";
        }
        if (wiredPresent)
            return "disconnected";
        return "absent";
    }

    // The one word the bar and the panel put next to the state.
    function statusWord(phase: string): string {
        switch (phase) {
        case "starting":
            return "\u2026";
        case "connected":
            return "connected";
        case "connecting":
            return "connecting";
        case "blocked":
            return "blocked";
        case "off":
            return "wifi off";
        case "disconnected":
            return "not connected";
        case "absent":
            return "no device";
        }
        return "";
    }

    // One colour per state, on the bar and in the panel.
    function phaseColor(phase: string): color {
        switch (phase) {
        case "connected":
            return Theme.green;
        case "connecting":
            return Theme.cyan;
        case "disconnected":
            return Theme.orange;
        case "absent":
            return Theme.red;
        }
        return Theme.comment;
    }

    // The bar's compact readout, one case per phase. The glyphs are all in Hack
    // Nerd Font; the broken-chain one (U+F127) is "there is a network but you are
    // not on it", the cross (U+F00D) is "the radio is off", and the ban (U+F05E)
    // is "the radio is switched off underneath us".
    function barText(phase: string, signal: int, onWifi: bool): string {
        switch (phase) {
        case "connected":
            return onWifi ? Util.pad(signal, 3) + "% \uf1eb" : "eth \uf0e8";
        case "connecting":
            return "connecting \uf1eb";
        case "off":
            return "wifi off \uf00d";
        case "blocked":
            return "wifi off \uf05e";
        case "disconnected":
            return "no net \uf127";
        case "absent":
            return "no net \uf127";
        }
        return "\u2026";
    }

    // The panel's advice for everything that is not connected. Connected has no
    // hint: it has addresses instead.
    function hint(phase: string, connectingTo: string): string {
        switch (phase) {
        case "starting":
            return "waiting for NetworkManager\u2026";
        case "off":
            return "wifi is off \u2014 switch it on to see networks";
        case "blocked":
            return "wifi is switched off by a hardware switch";
        case "connecting":
            return connectingTo !== "" ? "connecting to " + connectingTo + "\u2026" : "connecting\u2026";
        case "disconnected":
            return "not connected \u2014 pick a network below";
        case "absent":
            return "no network interface";
        }
        return "";
    }

    // NetworkManager's own verdict, only after a check has actually run: Unknown
    // means the daemon has not answered yet, and is not shown.
    function connectivityLabel(connectivity: int): string {
        switch (connectivity) {
        case NetworkConnectivity.Full:
            return "internet";
        case NetworkConnectivity.Limited:
            return "no internet";
        case NetworkConnectivity.Portal:
            return "login required";
        case NetworkConnectivity.None:
            return "no internet";
        }
        return "";
    }

    // Short names for the security enum, which is otherwise "Wpa2Psk".
    function securityLabel(security: int): string {
        switch (security) {
        case WifiSecurityType.Open:
            return "open";
        case WifiSecurityType.Owe:
            return "owe";
        case WifiSecurityType.Sae:
        case WifiSecurityType.Wpa3SuiteB192:
            return "wpa3";
        case WifiSecurityType.Wpa2Psk:
            return "wpa2";
        case WifiSecurityType.WpaPsk:
            return "wpa";
        case WifiSecurityType.Wpa2Eap:
        case WifiSecurityType.WpaEap:
        case WifiSecurityType.Leap:
            return "802.1x";
        case WifiSecurityType.StaticWep:
        case WifiSecurityType.DynamicWep:
            return "wep";
        }
        return "";
    }

    // ---- nmcli text ------------------------------------------------
    //
    // `nmcli -m multiline` prints "KEY:    value" and keeps the array index in
    // the key ("IP4.ADDRESS[1]"). Repeated keys are collected in order, "--" is
    // nmcli's empty value.
    function parseMultiline(text: string): var {
        const out = {};
        const lines = text.split("\n");
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i];
            const colon = line.indexOf(":");
            if (colon <= 0)
                continue;
            let key = line.slice(0, colon).trim();
            const value = line.slice(colon + 1).trim();
            const bracket = key.indexOf("[");
            if (bracket > 0)
                key = key.slice(0, bracket);
            if (out[key] === undefined)
                out[key] = [];
            if (value !== "" && value !== "--")
                out[key].push(value);
        }
        return out;
    }

    // The subset of a connection profile this panel edits. `ipv4.dns` is empty
    // when the DNS comes from DHCP, and nmcli is free to print the servers
    // separated by commas or spaces, so they are normalised to commas here.
    function parseProfile(text: string): var {
        const map = root.parseMultiline(text);
        const first = key => map[key] !== undefined && map[key].length > 0 ? map[key][0] : "";
        const dns = (map["ipv4.dns"] !== undefined ? map["ipv4.dns"] : []).join(",").split(/[\s,]+/).filter(part => part !== "").join(",");
        return {
            "method": first("ipv4.method") === "manual" ? "manual" : "auto",
            "address": first("ipv4.addresses"),
            "gateway": first("ipv4.gateway"),
            "dns": dns,
            "ipv6": first("ipv6.method") === "ignore" ? "ignore" : "auto",
            "autoconnect": first("connection.autoconnect") !== "no"
        };
    }

    // Refuse the two mistakes that would leave the profile unusable: a manual
    // method without an address, and anything that is not an address in the
    // fields nmcli takes verbatim.
    function validate(method: string, address: string, gateway: string, dns: string): string {
        if (method === "manual") {
            if (!/^[0-9a-fA-F.:]+\/[0-9]{1,3}$/.test(address))
                return "address must be ip/prefix, e.g. 192.168.1.50/24";
            if (!/^[0-9a-fA-F.]+$/.test(gateway))
                return "gateway must be an address";
        }
        if (dns !== "" && !/^[0-9a-fA-F.:,]+$/.test(dns))
            return "dns must be addresses separated by commas";
        return "";
    }

    // The argument vector for `nmcli connection modify`, built as an array so
    // nothing is quoted or word-split by a shell. `ipv4.ignore-auto-dns` is what
    // makes typed DNS survive DHCP: without it NetworkManager appends the
    // lease's servers to the list and the field looks ignored.
    function modifyArgs(connection: string, method: string, address: string, gateway: string, dns: string, ipv6: string, autoconnect: bool): var {
        const args = ["nmcli", "connection", "modify", connection, "ipv4.method", method];
        if (method === "manual")
            args.push("ipv4.addresses", address, "ipv4.gateway", gateway);
        else
            args.push("ipv4.addresses", "", "ipv4.gateway", "");
        args.push("ipv4.dns", dns);
        args.push("ipv4.ignore-auto-dns", dns !== "" ? "yes" : "no");
        args.push("ipv6.method", ipv6);
        args.push("connection.autoconnect", autoconnect ? "yes" : "no");
        return args;
    }
}
