pragma Singleton

// Which Bluetooth devices are charging right now.
//
// The question the bar wants to answer is "is my mouse on the charger", and
// nothing in the Bluetooth stack answers it:
//
//   - BlueZ 5.87's org.bluez.Battery1 has only Percentage and Source. The
//     Charging property is in the upstream API description but is marked
//     experimental and is not implemented here (the string is not even in the
//     daemon binary).
//   - Quickshell's BluetoothDevice exposes batteryAvailable and battery, and
//     no charging flag -- not in 0.3.2, not in upstream master.
//   - UPower would answer it too, through its own device list: it does see
//     the HID++ device, but as a power supply rather than as a Bluetooth
//     device, so it reports the level and the state without the address that
//     would tie it back to a Bluetooth device. The kernel node carries the
//     address, which is what the bar needs.
//
// What does answer it is the kernel. The hid-logitech-hidpp driver creates a
// power_supply node for every Logitech HID++ device it drives and maps the
// HID++ battery status byte onto the Linux power supply ABI (Charging,
// Discharging, Full, Not charging, Unknown). The node carries the device's
// Bluetooth address in serial_number, so the device is identified by address
// and not by name.
//
// The node only exists while the Bluetooth link is up, which is the same
// condition under which BlueZ reports a battery level at all -- so the bar
// shows a charging icon exactly when it could show a level too.
//
// Devices that are not Logitech HID++ ones (a plain Bluetooth keyboard, say)
// have no such node and therefore no charging state. That is a limit of the
// available signal, not of this code: there is no vendor-neutral way to ask
// whether an arbitrary Bluetooth device is on a charger.
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    // The Bluetooth addresses (lowercase, as the kernel spells them in
    // serial_number) of the devices the kernel reports a power state for,
    // mapped to that state: "Charging" or "Full" for a device on its charger,
    // "Discharging" for one running on its own.
    //
    // An address that is not in the map is a device the kernel says nothing
    // about -- either it is not on a charger, or it does not speak HID++ and
    // therefore has no node at all.
    //
    // A plain property rather than a computed one, because it is assigned by
    // the poll below. Widgets read it directly, so the dependency on it is
    // explicit and the readout updates when the poll lands.
    property var chargingByAddress: ({})

    // True when the device with this Bluetooth address is on its charger.
    // The address is compared case-insensitively: BlueZ spells it uppercase
    // ("D1:CF:B5:D4:D0:80") and the kernel lowercase
    // ("d1:cf:b5:d4:d0:80").
    function isCharging(address: string): bool {
        const status = root.statusFor(address);
        return status === "Charging" || status === "Full";
    }

    // The power state the kernel reports for an address, or "" when it
    // reports none.
    function statusFor(address: string): string {
        if (!address)
            return "";
        return root.chargingByAddress[address.toLowerCase()] || "";
    }

    // The lightning bolt that marks a charging device. U+F0E7, verified by
    // rendering it in Hack Nerd Font (it is the plain bolt, not a plug or a
    // battery-with-bolt). Built from the codepoint, not typed: the point sits
    // above the BMP.
    readonly property string glyph: String.fromCodePoint(0xF0E7)

    // One poll reads every power supply node: the address it belongs to and
    // its status, in one line each. The listing is done by a process because
    // the power supply class is a directory of symlinks -- there is no single
    // file to read and FileView only reads files.
    //
    // The nodes appear and disappear as devices connect and sleep, so the
    // whole set is re-read every time rather than tracked.
    Process {
        id: poll

        command: ["sh", "-c", `
            for d in /sys/class/power_supply/*/; do
                [ -r "$d/serial_number" ] || continue
                addr=$(cat "$d/serial_number" 2>/dev/null)
                [ -n "$addr" ] || continue
                status=$(cat "$d/status" 2>/dev/null)
                echo "$addr $status"
            done
        `]
        stdout: StdioCollector {
            id: pollOut

            waitForEnd: true
            onStreamFinished: root.apply(pollOut.text)
        }
    }

    // The kernel spells a charging device "Charging" and a device that has
    // finished charging "Full"; both mean the device is on power. The other
    // two are the device running on its own and on power but not taking any.
    //
    // The status is everything after the address, not just the second word:
    // one of the kernel's statuses is two words ("Not charging"), and taking
    // only the first would turn it into a status that is not one of them.
    function apply(text: string): void {
        const out = {};
        for (const line of text.split("\n")) {
            const trimmed = line.trim();
            if (trimmed === "")
                continue;
            const separator = trimmed.indexOf(" ");
            if (separator < 0)
                continue;
            const address = trimmed.slice(0, separator).toLowerCase();
            const status = trimmed.slice(separator + 1).trim().toLowerCase();
            if (status !== "charging" && status !== "full" && status !== "discharging" && status !== "not charging")
                continue;
            out[address] = status.charAt(0).toUpperCase() + status.slice(1);
        }
        root.chargingByAddress = out;
    }

    // The poll interval. A device that is plugged in while the bar is up
    // should show its icon without anyone waiting for a minute, but the state
    // only changes when someone plugs something in, so a poll every half
    // minute is enough and costs one fork.
    Timer {
        interval: 30000
        running: true
        repeat: true
        triggeredOnStart: true

        onTriggered: poll.running = true
    }
}
