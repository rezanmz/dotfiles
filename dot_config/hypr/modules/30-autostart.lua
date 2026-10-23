-- Autostart.
--
-- hyprland.start is NOT the place for long-lived daemons. hl.exec_cmd sends
-- their stdout/stderr to /dev/null and nothing restarts them, so a daemon that
-- dies mid-session dies invisibly and forever. Anything that has to survive the
-- session belongs in a systemd user unit instead — see
-- dot_config/systemd/user/quickshell.service for the shape. What is left
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

-- Steam starts at login with no window (-silent: no main window, no splash).
-- It exists to do the work that needs the client running and signed in:
-- shader-cache deltas for installed games plus the fossilize replay that
-- validates them against the current Mesa build, Steam's own updates, and
-- queued game updates.
--
-- Why start it rather than launch it on demand: that replay is CPU-bound
-- (4 workers; ~20 min for CS2's 7.4 GB cache after a cache commit, ~1h when
-- both CS2 and Deadlock are redone after a Mesa upgrade), and a cache is only
-- picked up while the client runs. Started at login the cost lands while the
-- machine is otherwise idle; started when a game is wanted, the same cost
-- competes with playing.
--
-- No workspace is assigned on purpose -- nothing should appear: with -silent
-- there is no window, and opening the main window later is a deliberate action.
-- Steam enforces a single instance, so a manual `steam` focuses the running
-- client instead of starting a second one.
hl.on("hyprland.start", function()
    hl.exec_cmd("steam -silent")
end)

-- The launcher is part of the shell now (dot_config/quickshell/Launcher.qml), so
-- there is nothing to start here: quickshell.service is the only process, and it
-- answers `qs ipc call launcher ...` from the keybinds.

-- The SUPER+Tab switcher is part of the shell now (Switcher.qml), so there is no
-- daemon to supervise: quickshell.service is the only process involved, and
-- `systemctl --user status quickshell` is what to check when SUPER+Tab
-- misbehaves. snappy-switcher, its socket, its config and its unit are gone.
