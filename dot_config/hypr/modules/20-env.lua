-- Environment variables.
-- Session-scoped values (XDG_CURRENT_DESKTOP, WAYLAND_DISPLAY, ...) are set by
-- uwsm; only compositor-specific hints belong here.

-- Cursor theme. Keep in sync with dot_config/environment.d/60-desktop.conf,
-- which is what systemd user services (e.g. hyprpolkitagent) and uwsm read.
hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")
hl.env("XCURSOR_THEME", "Bibata-Modern-Classic")

-- Qt apps follow the GTK theme via libqgtk3.so (shipped by qt6), so
-- hyprpolkitagent and nwg-displays pick up Dracula without qt6ct or Kvantum.
hl.env("QT_QPA_PLATFORMTHEME", "gtk3")

-- Let Electron/Chromium-family apps pick the Wayland backend themselves.
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")

-- Firefox/Thunderbird Wayland backend and IM support.
hl.env("MOZ_ENABLE_WAYLAND", "1")
