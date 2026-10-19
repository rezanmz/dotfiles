pragma Singleton

// The state a bluetooth manager needs that the Quickshell Bluetooth module
// does not carry.
//
// The module exposes the adapter and the devices, and the calls to pair,
// connect, disconnect and forget. What it does not expose is the part that
// decides whether any of those calls work:
//
//   - The scan lifecycle. BlueZ has no scan timeout: `Discovering` stays true
//     for as long as a client holds a discovery session, and the session ends
//     only when the client stops it or disconnects. A manager that starts a
//     scan and forgets about it leaves the radio scanning forever. Blueman
//     stops its scan after 60 seconds; this does it after 20.
//
//   - Whether the adapter is bondable. The kernel clears HCI_BONDABLE on every
//     adapter at startup and only bluetoothd puts it back, and it only does
//     that when `AlwaysPairable` is set in main.conf or when a pairing agent
//     with a usable IO capability is registered. With no agent registered --
//     and Quickshell cannot register one, see below -- the adapter sits
//     non-bondable, and a pairing attempt is rejected by the remote or
//     stripped of its bonding keys. That is the "Authentication Canceled"
//     failure the panel used to produce on the Galaxy Buds.
//
//   - The per-device preferences a manager is expected to remember: whether
//     the device should be reconnected automatically, and under what name.
//
// So the manager keeps that state here and the panel reads it.
import QtQuick
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io

