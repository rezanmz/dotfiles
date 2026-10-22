#!/bin/sh
# Put amd-smi on PATH for every user and every kind of process.
#
# Why this exists: rocm-core ships /opt/rocm/bin/amd-smi plus
# /etc/profile.d/rocm.sh, and that snippet is only read by LOGIN shells. A
# terminal started from the compositor inherits the session's environment as it
# was captured at login, so `amd-smi` was not found there -- only the absolute
# path worked. A symlink in /usr/local/bin works for login shells, non-login
# shells, GUI processes and systemd units alike, because /usr/local/bin is in
# the default PATH for every account.
#
# Verified after install:
#     env -i PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
#         sh -c 'amd-smi version'
#
# The symlink is a symlink, not a wrapper on purpose: the CLI locates its own
# libexec directory from os.path.abspath(__file__) only in the ImportError
# fallback, and resolving through /opt/rocm/bin keeps __file__ inside the
# package tree either way.
#
# Needs root. It runs non-interactively so `chezmoi apply` can never hang on a
# password prompt; if sudo is not passwordless it prints the command to run.
#
# Re-run: chezmoi state delete-bucket --bucket=scriptState

set -eu

# Linux-only: /opt/rocm does not exist elsewhere.
if [ "$(uname -s)" != "Linux" ]; then
    echo "not Linux; skipping amd-smi symlink" >&2
    exit 0
fi

TARGET=/opt/rocm/bin/amd-smi
LINK=/usr/local/bin/amd-smi

# No ROCm on this machine: nothing to link.
if [ ! -e "$TARGET" ]; then
    echo "amd-smi not installed; skipping symlink" >&2
    exit 0
fi

if [ "$(id -u)" -ne 0 ]; then
    if [ -L "$LINK" ] && [ "$(readlink "$LINK")" = "$TARGET" ]; then
        exit 0
    fi
    if sudo -n true 2>/dev/null; then
        exec sudo -n "$0"
    fi
    echo "amd-smi symlink not created: sudo needs a password. Run:" >&2
    echo "    sudo ln -sfn $TARGET $LINK" >&2
    exit 0
fi

ln -sfn "$TARGET" "$LINK"
echo "linked $LINK -> $TARGET"
