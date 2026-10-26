#!/bin/sh
# Install the udev rule that arms USB remote wakeup on the Bluetooth
# controller, so a Bluetooth keyboard or mouse can wake the machine from
# suspend (S3).
#
# Why a udev rule: the setting lives in /sys, is reset on every boot and
# every replug, and only root can change it. The controller (a MediaTek
# MT7922 on a Foxconn 0489:e0e2 device) already advertises USB Remote
# Wakeup, and BlueZ 5.87 already reports WakeAllowed=yes for the paired
# Keychron K8 Pro and MX Master 3S; the only missing piece was this flag,
# confirmed working by a suspend test on 2026-10-24 (pressing a BT key woke
# the machine out of S3).
#
# Scope: wake from S3 only. Hibernation (S4) powers down the USB rail, so
# nothing here can make Bluetooth wake the machine out of hibernate.
#
# Needs root. It runs non-interactively so `chezmoi apply` can never hang
# on a password prompt; if sudo is not passwordless it prints the command.
#
# Re-run: chezmoi state delete-bucket --bucket=scriptState

set -eu

if [ "$(uname -s)" != "Linux" ]; then
    echo "not Linux; skipping bluetooth wakeup install" >&2
    exit 0
fi

if [ "$(id -u)" -ne 0 ]; then
    if sudo -n true 2>/dev/null; then
        exec sudo -n "$0"
    fi
    echo "bluetooth wakeup not installed: sudo needs a password." >&2
    echo "Run this once as root (path is stable, not a temp copy):" >&2
    echo "    sudo $HOME/.local/share/chezmoi/run_onchange_after_install-bt-wakeup.sh" >&2
    exit 0
fi

# Matched on vendor:product, not the sysfs path: the USB port can move
# between ports/hubs, and the pair identifies the Foxconn/MT7922 combo
# uniquely on this machine. The ATTR{power/wakeup}="enabled" write is what
# arms the device's remote-wakeup; the kernel's own suspend path does the
# rest (it also enables the root hub and the xHCI controller).
#
# No power_control match: an earlier version required ATTR{power/control}
# =="auto" here, and after a power cycle the rule silently did not fire, so
# 1-6/power/wakeup stayed "disabled" and neither the keyboard nor the mouse
# could wake the machine. Writing the flag is harmless while the driver is
# still probing, so match on the vendor:product pair alone.
RULE=/etc/udev/rules.d/90-bluetooth-usb-wakeup.rules
if [ ! -f "$RULE" ] || ! grep -q 'ATTR{idProduct}=="e0e2", ATTR{power/wakeup}="enabled"' "$RULE"; then
    cat >"$RULE" <<'EOF'
# Let a Bluetooth keyboard or mouse wake the machine from suspend.
#
# Installed by chezmoi: run_onchange_after_install-bt-wakeup.sh
#
# MediaTek MT7922 (Foxconn 0489:e0e2) Bluetooth controller. The device
# advertises USB Remote Wakeup; arming power/wakeup is what makes usbcore
# honour it during system suspend. Wake from hibernation (S4) is not
# possible: the USB rail is off in S4.
ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="0489", ATTR{idProduct}=="e0e2", ATTR{power/wakeup}="enabled"
EOF
    chmod 644 "$RULE"
    echo "wrote $RULE"
else
    echo "$RULE already correct"
fi

# Apply to the live device without a reboot or a replug.
#
# "changed" means a rule matched and did its work, not merely that the
# process exited 0 — hence grep rather than exit status.
if [ "$(cat /sys/bus/usb/devices/1-6/power/wakeup 2>/dev/null)" = "enabled" ]; then
    echo "live device already armed"
else
    udevadm trigger --verbose --action=add /sys/bus/usb/devices/1-6 2>&1
    udevadm settle
    if [ "$(cat /sys/bus/usb/devices/1-6/power/wakeup 2>/dev/null)" = "enabled" ]; then
        echo "live device armed"
    else
        echo "rule did not take effect on the live device" >&2
        exit 1
    fi
fi

echo "bluetooth usb wakeup installed"
