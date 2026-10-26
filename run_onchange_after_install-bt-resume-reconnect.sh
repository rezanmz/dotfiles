#!/bin/sh
# Install a systemd sleep hook that restarts bluetoothd after resume.
#
# Why: this machine's xHCI controller (0000:0c:00.0) resets the Bluetooth
# controller on resume -- `xHC error in resume, USBSTS 0x401, Reinit` followed
# by "usb 1-6: reset" and a full BT firmware reload. bluetoothd survives that
# but keeps stale link state, so paired HID devices stay "Connected: yes" with
# no working input, or refuse to connect with le-connection-abort-by-local.
# Power-cycling the device by hand fixes it, which proves the link needs to be
# rebuilt from a clean HCI. Restarting bluetoothd after resume does that
# automatically; trusted devices reconnect on their own.
#
# Scope: resume from S3 only. Nothing here helps hibernation (S4), where the
# USB rail is off entirely.
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
if [ ! -f "$HOOK" ] || ! grep -q 'restart bluetooth.service' "$HOOK"; then
    cat >"$HOOK" <<'EOF'
#!/bin/sh
# Restart bluetoothd after resume.
#
# Installed by chezmoi: run_onchange_after_install-bt-resume-reconnect.sh
#
# The xHCI controller resets the Bluetooth controller on resume and the
# firmware is reloaded, which leaves bluetoothd holding link state that no
# longer exists. Input then stays dead until the device is power-cycled.
# A short delay lets usb re-enumeration finish before bluetoothd restarts.
case "$1" in
post)
    sleep 2
    systemctl --no-block restart bluetooth.service
    ;;
esac
EOF
    chmod 755 "$HOOK"
    echo "wrote $HOOK"
else
    echo "$HOOK already correct"
fi

echo "bluetooth resume hook installed"
