-- Keybindings.
-- SUPER is the main modifier, matching the i3 config this replaces.
--
--   SUPER+RETURN  terminal          SUPER+D  launcher
--   SUPER+SHIFT+D displays          SUPER+B  bluetooth
--   SUPER+Tab      window switcher
--   SUPER+Q       close window      SUPER+E  file manager
--   SUPER+L       lock              SUPER+M  exit menu
--   SUPER+1..0    workspaces        SUPER+SHIFT+1..0  move window to workspace
--   SUPER+S       scratchpad (magic)   SUPER+0  workspace 10 (mail)
--   SUPER+arrows / h j k l  focus  SUPER+SHIFT+...  move window
--   PRINT         region screenshot SUPER+SHIFT+PRINT  full screenshot

local mainMod = "SUPER"

local terminal    = "kitty"
-- The launcher opens on a clean prompt and reveals entries once you type. This
-- is per-invocation, NOT in fuzzel.ini: [main] would also hide the list for
-- every --dmenu helper (exit-menu, clipboard-pick, notif-history, dunst).
local launcher    = "fuzzel --hide-before-typing"
local fileManager = "kitty yazi"
local lockCmd     = "hyprlock"

local ipc     = "hyprctl dispatch"
local helpers = os.getenv("HOME") .. "/.local/bin"

-- Applications
hl.bind(mainMod .. " + RETURN", hl.dsp.exec_cmd(terminal))
hl.bind(mainMod .. " + D",      hl.dsp.exec_cmd(launcher))
hl.bind(mainMod .. " + E",      hl.dsp.exec_cmd(fileManager))
hl.bind(mainMod .. " + B",      hl.dsp.exec_cmd(terminal .. " -e bluetui"))
-- Window switcher: list open windows and focus the chosen one.
hl.bind(mainMod .. " + Tab", hl.dsp.exec_cmd(helpers .. "/window-switch"))
-- Display management GUI (scale, position, multi-monitor alignment).
hl.bind(mainMod .. " + SHIFT + D", hl.dsp.exec_cmd("nwg-displays"))

-- Session
hl.bind(mainMod .. " + Q", hl.dsp.window.close())
hl.bind(mainMod .. " + L", hl.dsp.exec_cmd(lockCmd))
hl.bind(mainMod .. " + M", hl.dsp.exec_cmd(helpers .. "/exit-menu"))
hl.bind(mainMod .. " + SHIFT + Q", hl.dsp.exit())

-- Window management
hl.bind(mainMod .. " + F",          hl.dsp.window.fullscreen({ mode = "fullscreen", action = "toggle" }))
hl.bind(mainMod .. " + SHIFT + F",  hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" }))
hl.bind(mainMod .. " + V",          hl.dsp.window.float({ action = "toggle" }))
hl.bind(mainMod .. " + P",          hl.dsp.window.pseudo())
hl.bind(mainMod .. " + J",          hl.dsp.layout("togglesplit"))
hl.bind(mainMod .. " + SHIFT + J",  hl.dsp.window.swap({ direction = "down" }))
hl.bind(mainMod .. " + SHIFT + K",  hl.dsp.window.swap({ direction = "up" }))

-- Focus
hl.bind(mainMod .. " + left",  hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + right", hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. " + up",    hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + down",  hl.dsp.focus({ direction = "down" }))
hl.bind(mainMod .. " + h",     hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + l",     hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. " + k",     hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + j",     hl.dsp.focus({ direction = "down" }))

-- Move windows
hl.bind(mainMod .. " + SHIFT + left",  hl.dsp.window.move({ direction = "left" }))
hl.bind(mainMod .. " + SHIFT + right", hl.dsp.window.move({ direction = "right" }))
hl.bind(mainMod .. " + SHIFT + up",    hl.dsp.window.move({ direction = "up" }))
hl.bind(mainMod .. " + SHIFT + down",  hl.dsp.window.move({ direction = "down" }))

-- Resize windows with the keyboard
hl.bind(mainMod .. " + CTRL + left",  hl.dsp.window.resize({ x = -40, y = 0, relative = true }), { repeating = true })
hl.bind(mainMod .. " + CTRL + right", hl.dsp.window.resize({ x = 40,  y = 0, relative = true }), { repeating = true })
hl.bind(mainMod .. " + CTRL + up",    hl.dsp.window.resize({ x = 0, y = -40, relative = true }), { repeating = true })
hl.bind(mainMod .. " + CTRL + down",  hl.dsp.window.resize({ x = 0, y = 40,  relative = true }), { repeating = true })

-- Workspaces
-- Workspaces 1-10. SUPER+0 reaches workspace 10, which is where mail lives.
-- Nothing special about it: it behaves exactly like 1-9.
for i = 1, 10 do
    local key = i % 10
    hl.bind(mainMod .. " + " .. key,         hl.dsp.focus({ workspace = i }))
    hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }))
end

hl.bind(mainMod .. " + S",         hl.dsp.workspace.toggle_special("magic"))
hl.bind(mainMod .. " + SHIFT + S", hl.dsp.window.move({ workspace = "special:magic" }))

hl.bind(mainMod .. " + C", hl.dsp.exec_cmd(helpers .. "/clipboard-pick"))
-- Cycle through workspaces with SUPER + scroll
hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mainMod .. " + mouse_up",   hl.dsp.focus({ workspace = "e-1" }))

-- Drag and resize with the mouse
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- Clipboard history (cliphist), fed by the cliphist systemd user unit
hl.bind(mainMod .. " + C", hl.dsp.exec_cmd(ipc .. " 'hl.dsp.exec_cmd(\"sh -c \\\"" .. helpers .. "/clipboard-pick\\\"\")'"))

-- Screenshots
hl.bind("PRINT",         hl.dsp.exec_cmd(helpers .. "/screenshot region"))
hl.bind(mainMod .. " + PRINT", hl.dsp.exec_cmd(helpers .. "/screenshot full"))
hl.bind(mainMod .. " + SHIFT + PRINT", hl.dsp.exec_cmd(helpers .. "/screenshot window"))

-- Media keys (Logitech MX Master and the Keychron consumer keys)
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),      { locked = true, repeating = true })
hl.bind("XF86AudioMute",        hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),     { locked = true, repeating = true })
hl.bind("XF86AudioMicMute",     hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),   { locked = true, repeating = true })
hl.bind("XF86AudioPlay",        hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPause",       hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioNext",        hl.dsp.exec_cmd("playerctl next"),       { locked = true })
hl.bind("XF86AudioPrev",        hl.dsp.exec_cmd("playerctl previous"),   { locked = true })

-- Utilities.
-- Notification history: fuzzel fed by dunst's history, newest first.
hl.bind(mainMod .. " + N", hl.dsp.exec_cmd(helpers .. "/notif-history"))
-- Colour picker (hyprpicker copies the picked colour to the clipboard).
hl.bind(mainMod .. " + SHIFT + P", hl.dsp.exec_cmd("hyprpicker --autocopy"))
-- Screen recording toggle.
-- wf-recorder: SUPER+SHIFT+R starts a region recording, pressing it again stops.
hl.bind(mainMod .. " + SHIFT + R", hl.dsp.exec_cmd(helpers .. "/record-toggle"))
