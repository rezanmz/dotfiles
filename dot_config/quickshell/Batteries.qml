pragma Singleton

// Every device that reports a battery, whatever bus it comes in on.
//
// Two sources: BlueZ (BluetoothDevice.battery — the mouse and keyboard report
// through the battery service) and UPower (everything else, e.g. the Logitech
// receiver, which surfaces there as a mouse battery). One merged list and one
// `lowest`, so the bar readout and the panel can never disagree about which
// device is closest to dying.
//
// A device can show up on both buses (UPower has a BlueZ battery source of its
// own): the Bluetooth entry wins and the duplicate is dropped by name.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import Quickshell.Services.UPower

Singleton {
    id: root

    // Service singletons discover asynchronously and only expose their
    // contents through these properties — a one-shot read sees an empty list.
    // The bindings are what keep the lists live (devices appearing, going to
    // sleep, or changing level all re-evaluate the merge below).
    readonly property var btDevices: {
        const adapter = Bluetooth.defaultAdapter;
        return adapter ? adapter.devices.values : [];
    }

    readonly property var upDevices: UPower.devices ? UPower.devices.values : []

    // {name, kind, percent, source} for everything that reports a level.
    readonly property var devices: {
        const out = [];
        const seen = {};

        for (let i = 0; i < root.btDevices.length; i++) {
            const d = root.btDevices[i];
            if (!d.batteryAvailable)
                continue;
            const name = d.name !== "" ? d.name : d.deviceName;
            seen[name.toLowerCase()] = true;
            out.push({
                "name": name,
                "kind": kindFromIcon(d.icon),
                "percent": Math.round(d.battery * 100),
                // The Bluetooth address, so the charging state (which the
                // kernel reports keyed by address) can be matched to this
                // device. Empty for the UPower devices below, which are not
                // Bluetooth devices.
                "address": d.address,
                "source": "bluetooth"
            });
        }

        for (let i = 0; i < root.upDevices.length; i++) {
            const d = root.upDevices[i];
            // No level means no battery worth reporting (UPower keeps line
            // power and drained husks in the list too).
            if (!d.ready || !d.isPresent || d.percentage <= 0)
                continue;
            const name = d.model !== "" ? d.model : d.nativePath;
            if (name === "" || seen[name.toLowerCase()])
                continue;
            out.push({
                "name": name,
                "kind": kindFromType(d.type),
                "percent": Math.round(d.percentage * 100),
                // Not a Bluetooth device, so there is no address to match a
                // charging state against.
                "address": "",
                "source": "upower"
            });
        }

        return out;
    }

    // The device closest to dying, or null when nothing reports a battery.
    readonly property var lowest: {
        let best = null;
        for (let i = 0; i < root.devices.length; i++) {
            const d = root.devices[i];
            if (best === null || d.percent < best.percent)
                best = d;
        }
        return best;
    }

    // "Low is bad" colour: green, orange past 20%, red past 10%. Theme.level is
    // the house helper, but it reads "high is bad" (temperature, disk), so it is
    // fed the discharge instead of the charge — same thresholds, right
    // direction, without touching the shared helper.
    function colorFor(percent: int): color {
        return Theme.level(100 - percent, 80, 90, Theme.green);
    }

    function kindFromIcon(icon: string): string {
        if (icon.indexOf("mouse") >= 0)
            return "mouse";
        if (icon.indexOf("keyboard") >= 0)
            return "keyboard";
        if (icon.indexOf("headset") >= 0 || icon.indexOf("headphone") >= 0 || icon.indexOf("speaker") >= 0 || icon.indexOf("audio") >= 0)
            return "headset";
        return "other";
    }

    function kindFromType(type: int): string {
        switch (type) {
        case UPowerDeviceType.Mouse:
            return "mouse";
        case UPowerDeviceType.Keyboard:
            return "keyboard";
        case UPowerDeviceType.Headset:
        case UPowerDeviceType.Headphones:
        case UPowerDeviceType.Speakers:
        case UPowerDeviceType.OtherAudio:
            return "headset";
        case UPowerDeviceType.Battery:
        case UPowerDeviceType.Ups:
            return "battery";
        }
        return "other";
    }
}
