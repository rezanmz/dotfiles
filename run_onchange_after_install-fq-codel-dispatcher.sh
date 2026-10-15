#!/bin/sh
# Install the fq_codel NetworkManager dispatcher script.
#
# Why this exists: saturating the link (a Steam download at ~430 Mbit/s) fills
# the queue and pushes round-trip latency to the LAN gateway from 6.8 ms idle
# to ~140 ms loaded. fq_codel keeps the queue short so interactive traffic is
# not stuck behind bulk transfers.
#
# Measured on this machine, ping to 192.168.1.1:
#     idle, 5 GHz, power save off ....... 4-14 ms
#     loaded, before fq_codel ........... 19-241 ms (avg 149)
#     loaded, after fq_codel ............ 9-226 ms (avg 139)
# The qdisc alone does NOT restore idle latency, because the bottleneck is the
# router's downstream queue, not this machine's transmit queue. Enabling SQM
# (fq_codel or CAKE) on the router is the other half of this fix.
#
# A NetworkManager dispatcher is used rather than a bare `tc` command because
# the qdisc is lost on every interface reset and reboot.
#
# Needs root. It runs non-interactively so `chezmoi apply` can never hang on a
# password prompt; if sudo is not passwordless it prints the command to run.
#
# Re-run: chezmoi state delete-bucket --bucket=scriptState

set -eu

DEST=/etc/NetworkManager/dispatcher.d/90-fq_codel

if [ "$(id -u)" -ne 0 ]; then
    if sudo -n true 2>/dev/null; then
        exec sudo -n "$0"
    fi
    echo "fq_codel dispatcher not installed: sudo needs a password." >&2
    echo "Run this once as root (path is stable, not a temp copy):" >&2
    echo "    sudo $HOME/.local/share/chezmoi/run_onchange_after_install-fq-codel-dispatcher.sh" >&2
    exit 0
fi

cat > "$DEST" <<'DISPATCHER'
#!/bin/sh
# Apply fq_codel to the Wi-Fi interface whenever a connection comes up.
#
# Why: saturating the link (a Steam download at ~430 Mbit/s) fills the queue and
# pushes round-trip latency to the LAN gateway from ~7 ms idle to ~140 ms loaded.
# fq_codel keeps the queue short so interactive traffic is not stuck behind bulk
# transfers.
#
# NetworkManager runs dispatchers as root, on every up/down, which makes this
# survive reboots and interface resets (a bare `tc qdisc` command does not).
# Scope is limited to wireless: wired links are rarely the bottleneck here.
#
# This does not fully restore idle latency while the link is saturated; the
# router's own queue is the outstanding bottleneck. See the README.

INTERFACE=$1
ACTION=$2

case "$ACTION" in
    up)
        case "$INTERFACE" in
            wl*)
                # target/interval suit Wi-Fi airtime scheduling; quantum 1514
                # matches a standard MTU.
                /usr/bin/tc qdisc replace dev "$INTERFACE" root fq_codel \
                    target 5ms interval 100ms quantum 1514 || exit 0
                logger -t nqm-fq_codel "applied fq_codel to $INTERFACE"
                ;;
        esac
        ;;
esac

exit 0
DISPATCHER

chmod 755 "$DEST"
echo "installed $DEST"
