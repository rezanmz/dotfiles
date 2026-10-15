-- Environment variables.
-- Session-scoped values (XDG_CURRENT_DESKTOP, WAYLAND_DISPLAY, ...) are set by
-- uwsm; only compositor-specific hints belong here.

hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")
hl.env("XCURSOR_THEME", "Adwaita")

-- Let Electron/Chromium-family apps pick the Wayland backend themselves.
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")

-- Firefox/Thunderbird Wayland backend and IM support.
hl.env("MOZ_ENABLE_WAYLAND", "1")
