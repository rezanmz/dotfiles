-- Autostart.
--
-- hyprland.start is NOT the place for long-lived daemons. hl.exec_cmd sends
-- their stdout/stderr to /dev/null and nothing restarts them, so a daemon that
-- dies mid-session dies invisibly and forever. Anything that has to survive the
-- session belongs in a systemd user unit instead — see
-- dot_config/systemd/user/snappy-switcher.service for the shape. What is left
-- here is only what is genuinely fine being fire-and-forget.
--
-- uwsm-managed services (waybar, hyprpaper, hypridle, cliphist, polkit agent)
-- are started by systemd user units at graphical-session.target, so they are
-- deliberately NOT duplicated here.

-- Thunderbird starts at login and the rule in 70-rules.lua puts it on
-- workspace 10. It stays there quietly: switching there is just SUPER+0, like
-- any other workspace, so mail is always loaded and ready.
--
-- No --name flag: it would overwrite the window class and stop the workspace
-- rule from matching. Thunderbird already enforces a single instance through
-- its profile lock, so a manual launch just focuses the existing window.
hl.on("hyprland.start", function()
    hl.exec_cmd("thunderbird")
end)

-- anyrun daemon. The launcher itself is started on demand by the keybind, but
-- the daemon must be resident: without it every launch re-loads the plugins
-- from disk and the clipboard integration is unavailable, and anyrun prints a
-- warning to that effect. It also pre-initialises the GPU resources so the
-- first launch is not visibly slow.
--
-- Still an exec here rather than a unit: anyrun's daemon answers one launcher
-- prompt and holds no state worth recovering — if it is ever missing, the next
-- SUPER+SPACE starts it again. That is the test for whether something needs a
-- supervisor, and snappy-switcher (a resident IPC server) does not pass it.
hl.on("hyprland.start", function()
    hl.exec_cmd("anyrun daemon")
end)

-- snappy-switcher, the SUPER+Tab window switcher, runs as the systemd user unit
-- dot_config/systemd/user/snappy-switcher.service — see the note at the top of
-- this file for why. Nothing to do here; `systemctl --user status
-- snappy-switcher` is the thing to check when SUPER+Tab misbehaves.
