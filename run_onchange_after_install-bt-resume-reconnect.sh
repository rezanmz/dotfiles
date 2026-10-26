#!/bin/sh
# Install a systemd sleep hook that recovers Bluetooth after resume by rebinding
# the btusb driver.
#
# Why: this machine's xHCI controller (0000:0c:00.0) fails its save/restore on
# every S3 resume -- "xHC error in resume, USBSTS 0x401, Reinit" -- and the kernel
# resets the Bluetooth controller, which reloads its firmware. The controller's
# connection table survives that reset as garbage: the paired devices report
# Connected, new HID nodes even appear, and they send nothing until they are
# power-cycled by hand.
#
# Restarting bluetooth.service does NOT fix that: it re-attaches BlueZ to the same
# stale controller, and stopping the daemon closes the HCI device, which costs a
# second firmware reload (measured: two re-inits per resume, and the new daemon
# came up 194 ms before the second one finished). Rebinding the driver does fix it:
# btusb is unloaded and reloaded, the USB device is re-probed and the controller
# state is rebuilt from scratch, then BlueZ reconnects the bonded devices -- same
# MACs, no re-pairing.
#
# Scope: resume from S3 only. Nothing here helps hibernation (S4), where the USB
# rail is off entirely.
#
# Needs root. Runs non-interactively so `chezmoi apply` can never hang on a
# password prompt; if sudo is not passwordless it prints the command.
#
# Re-run: chezmoi state delete-bucket --bucket=scriptState

set -eu

if [ "$(uname -s)" != "Linux" ]; then
    echo "not Linux; skipping bluetooth resume hook install" >&2
    exit 0
fi

if [ "$(id -u)" -ne 0 ]; then
    if sudo -n true 2>/dev/null; then
        exec sudo -n "$0"
    fi
    echo "bluetooth resume hook not installed: sudo needs a password." >&2
    echo "Run this once as root (path is stable, not a temp copy):" >&2
    echo "    sudo $HOME/.local/share/chezmoi/run_onchange_after_install-bt-resume-reconnect.sh" >&2
    exit 0
fi

HOOK=/usr/lib/systemd/system-sleep/50-bluetooth-reconnect
if [ ! -f "$HOOK" ] || ! grep -q 'rebinding btusb after resume' "$HOOK"; then
    cat >"$HOOK" <<'EOF'
#!/bin/sh
# Bluetooth recovery after resume (MediaTek MT7922, USB 0489:e0e2).
#
# Installed by chezmoi: run_onchange_after_install-bt-resume-reconnect.sh
#
# The xHCI save/restore fails on every resume and the BT controller is reset with
# its connection table intact but stale: devices show Connected and new HID nodes
# appear, yet no input arrives until the device is power-cycled. Rebinding btusb
# rebuilds the controller state; restarting bluetoothd does not.
case "$1" in
post)
    # Wait for the adapter to reappear, then let the USB side settle: the kernel
    # is still re-initialising the controller for the first ~2 s after resume.
    i=0
    while [ $i -lt 20 ] && [ ! -d /sys/class/bluetooth ]; do
        sleep 0.5
        i=$((i + 1))
    done
    sleep 3

    logger -t bt-resume "rebinding btusb after resume"
    modprobe -r btusb btmtk 2>/dev/null || true
    sleep 1
    modprobe btusb 2>/dev/null || true

    i=0
    while [ $i -lt 20 ] && [ ! -e /sys/class/bluetooth/hci0 ]; do
        sleep 0.5
        i=$((i + 1))
    done

    # Fallback: force a USB re-enumeration of the BT function if the rebind did
    # not bring the adapter back.
    if [ ! -e /sys/class/bluetooth/hci0 ]; then
        logger -t bt-resume "no hci0 after rebind, re-authorising usb 1-6"
        echo 0 >/sys/bus/usb/devices/1-6/authorized 2>/dev/null || true
        sleep 2
        echo 1 >/sys/bus/usb/devices/1-6/authorized 2>/dev/null || true
        i=0
        while [ $i -lt 20 ] && [ ! -e /sys/class/bluetooth/hci0 ]; do
            sleep 0.5
            i=$((i + 1))
        done
    fi

    if [ ! -e /sys/class/bluetooth/hci0 ]; then
        logger -t bt-resume "ERROR: adapter did not come back after rebind"
        exit 1
    fi

    # BlueZ reconnects bonded devices by itself, but a nudge is cheap and it is
    # what the manual power-cycle of the device was standing in for.
    sleep 2
    for mac in $(bluetoothctl devices Paired 2>/dev/null | awk '{print $2}'); do
        bluetoothctl connect "$mac" >/dev/null 2>&1 || true
    done
    logger -t bt-resume "hci0 back, paired devices nudged"
    ;;
esac
EOF
    chmod 755 "$HOOK"
    echo "wrote $HOOK"
else
    echo "$HOOK already correct"
fi

echo "bluetooth resume hook installed"
