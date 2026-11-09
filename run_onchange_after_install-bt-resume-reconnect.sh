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
# So: record which paired devices were actually up before suspend, then after
# resume drop the link of every BR/EDR HID device (the keyboard). That link is
# the real damage: the controller reset kills it without telling the device, the
# host's own reconnect then reports Connected and creates the input node, and no
# key ever arrives (2026-11-09 12:16:38, dead until the keyboard was power-cycled
# at 12:16:59). A teardown the DEVICE observes -- HCI Disconnect -- is what
# clears its stale hidp context, and the next key press rebuilds a clean link. LE
# HOGP devices (the mouse) are left alone, they recover by themselves. A driver
# reload is kept for the one case it can fix, hci0 not existing at all.
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
if [ ! -f "$HOOK" ] || ! grep -q 'bt-resume v7' "$HOOK"; then
    cat >"$HOOK" <<'EOF'
#!/bin/sh
# Bluetooth recovery after resume (MediaTek MT7922, USB 0489:e0e2).
# bt-resume v7: poll for the stale hidp link, drop it once, let the device rebuild.
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
# Work done here: note which devices were up before suspend, let BlueZ reconnect
# them, then DROP the BR/EDR HID link so the device stops using the hidp context
# the reset orphaned; the next key press makes the keyboard page the host and the
# link it builds is clean. A host-initiated connect is never attempted on it --
# the Keychron is not pageable while idle. LE devices get one bounded nudge, and
# the USB function is re-enumerated in the one case where the adapter itself
# never came back.
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

# BR/EDR HID (hidp) -- the keyboard. LE HOGP devices (the mouse) reconnect
# cleanly by themselves and must be left alone.
is_bredr_hid() {
    bluetoothctl info "$1" 2>/dev/null |
        grep -q '00001124-0000-1000-8000-00805f9b34fb'
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

    # BR/EDR HID: the device keeps the hidp context of the link the controller
    # reset destroyed and still believes it is connected, so its key presses go
    # into a dead link and it never re-pages (2026-11-09 12:16:38, silent until
    # the keyboard was power-cycled at 12:16:59). A teardown the DEVICE sees
    # clears that; the next key press then makes the keyboard page the host and
    # a device-initiated link is clean (confirmed 12:26 and 12:35).
    #
    # Never connect it from here: the Keychron is not pageable while idle, so a
    # host-initiated connect only fails ("Operation already in progress" at
    # 09:23, no link at 12:26 and 12:35) and would leave the keyboard down. The
    # price of this design is one swallowed key press per resume.
    #
    # BlueZ re-establishes links after the firmware reload, but not at a
    # predictable moment: intervals are 1,2,4,8,16,... and on 2026-11-06 a device
    # only reappeared 12 s after resume. A single snapshot would miss that and
    # leave the silent link in place, so poll for up to 25 s.
    #
    # Each device is dropped at most ONCE. Dropping it again when the user's own
    # key press has just rebuilt the link would swallow that press too, and keep
    # swallowing it, so the first successful drop ends the work for that MAC.
    ticks=0
    dropped=""
    while [ "$ticks" -lt 50 ]; do
        for mac in $(cat "$STATE" 2>/dev/null); do
            case " $dropped " in *" $mac "*) continue;; esac
            bt_up "$mac" || continue
            is_bredr_hid "$mac" || continue
            logger -t bt-resume "dropping stale hidp link, next key press rebuilds it: $mac"
            timeout 10 bluetoothctl disconnect "$mac" >/dev/null 2>&1
            dropped="$dropped $mac"
        done
        sleep 0.5
        ticks=$((ticks + 1))
    done

    # LE HOGP devices (the mouse) reconnect by themselves, and a sleeping one is
    # also not pageable, but a bounded attempt costs nothing and catches the case
    # where the device is awake and waiting.
    sleep 2
    for mac in $(down); do
        is_bredr_hid "$mac" && continue
        logger -t bt-resume "nudging $mac"
        timeout 8 bluetoothctl connect "$mac" >/dev/null 2>&1 &
    done
    wait
    logger -t bt-resume "resume recovery done"
    ;;
esac
EOF
    chmod 755 "$HOOK"
    echo "wrote $HOOK"
else
    echo "$HOOK already correct"
fi

echo "bluetooth resume hook installed"
