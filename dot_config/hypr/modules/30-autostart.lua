-- Autostart.
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
-- Not a systemd unit because the daemon is meaningless outside a graphical
-- session and anyrun owns its own lifetime.
hl.on("hyprland.start", function()
    hl.exec_cmd("anyrun daemon")
end)
