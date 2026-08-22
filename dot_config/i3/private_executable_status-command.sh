#!/bin/sh
set -eu

config="$HOME/.config/i3status-rust/config.toml"
if command -v i3status-rs >/dev/null 2>&1 && [ -f "$config" ]; then
  # Fall through if the optional Rust implementation exits immediately.
  i3status-rs "$config" && exit 0
fi

if command -v i3status >/dev/null 2>&1; then
  exec i3status
fi

# Keep i3bar alive with an explicit, non-sensitive status when neither backend exists.
printf '%s\n' '{"version":1}' '['
while :; do
  printf '%s\n' '[{"full_text":"i3status unavailable"}],'
  sleep 60
done
