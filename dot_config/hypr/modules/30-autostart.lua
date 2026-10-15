-- Autostart.
-- uwsm-managed services (waybar, hyprpaper, hypridle, cliphist, polkit agent)
-- are started by systemd user units at graphical-session.target. Only things
-- that have no unit go here.

-- The session is launched as `Hyprland (uwsm-managed)`, so the units above are
-- enabled with `systemctl --user` instead of being duplicated here.
-- See README.md in the dotfiles for the enable list.
