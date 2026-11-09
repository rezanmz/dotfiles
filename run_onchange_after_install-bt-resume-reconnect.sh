#!/bin/sh
# Install a systemd sleep hook that recovers Bluetooth after resume by nudging
# the devices that did not come back on their own.
#
# Why: this machine's xHCI controller (0000:0c:00.0) fails its save/restore on
# every S3 resume -- "xHC error in resume, USBSTS 0x401, Reinit" -- and btmtk
# reloads the Bluetooth controller firmware as part of its own resume. That
# reset drops every link, and the devices plus BlueZ re-establish them by
# themselves within a few seconds (measured 2026-11-06, with no hook running at
# all: Keychron HID node 6 s after resume).
#
# The hook used to rebind btusb instead. That is wrong: it resets the controller
# a SECOND time, three seconds after the first one, and races the reconnect the
# devices are already making. 2026-11-09 09:23 is the bill for that -- the wake
# sequence was kernel reset :09.5, hook reload :12.5-:13.7, then bluetoothd
# "connect ... Operation already in progress (114)" and the kernel "ACL packet
# for unknown connection handle 50". The keyboard the user had just pressed to
# wake the machine never came back until it was power-cycled by hand, and the
# password prompt stayed unanswerable.
#
# So: record which paired devices were actually up before suspend, wait for them
# after resume, and only nudge the ones that are still down. A driver reload is
# kept for the one case it can fix, hci0 not existing at all.
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
if [ ! -f "$HOOK" ] || ! grep -q 'bt-resume v3' "$HOOK"; then
    cat >"$HOOK" <<'EOF'
#!/bin/sh
# Bluetooth recovery after resume (MediaTek MT7922, USB 0489:e0e2).
# bt-resume v3: nudge-only, no driver rebind.
#
# Installed by chezmoi: run_onchange_after_install-bt-resume-reconnect.sh
#
# The kernel resets this controller on every resume by itself (btmtk reloads the
# firmware right after "xHC error in resume, USBSTS 0x401, Reinit"), and the
# paired devices come back on their own within a few seconds. Rebinding btusb
# here therefore stacks a second reset on top of that one and breaks the
# reconnect that is already in flight -- see the installer for the 2026-11-09
# trace where that left the keyboard dead until it was power-cycled.
#
# Work done here: note which devices were up before suspend, wait for them after
# resume, nudge only the ones that stayed down, and re-enumerate the USB
# function in the one case where the adapter itself never came back.
#
# The post half must run detached: systemd-sleep.service kills its whole cgroup
# when it exits, so a plain `setsid ... &` child is SIGTERM'd within
# milliseconds (that is exactly what the earlier version did, silently, for four
# days). systemd-run puts it in its own transient unit, which outlives the sleep
# service; doing the work inline instead cost 60-90 s of every wake-up.
#
# Devices up before suspend.
STATE=/run/bt-resume-connected

bt_devices() {
    bluetoothctl devices Paired 2>/dev/null | awk '{print $2}'
}

bt_up() {
    bluetoothctl info "$1" 2>/dev/null | grep -q 'Connected: yes'
}

# Devices from $STATE (or all paired devices, if it is missing) that are down.
down() {
    if [ -f "$STATE" ]; then
        wanted=$(cat "$STATE")
    else
        wanted=$(bt_devices)
    fi
    for mac in $wanted; do
        bt_up "$mac" || echo "$mac"
    done
}

case "$1" in
pre)
    # Runs synchronously, before the suspend, so this must stay one bounded call:
    # a per-device `bluetoothctl info` loop here would put N D-Bus round trips to
    # bluetoothd -- the daemon that goes wedged on this box -- on the sleep path,
    # and a stall there becomes a 60-90 s wake again (systemd-sleep waits for the
    # hook). `devices Connected` returns exactly the set wanted, in one call.
    #
    # If this fails or times out, $STATE stays empty or stale and the post half
    # falls back to nudging every paired device, which is only wasteful.
    timeout 5 bluetoothctl devices Connected 2>/dev/null |
        awk '{print $2}' >"$STATE" 2>/dev/null || true
    exit 0
    ;;
post)
    if [ -z "${BT_RESUME_DETACHED:-}" ]; then
        systemd-run --quiet --collect --no-block \
            --unit="bt-resume-reconnect-$$" \
            --setenv=BT_RESUME_DETACHED=1 \
            /bin/sh "$0" post ||
            logger -t bt-resume "ERROR: systemd-run failed, recovery not started"
        exit 0
    fi

    # Wait for the adapter itself: hci0 is unregistered and registered again
    # while btmtk reloads the firmware.
    i=0
    while [ $i -lt 20 ] && [ ! -e /sys/class/bluetooth/hci0 ]; do
        sleep 0.5
        i=$((i + 1))
    done

    # The xHC reinit can leave the BT USB function dead. Re-enumerating it is the
    # only failure a driver-level reset would ever have fixed.
    if [ ! -e /sys/class/bluetooth/hci0 ]; then
        logger -t bt-resume "no hci0 after resume, re-authorising usb 1-6"
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
        logger -t bt-resume "ERROR: hci0 missing after resume, nothing to nudge"
        exit 1
    fi

    if [ -f "$STATE" ] && [ ! -s "$STATE" ]; then
        logger -t bt-resume "no device was up before suspend, nothing to do"
        exit 0
    fi

    # Two rounds of 10 s let the devices and BlueZ finish what they started.
    missing=""
    round=0
    while [ $round -lt 2 ]; do
        sleep 10
        missing=$(down)
        if [ -z "$missing" ]; then
            logger -t bt-resume "all devices from before suspend reconnected on their own"
            exit 0
        fi
        round=$((round + 1))
    done

    logger -t bt-resume "nudging devices still down: $(echo $missing)"
    for mac in $missing; do
        timeout 8 bluetoothctl connect "$mac" >/dev/null 2>&1 &
    done
    wait

    sleep 5
    missing=$(down)
    if [ -z "$missing" ]; then
        logger -t bt-resume "all devices reconnected after a nudge"
    else
        logger -t bt-resume "still down after a nudge: $(echo $missing)"
    fi
    ;;
esac
EOF
    chmod 755 "$HOOK"
    echo "wrote $HOOK"
else
    echo "$HOOK already correct"
fi

echo "bluetooth resume hook installed"
