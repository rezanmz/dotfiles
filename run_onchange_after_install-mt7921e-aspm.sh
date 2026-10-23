#!/bin/sh
# Install the mt7921e PCIe ASPM override for the Wi-Fi card.
#
# Why this exists: the Wi-Fi card is a MediaTek MT7922 (driver mt7921e) on a
# PCIe 2.0 x1 link with ASPM L1 enabled by default
# (/sys/bus/pci/devices/0000:0b:00.0/link/l1_aspm = 1, pcie_aspm policy
# "default", module parameter disable_aspm = N). L1 entry/exit latency can stall
# the card for tens to hundreds of milliseconds, which presents exactly like
# "network jitter" in online games:
#
#   first hop (192.168.1.1)   2-4 ms median  ->  25-100 ms median
#   first hop p99 / max                     ->  207 / 539 ms
#   packet loss                             ->  0 %
#   RSSI, TX/RX rate, retries               ->  unchanged
#   loopback (127.0.0.1)                    ->  clean (no host stall)
#
# The same signature also fits airtime contention on the AP, so this is a
# hypothesis under test, not a proven fix. It is installed because it is the
# cheapest test that isolates the card: measure before/after with
#   ping -c 1800 -i 0.1 -D 192.168.1.1
# and compare per-second medians and maxima. If the spikes survive, revert this
# and treat the AP's airtime as the suspect.
#
# What it installs:
#
#   /etc/modprobe.d/mt7921e-aspm.conf
#       options mt7921e disable_aspm=1
#
# Takes effect on the next module load: reboot, or
#   sudo modprobe -r mt7921e && sudo modprobe mt7921e
# which drops Wi-Fi for a few seconds. Verify with
#   cat /sys/module/mt7921e/parameters/disable_aspm    # expect Y
#   cat /sys/bus/pci/devices/0000:0b:00:0/link/l1_aspm # expect 0
#
# Needs root. It runs non-interactively so `chezmoi apply` can never hang on a
# password prompt; if sudo is not passwordless it prints the command to run.
#
# Re-run: chezmoi state delete-bucket --bucket=scriptState

set -eu

# Linux-only: the module and its parameter do not exist on macOS.
if [ "$(uname -s)" != "Linux" ]; then
    echo "not Linux; skipping mt7921e ASPM override" >&2
    exit 0
fi

DEST=/etc/modprobe.d/mt7921e-aspm.conf

if [ "$(id -u)" -ne 0 ]; then
    if sudo -n true 2>/dev/null; then
        exec sudo -n "$0"
    fi
    echo "mt7921e ASPM override not installed: sudo needs a password." >&2
    echo "Run this once as root (path is stable, not a temp copy):" >&2
    echo "    sudo $HOME/.local/share/chezmoi/run_onchange_after_install-mt7921e-aspm.sh" >&2
    exit 0
fi

cat > "$DEST" <<'CONF'
# Keep the MT7922's PCIe link out of ASPM L1. L1 exit latency stalls the card
# and shows up as multi-hundred-millisecond latency spikes on the first hop with
# no packet loss and no change in link rate. See
# run_onchange_after_install-mt7921e-aspm.sh in the dotfiles repo.
options mt7921e disable_aspm=1
CONF

chmod 644 "$DEST"
echo "installed $DEST"
