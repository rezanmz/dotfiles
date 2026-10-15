-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
-- Managed by chezmoi — do not edit ~/.config/hypr/hyprland.lua directly.
-- Source: dot_config/hypr/hyprland.lua in the dotfiles repository.
--
-- Layout:
--   hyprland.lua          this entry point
--   modules/00-theme.lua  Dracula palette + dra() helper
--   modules/10-monitors   display modes
--   modules/20-env        environment variables
--   modules/30-autostart  (uwsm/systemd owns startup)
--   modules/40-look       gaps, borders, shadows, animations
--   modules/50-input      keyboard and mouse
--   modules/60-binds      keybindings
--   modules/70-rules      window and workspace rules
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

require("modules.00-theme")
require("modules.10-monitors")
require("modules.20-env")
require("modules.30-autostart")
require("modules.40-look")
require("modules.50-input")
require("modules.60-binds")
require("modules.70-rules")