Singleton {
    id: root

    // ---- the adapter ---------------------------------------------------
    readonly property var adapter: Bluetooth.defaultAdapter

    readonly property bool adapterPresent: root.adapter !== null
    readonly property bool adapterOn: root.adapterPresent && root.adapter.enabled

    // ---- scanning -------------------------------------------------------
    //
    // BlueZ keeps a scan running until the client stops it, so the manager
    // runs one on a timer of its own. The window is short on purpose: a
    // device that is going to be found is found within a few seconds, and a
    // radio that scans for minutes in the background is a radio that
    // interferes with the mouse and drains the battery.
    readonly property int scanSeconds: 20

    property bool scanning: false

    // When the current scan started, so the panel can show what is left of it.
    //
    // A double, not an int: the value is a millisecond timestamp, which is
    // well past what a 32-bit int can hold, and an int would wrap it into a
    // number from 1970 and make every elapsed calculation nonsense.
    property double scanStarted: 0

    // The number of devices seen during this scan, counted by the panel.
    property int foundCount: 0

    // A tick that runs while a scan is going, so the countdown in the panel
    // moves. It is only alive during a scan, so it costs nothing the rest of
    // the time.
    Timer {
        interval: 1000
        repeat: true
        running: root.scanning
        onTriggered: {
            const elapsed = Math.floor((Date.now() - root.scanStarted) / 1000);
            root.scanRemaining = Math.max(0, root.scanSeconds - elapsed);
        }
    }

    function startScan(): void {
        if (!root.adapterPresent)
            return;

        // A scan only finds devices that are willing to be found, and the
        // adapter has to be pairable for anything to be done with what it
        // finds. Making the adapter pairable first is what turns a scan that
        // finds things into a scan that can do something with them.
        root.ensurePairable();

        root.adapter.discovering = true;
        root.scanning = true;
        root.scanStarted = Date.now();
        root.scanRemaining = root.scanSeconds;
        root.foundCount = 0;
        scanTimer.restart();
    }

    function stopScan(): void {
        if (!root.adapterPresent)
            return;
        if (root.adapter.discovering)
            root.adapter.discovering = false;
        root.scanning = false;
        root.scanRemaining = 0;
        scanTimer.stop();
    }

    function toggleScan(): void {
        if (root.scanning)
            root.stopScan();
        else
            root.startScan();
    }

    // Seconds left in the current scan, for the panel's countdown.
    //
    // The countdown is a property the tick writes to rather than a computed
    // one: a computed property that reads the clock only re-evaluates when
    // one of its dependencies changes, and the wall clock is not one of them.
    property int scanRemaining: 0

    Timer {
        id: scanTimer

        interval: root.scanSeconds * 1000
        repeat: false
        onTriggered: root.stopScan()
    }

    // ---- bondability ----------------------------------------------------
    //
    // The adapter is not bondable by default, and without bondability a
    // pairing does not stick: the kernel refuses the remote's request, and
    // for a LE device it completes the pairing without storing the keys, so
    // the device drops the moment it reconnects.
    //
    // There is no way to make the adapter bondable from the outside except
    // writing the property, and writing it is exactly what
    // `AlwaysPairable = true` in main.conf does at startup -- but that also
    // leaves the adapter pairable forever, which is not what a manager
    // should do. So the manager writes the property itself, and puts it back
    // when it is done.
    function ensurePairable(): void {
        if (!root.adapterPresent)
            return;
        if (!root.adapter.pairable) {
            root.adapter.pairable = true;
            root.pairableRestored = true;
        }
    }

    // True when the manager turned bondability on, so it can turn it off
    // again. It is left on once a device is paired, because a bonded device
    // wants to be able to reconnect.
    property bool pairableRestored: false

    // ---- per-device preferences ----------------------------------------
    //
    // BlueZ has no "auto connect" property. `Trusted` is about accepting
    // incoming connections, not about reconnecting, so the preference to
    // reconnect a device has to be kept by the client -- which is what
    // Blueman does with its AutoConnect applet plugin.
    //
    // The preferences live in a file under the shell's config directory, so
    // they survive a restart of the shell.
    readonly property string prefsPath: Quickshell.env("XDG_CONFIG_HOME") + "/quickshell/bluetooth-prefs.json"

    property var prefs: ({})

    // The auto-connect preferences, as a map of lower-case address to true.
    readonly property var autoConnect: {
        const out = {};
        const prefs = root.prefs;
        for (const address in prefs) {
            if (prefs[address] && prefs[address].autoconnect)
                out[address] = true;
        }
        return out;
    }

    function wantsAutoConnect(address: string): bool {
        if (!address)
            return false;
        return root.autoConnect[address.toLowerCase()] === true;
    }

    function setAutoConnect(address: string, wanted: bool): void {
        if (!address)
            return;
        const key = address.toLowerCase();
        const prefs = Object.assign({}, root.prefs);
        const entry = Object.assign({}, prefs[key] || {});
        entry.autoconnect = wanted;
        prefs[key] = entry;
        root.prefs = prefs;
        root.savePrefs();
    }

    // The name to show for a device. BlueZ's Alias is the user's own name
    // for the device once it has been renamed, and the module exposes it as
    // `name`, so the alias itself lives in BlueZ and there is nothing to
    // mirror here.
    function displayName(device: var): string {
        if (!device)
            return "";
        return device.name || device.deviceName || "";
    }

    function savePrefs(): void {
        // setText() writes the file; the write is atomic by default, so a
        // crash mid-write cannot leave a half-written file behind.
        prefsFile.setText(JSON.stringify(root.prefs, null, 2));
    }

    FileView {
        id: prefsFile

        path: root.prefsPath
        blockLoading: true
        watchChanges: false
    }

    // ---- reading the preferences in -------------------------------------
    //
    // The file is read once at startup, when the singleton is first
    // referenced. A malformed file is ignored rather than fatal: the
    // preferences are a convenience, not something worth refusing to start
    // over.
    function loadPrefs(): void {
        const text = prefsFile.text();
        if (!text)
            return;
        try {
            const parsed = JSON.parse(text);
            if (parsed && typeof parsed === "object")
                root.prefs = parsed;
        } catch (e) {
            root.prefs = {};
        }
    }

    Component.onCompleted: {
        // The file has to be read before it can be written, and the write
        // happens only after this, so the order matters: load first.
        root.loadPrefs();
    }

    // ---- watching the devices -------------------------------------------
    //
    // Two things need the device list: the count of what a scan found, and
    // the reconnection of the devices that asked for it.
    //
    // The list is watched rather than polled, so a device that appears is
    // noticed straight away.
    property var seenAddresses: ({})
    property var pendingReconnects: ({})

    function noteDevices(): void {
        if (!root.adapter)
            return;

        const devices = root.adapter.devices.values;
        const seen = {};
        let found = 0;

        for (let i = 0; i < devices.length; i++) {
            const d = devices[i];
            const address = (d.address || "").toLowerCase();
            if (address === "")
                continue;
            seen[address] = true;

            // A device that has just appeared and is not connected yet, and
            // that asked to be reconnected, is asked again. The request is
            // only made once per appearance: BlueZ does the retrying.
            if (!d.connected && root.wantsAutoConnect(address) && !root.pendingReconnects[address]) {
                root.pendingReconnects[address] = true;
                d.connect();
            }
            if (!d.connected)
                continue;

            // The device is connected, so it is no longer waiting.
            if (root.pendingReconnects[address])
                delete root.pendingReconnects[address];

            if (!root.seenAddresses[address])
                found++;
        }

        root.foundCount = found;
        root.seenAddresses = seen;
    }

    // A tick that keeps the device list in view. It is cheap -- the list is
    // a handful of entries and the properties are cached by the shell -- and
    // it runs only while something is going on.
    Timer {
        interval: 2000
        repeat: true
        running: root.scanning || Object.keys(root.pendingReconnects).length > 0
        onTriggered: root.noteDevices()
    }

    // The reconnect has to be attempted once when the shell starts too: a
    // device that is already in range when the shell comes up should be
    // connected without waiting for the next scan.
    Timer {
        interval: 3000
        running: true
        repeat: false
        onTriggered: root.noteDevices()
    }
}
