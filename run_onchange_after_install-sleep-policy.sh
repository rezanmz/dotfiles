#!/bin/sh
# Install the sleep and hibernate policy for this desktop.
#
# Why this exists: the policy lives in /etc, which chezmoi does not manage
# (it only manages files under $HOME), so it was hand-written and would be
# lost on a reinstall. This script owns it.
#
# What it installs:
#
#   /etc/systemd/logind.conf.d/10-sleep-policy.conf
#       The power button suspends instead of powering off, and the hibernate
#       key suspends first and only writes RAM to disk if the machine is still
#       asleep after HibernateDelaySec.
#
#   /etc/systemd/sleep.conf.d/10-sleep-policy.conf
#       Suspend and hibernation are allowed, deep (S3) suspend is pinned, and
#       the suspend-then-hibernate delay is 45 minutes.
#
#   /etc/kernel/cmdline and /etc/default/grub
#       resume=UUID=<the disk swap>, so the kernel looks for a hibernation
#       image at boot. /etc/kernel/cmdline is the one that matters: mkinitcpio
#       embeds it into the UKI through the presets' ALL_cmdline, and the
#       kernel takes its command line from the UKI. The GRUB copy only
#       applies to the classic (non-UKI) entry path.
#
#   /etc/mkinitcpio.conf and /etc/mkinitcpio.d/*.preset
#       The `resume` hook, so the initramfs can restore that image, and
#       ALL_cmdline, so the UKI carries the command line above.
#
#   /etc/fstab
#       The disk swap is enabled at boot.
#
# The swap UUID is derived at run time from the actual swap device, never
# hardcoded here: this repository is public and the UUID is machine-specific.
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

# Machine-specific names, overridable from the environment. This is the
# volume group archinstall created; on another machine the script reuses
# whatever disk swap it already finds and only creates one when there is
# none at all.
VG=${SLEEP_POLICY_VG:-ArchinstallVg}
SWAP_LV=${SLEEP_POLICY_SWAP_LV:-swap}
SWAP_SIZE=${SLEEP_POLICY_SWAP_SIZE:-40G}

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

# --- 1. the disk swap -------------------------------------------------------
#
# Hibernation needs a swap device that is on disk: the whole of RAM is
# written to it. zram does not qualify, so it is skipped even though it is
# the machine's higher-priority swap.
swap_dev=""
swap_uuid=""
for dev in $(blkid -t TYPE=swap -o device 2>/dev/null || true); do
    case "$dev" in
        /dev/zram* | /dev/mapper/zram*) continue ;;
    esac
    swap_dev=$dev
    swap_uuid=$(blkid -s UUID -o value "$dev" 2>/dev/null || true)
    [ -n "$swap_uuid" ] && break
done

if [ -z "$swap_uuid" ]; then
    if ! vgs "$VG" >/dev/null 2>&1; then
        echo "no disk swap found and volume group $VG does not exist;" >&2
        echo "hibernation is not wired up" >&2
        exit 0
    fi
    lvcreate -L "$SWAP_SIZE" -n "$SWAP_LV" "$VG" >/dev/null
    mkswap "/dev/$VG/$SWAP_LV" >/dev/null
    swap_dev="/dev/$VG/$SWAP_LV"
    swap_uuid=$(blkid -s UUID -o value "$swap_dev")
    echo "created $swap_dev ($swap_uuid)"
fi

# The swap must be active for the hibernation image to land in it.
#
# swapon reports an active device under its kernel name (/dev/dm-1) while
# blkid reports it as /dev/mapper/<vg>-<lv>, so the names cannot be compared
# directly. Asking swapon to enable it and tolerating "busy" is the
# reliable test: "busy" means it is already on.
swapon_err=$(swapon "$swap_dev" 2>&1) || {
    case "$swapon_err" in
        *busy*)
            echo "$swap_dev is already active"
            ;;
        *)
            echo "could not enable $swap_dev: $swapon_err" >&2
            exit 1
            ;;
    esac
}

# --- 2. the policy drop-ins -------------------------------------------------
write_if_changed /etc/systemd/logind.conf.d/10-sleep-policy.conf <<'LOGIND'
# Sleep and power key policy for this desktop.
#
# Installed by chezmoi: run_onchange_after_install-sleep-policy.sh

[Login]
# The power button suspends instead of powering off. The previous default
# (poweroff) meant a stray press killed the session outright, with no lock
# and no warning.
#
# It is plain suspend, and that is deliberate: a power button press means
# "I am coming straight back", and a resume from RAM is ~1 s against ~15 s
# from a hibernation image.
#
# The long absences are handled by suspend-then-hibernate instead, which
# the idle timer and the launcher's "Sleep" row both use. Plain suspend
# holds RAM powered indefinitely, so a machine left for the afternoon would
# still have 30 GiB of RAM on standby when you came back.
HandlePowerKey=suspend

# A long press does nothing. The default is already "ignore"; stating it
# means no future default change can turn a held button into a power off.
HandlePowerKeyLongPress=ignore

# The lid switch is ignored: this is a tower, there is no lid, and the
# default (suspend) is dead configuration.
HandleLidSwitch=ignore

# The hibernate key goes straight to the chain. There is no hibernate key
# on this machine (nothing emits KEY_SLEEP), so this is only here for
# completeness and for a future keyboard that has one.
HandleHibernateKey=suspend-then-hibernate

# The suspend key suspends (unchanged from the default). This one is plain
# suspend, so it stays in RAM indefinitely.
HandleSuspendKey=suspend
LOGIND

