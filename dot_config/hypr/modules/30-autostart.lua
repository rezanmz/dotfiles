-- Autostart.
--
-- uwsm-managed services (waybar, hyprpaper, hypridle, cliphist, polkit agent)
-- are started by systemd user units at graphical-session.target, so they are
-- deliberately NOT duplicated here.

-- Thunderbird: launched into the special workspace "scratchpad" so that
-- SUPER+0 simply toggles it. The companion window rule lives in 70-rules.lua.
-- No --name flag: it would overwrite the window class and stop the rule in
-- 70-rules.lua from matching. Thunderbird already enforces a single instance
-- through its profile lock.
hl.on("hyprland.start", function()
    hl.exec_cmd("thunderbird")
end)
