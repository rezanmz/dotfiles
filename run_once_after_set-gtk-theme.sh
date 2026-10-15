#!/bin/sh
# Apply the GTK/icon theme through dconf.
#
# Why this exists: gtk-3.0/settings.ini is NOT authoritative on a system running
# dconf. When dconf has a value for org.gnome.desktop.interface gtk-theme (which
# default installs do) it overrides settings.ini, and GTK resolves Adwaita no
# matter what the file says. Verified with:
#     python3 -c "import gi; gi.require_version('Gtk','3.0'); \\
#       from gi.repository import Gtk; print(Gtk.Settings.get_default().get_property('gtk-theme-name'))"
# which printed "Adwaita" while settings.ini said "Dracula".
#
# Both places are therefore set: settings.ini for toolkits that read it
# directly, dconf for everything that consults the settings daemon.
#
# Requires: dracula-gtk-theme and papirus-icon-theme installed.
# Re-run manually with: chezmoi state delete-bucket --bucket=scriptState

set -eu

if ! command -v gsettings >/dev/null 2>&1; then
    echo "gsettings not found; skipping GTK theme setup" >&2
    exit 0
fi

# Only touch values whose target theme is actually installed, so a machine
# without the packages degrades to "theme not applied" rather than a broken
# pointer to a missing theme.
if [ -d /usr/share/themes/Dracula ]; then
    gsettings set org.gnome.desktop.interface gtk-theme 'Dracula'
else
    echo "Dracula GTK theme not installed; leaving gtk-theme unchanged" >&2
fi

if [ -d /usr/share/icons/Papirus-Dark ]; then
    gsettings set org.gnome.desktop.interface icon-theme 'Papirus-Dark'
else
    echo "Papirus-Dark icons not installed; leaving icon-theme unchanged" >&2
fi

# prefer-dark makes GTK/libadwaita prefer dark variants, which is what stops
# apps like Thunderbird from rendering light when the theme's dark assets exist.
gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'

echo "GTK theme applied: $(gsettings get org.gnome.desktop.interface gtk-theme) / $(gsettings get org.gnome.desktop.interface color-scheme)"
