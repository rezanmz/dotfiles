#!/bin/sh
# Install the sleep policy for this desktop.
#
# Why this exists: the policy lives in /etc, which chezmoi does not manage
# (it only manages files under $HOME), so it was hand-written and would be
# lost on a reinstall. This script owns it.
#
# The policy is plain suspend to RAM (S3). There is no hibernation and no
# suspend-then-hibernate: the machine accepts the risk of losing the session
# to a power cut or a bit flip in DRAM, in exchange for a one-second resume
# and no disk swap.
#
# What it installs:
#
#   /etc/systemd/logind.conf.d/10-sleep-policy.conf
#       The power button and the suspend key suspend to RAM; nothing is
#       allowed to hibernate.
#
#   /etc/systemd/sleep.conf.d/10-sleep-policy.conf
#       Hibernation and the suspend-then-hibernate chain are refused, and
#       deep (S3) suspend is pinned.
#
#   /etc/kernel/cmdline and /etc/default/grub
#       Any leftover resume= is removed. Nothing restores an image, and a
#       stale resume= only delays the boot.
#
#   /etc/mkinitcpio.conf and /etc/mkinitcpio.d/*.preset
#       The `resume` hook is removed; ALL_cmdline is kept so the UKI still
#       carries /etc/kernel/cmdline.
#
#   /etc/fstab
#       The disk swap line is removed and the swap LV is deleted. zram
#       (/etc/systemd/zram-generator.conf) is the whole swap on this
#       machine; a disk swap would only be a device to forget about.
#       Opt out with SLEEP_POLICY_DELETE_SWAP=0 to keep the LV.
#
# Needs root. It runs non-interactively so `chezmoi apply` can never hang on
# a password prompt; if sudo is not passwordless it prints the command to run.
#
# Re-run: chezmoi state delete-bucket --bucket=scriptState

set -eu

# Linux desktop configuration: /etc/systemd does not exist on macOS.
if [ "$(uname -s)" != "Linux" ]; then
    echo "not Linux; skipping sleep policy install" >&2
    exit 0
fi

if [ "$(id -u)" -ne 0 ]; then
    if sudo -n true 2>/dev/null; then
        exec sudo -n "$0"
    fi
    echo "sleep policy not installed: sudo needs a password." >&2
    echo "Run this once as root (path is stable, not a temp copy):" >&2
    echo "    sudo $HOME/.local/share/chezmoi/run_onchange_after_install-sleep-policy.sh" >&2
    exit 0
fi

# Set when something changed that requires the initramfs to be rebuilt.
need_initramfs=0

# Write a file only when its content differs, so repeated runs do not churn
# mtimes or trigger needless rebuilds.
write_if_changed() {
    dest=$1
    tmp=$(mktemp)
    cat >"$tmp"
    if [ -f "$dest" ] && cmp -s "$tmp" "$dest"; then
        rm -f "$tmp"
        return 0
    fi
    mkdir -p "$(dirname "$dest")"
    cp "$tmp" "$dest"
    chmod 644 "$dest"
    rm -f "$tmp"
    echo "wrote $dest"
}

# --- 1. the policy drop-ins -------------------------------------------------
write_if_changed /etc/systemd/logind.conf.d/10-sleep-policy.conf <<'LOGIND'
# Sleep and power key policy for this desktop.
#
# Installed by chezmoi: run_onchange_after_install-sleep-policy.sh

[Login]
# The power button suspends to RAM instead of powering off. The previous
# default (poweroff) meant a stray press killed the session outright, with no
# lock and no warning.
#
# It is plain suspend (S3), not suspend-then-hibernate. The chain was removed
# on purpose: the machine holds RAM on standby until it is woken, and if the
# power goes out the session is lost. That trade is accepted — a ~1 s resume
# from RAM, and no disk swap and no hibernation image to carry around.
HandlePowerKey=suspend

# A long press does nothing. The default is already "ignore"; stating it
# means no future default change can turn a held button into a power off.
HandlePowerKeyLongPress=ignore

# The lid switch is ignored: this is a tower, there is no lid, and the
# default (suspend) is dead configuration.
HandleLidSwitch=ignore

# Nothing hibernates. There is no hibernation target (no disk swap) and no
# hibernate key on this machine (nothing emits KEY_SLEEP); this line is what
# stops a future keyboard, or a stray loginctl call, from asking for one.
HandleHibernateKey=ignore

# The suspend key suspends, for the same reason as the power button.
HandleSuspendKey=suspend
LOGIND

write_if_changed /etc/systemd/sleep.conf.d/10-sleep-policy.conf <<'SLEEP'
# Sleep policy for this desktop.
#
# Installed by chezmoi: run_onchange_after_install-sleep-policy.sh

[Sleep]
# Suspend to RAM only. Both hibernation forms are refused, so no path into
# sleep can try to write RAM to a swap device that no longer exists.
AllowSuspend=yes
AllowHibernation=no
AllowSuspendThenHibernate=no

