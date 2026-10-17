-- Autostart.
--
-- hyprland.start is NOT the place for long-lived daemons. hl.exec_cmd sends
-- their stdout/stderr to /dev/null and nothing restarts them, so a daemon that
-- dies mid-session dies invisibly and forever. Anything that has to survive the
-- session belongs in a systemd user unit instead — see
-- dot_config/systemd/user/snappy-switcher.service for the shape. What is left
-- here is only what is genuinely fine being fire-and-forget.
--
-- uwsm-managed services (quickshell, hyprpaper, hypridle, cliphist, polkit
-- agent) are started by systemd user units at graphical-session.target, so they
-- are deliberately NOT duplicated here.

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

-- The launcher is part of the shell now (dot_config/quickshell/Launcher.qml), so
-- there is nothing to start here: quickshell.service is the only process, and it
-- answers `qs ipc call launcher ...` from the keybinds.

-- snappy-switcher, the SUPER+Tab window switcher, runs as the systemd user unit
-- dot_config/systemd/user/snappy-switcher.service — see the note at the top of
-- this file for why. Nothing to do here; `systemctl --user status
-- snappy-switcher` is the thing to check when SUPER+Tab misbehaves.