write_if_changed /etc/systemd/sleep.conf.d/10-sleep-policy.conf <<'SLEEP'
# Sleep policy for this desktop.
#
# Installed by chezmoi: run_onchange_after_install-sleep-policy.sh

[Sleep]
# Suspend is allowed, and so is the suspend-then-hibernate chain. Both are
# the default, but they are stated here so the policy is in one place.
AllowSuspend=yes
AllowHibernation=yes
AllowSuspendThenHibernate=yes

# How long the machine stays suspended before it hibernates instead.
#
# systemd defaults to 2 hours on a machine with no battery. 45 minutes is
# long enough that a coffee break does not force a slow disk resume, and
# short enough that an overnight absence does not leave RAM powered.
HibernateDelaySec=45min

# Which sleep state to use. "mem" is S3 (deep): everything but RAM is
# powered down. The kernel already selects deep here on its own; naming it
# explicitly means it stays deep even if the kernel default changes.
SuspendState=mem

# Pin the in-RAM suspend mode to deep rather than s2idle. s2idle keeps the
# SoC alive in a low-power state, which draws more and resumes less
# reliably; deep cuts power to everything but RAM.
MemorySleepMode=deep
SLEEP

# --- 3. the kernel command line ---------------------------------------------
#
# resume= tells the kernel which swap device holds the hibernation image.
# Any stale resume= is removed first, so a changed swap cannot leave two of
# them behind and let the kernel pick the wrong one.
if ! grep -q "resume=UUID=$swap_uuid" /etc/kernel/cmdline 2>/dev/null; then
    sed -i 's| *resume=UUID=[^ ]*||g' /etc/kernel/cmdline
    sed -i "s|\$| resume=UUID=$swap_uuid|" /etc/kernel/cmdline
    need_initramfs=1
    echo "updated /etc/kernel/cmdline"
fi

# The same value for the classic GRUB entry path. This machine boots a UKI,
# so this line is not what the running kernel uses; it is kept so a
# non-UKI fallback entry would still be able to resume.
if ! grep -q "resume=UUID=$swap_uuid" /etc/default/grub 2>/dev/null; then
    # Strip any stale resume= first, then write the current one. The
    # trailing-space trim keeps the result from having a stray space inside
    # the quotes.
    sed -i 's| *resume=UUID=[^ "]*||g' /etc/default/grub
    if grep -q '^GRUB_CMDLINE_LINUX=' /etc/default/grub; then
        sed -i "s|^GRUB_CMDLINE_LINUX=\"\(.*\)\"|GRUB_CMDLINE_LINUX=\"\1 resume=UUID=$swap_uuid\"|" /etc/default/grub
        sed -i 's|^GRUB_CMDLINE_LINUX="[[:space:]]*|GRUB_CMDLINE_LINUX="|' /etc/default/grub
    else
        printf 'GRUB_CMDLINE_LINUX="resume=UUID=%s"\n' "$swap_uuid" >> /etc/default/grub
    fi
    grub-mkconfig -o /boot/grub/grub.cfg
    echo "updated /etc/default/grub"
fi

# --- 4. fstab ----------------------------------------------------------------
#
# The disk swap has to be enabled at boot, otherwise a hibernation image
# written before a reboot is never found. Priority 10 keeps zram (100) as
# the preferred swap for ordinary memory pressure; the hibernation image
# still goes to the disk swap, because that is what resume= names.
if ! grep -qE "^[^#]*[[:space:]]none[[:space:]]+swap" /etc/fstab; then
    printf 'UUID=%s none swap defaults,pri=10 0 0\n' "$swap_uuid" >> /etc/fstab
    echo "added the swap to /etc/fstab"
fi

# --- 5. the initramfs --------------------------------------------------------
#
# The `resume` hook is what restores the image: without it in the initramfs
# the kernel finds the swap device but nothing loads the image out of it.
if ! grep -qE '^HOOKS=.*\bresume\b' /etc/mkinitcpio.conf; then
    # The hook has to go INSIDE the parentheses: HOOKS=(... resume), not
    # HOOKS=(...) resume.
    sed -i 's|^HOOKS=(\([^)]*\))|HOOKS=(\1 resume)|' /etc/mkinitcpio.conf
    need_initramfs=1
    echo "added the resume hook to /etc/mkinitcpio.conf"
fi

# ALL_cmdline is what puts /etc/kernel/cmdline into the UKI. Without it the
# UKI carries the kernel's built-in command line, which has no resume=.
for preset in /etc/mkinitcpio.d/*.preset; do
    [ -f "$preset" ] || continue
    if ! grep -q "^ALL_cmdline=" "$preset"; then
        sed -i "1i ALL_cmdline='/etc/kernel/cmdline'" "$preset"
        need_initramfs=1
        echo "added ALL_cmdline to $preset"
    fi
done

# The initramfs has to be rebuilt for the new hook and command line to be
# in it. The UKI is rebuilt by the same pass.
if [ "$need_initramfs" -eq 1 ]; then
    mkinitcpio -P
    echo "rebuilt the initramfs and UKIs"
fi

# --- 6. apply the policy without a reboot ------------------------------------
#
# systemd-logind re-reads its configuration on reload, so the key handling
# takes effect immediately. The sleep policy is read when a sleep operation
# starts, so it needs no reload at all.
systemctl reload systemd-logind

echo "sleep policy installed (swap $swap_dev, uuid $swap_uuid)"
