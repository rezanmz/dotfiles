#!/bin/sh
set -eu

command -v picom >/dev/null 2>&1 || exit 0
uid=$(id -u)
if pgrep -u "$uid" -x picom >/dev/null 2>&1; then
  pkill -u "$uid" -x picom || true
fi
exec picom --config "$HOME/.config/picom/picom.conf" -b