# Which sleep state to use. "mem" is S3 (deep): everything but RAM is
# powered down. The kernel already selects deep here on its own; naming it
# explicitly means it stays deep even if the kernel default changes.
SuspendState=mem

# Pin the in-RAM suspend mode to deep rather than s2idle. s2idle keeps the
# SoC alive in a low-power state, which draws more and resumes less
# reliably; deep cuts power to everything but RAM.
MemorySleepMode=deep
SLEEP

# --- 2. leftover hibernation wiring -----------------------------------------
#
# resume= names the swap device that holds a hibernation image. There is no
# image any more, and a resume= pointing at a deleted LV makes the boot log
# an error and gives up. /etc/kernel/cmdline is the one that matters: the
# presets' ALL_cmdline makes mkinitcpio embed it into the UKI, and the kernel
# takes its command line from the UKI.
if grep -q 'resume=' /etc/kernel/cmdline 2>/dev/null; then
    sed -i 's| *resume=[^ ]*||g' /etc/kernel/cmdline
    need_initramfs=1
    echo "removed resume= from /etc/kernel/cmdline"
fi

# The same value for the classic GRUB entry path. This machine boots a UKI,
# so this copy only covers a non-UKI fallback entry.
if grep -q 'resume=' /etc/default/grub 2>/dev/null; then
    sed -i 's| *resume=[^ "]*||g' /etc/default/grub
    grub-mkconfig -o /boot/grub/grub.cfg
    echo "removed resume= from /etc/default/grub"
fi

# The `resume` hook loads the image out of the swap device in the initramfs.
# Nothing does that any more. The substitution is restricted to the HOOKS
# line: the word also appears in the comments of the stock file.
if grep -qE '^HOOKS=.*(^|[[:space:]])resume([[:space:]]|\)|$)' /etc/mkinitcpio.conf; then
    sed -i '/^HOOKS=/s|[[:space:]]*\<resume\>||' /etc/mkinitcpio.conf
    need_initramfs=1
    echo "removed the resume hook from /etc/mkinitcpio.conf"
fi

# ALL_cmdline is what puts /etc/kernel/cmdline into the UKI. Without it the
# UKI carries the kernel's built-in command line.
for preset in /etc/mkinitcpio.d/*.preset; do
    [ -f "$preset" ] || continue
    if ! grep -q "^ALL_cmdline=" "$preset"; then
        sed -i "1i ALL_cmdline='/etc/kernel/cmdline'" "$preset"
        need_initramfs=1
        echo "added ALL_cmdline to $preset"
    fi
done

# --- 3. fstab ---------------------------------------------------------------
#
# A swap line only existed to enable the hibernation image at boot. zram is
# enabled by systemd-zram-setup, not by fstab, so removing this line leaves
# the machine with exactly one swap device.
if grep -qE '^[[:space:]]*[^#].*[[:space:]]none[[:space:]]+swap[[:space:]]' /etc/fstab; then
    sed -i -E '/^[[:space:]]*#/!{/[[:space:]]none[[:space:]]+swap[[:space:]]/d}' /etc/fstab
    echo "removed the disk swap line from /etc/fstab"
fi

# --- 4. the disk swap LV ----------------------------------------------------
#
# Nothing needs a disk-backed swap once hibernation is gone. Deleting the LV
# hands its space back to the volume group; on this machine that is 40 GiB.
# `swapoff` is best-effort: a device that is not active is already the goal.
if [ "${SLEEP_POLICY_DELETE_SWAP:-1}" = 1 ]; then
    for dev in $(blkid -t TYPE=swap -o device 2>/dev/null || true); do
        case "$dev" in
            /dev/zram* | /dev/mapper/zram*) continue ;;
        esac
        swapoff "$dev" 2>/dev/null || true
        read -r vg name <<EOF
$(lvs --noheadings -o vg_name,lv_name "$dev" 2>/dev/null | sed 's/^[[:space:]]*//')
EOF
        if [ -n "${vg:-}" ] && [ -n "${name:-}" ]; then
            lvremove -y "$vg/$name" >/dev/null
            echo "deleted the disk swap LV $vg/$name ($dev)"
        else
            echo "left $dev alone: it is not an LVM swap device" >&2
        fi
    done
fi

# The initramfs has to be rebuilt for the new hook and command line to be
# in it. The UKI is rebuilt by the same pass.
if [ "$need_initramfs" -eq 1 ]; then
    mkinitcpio -P
    echo "rebuilt the initramfs and UKIs"
fi

# --- 5. apply the policy without a reboot ------------------------------------
#
# systemd-logind re-reads its configuration on reload, so the key handling
# takes effect immediately. The sleep policy is read when a sleep operation
# starts, so it needs no reload at all.
systemctl reload systemd-logind

echo "sleep policy installed: suspend only, no hibernation, no disk swap"
