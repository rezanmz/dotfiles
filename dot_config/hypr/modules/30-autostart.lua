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
