-- Hyprland configuration — entry point.
--
-- Module loading uses loadfile() with an absolute path rather than require():
-- Hyprland's Lua `require` resolves against the *current working directory*
-- (it looks for ./modules/...), so a config that requires submodules only works
-- when the compositor happens to be started from ~/.config/hypr. loadfile with
-- an explicit path is independent of CWD and of package.path.
--
-- Managed by chezmoi: source lives in ~/.local/share/chezmoi/dot_config/hypr.
-- Edit with `chezmoi edit ~/.config/hypr/hyprland.lua` and apply with
-- `chezmoi apply`, or edit the source directly.
--
-- Validate before applying (works from any directory):
--   Hyprland --verify-config -c ~/.config/hypr/hyprland.lua

local configDir = (os.getenv("XDG_CONFIG_HOME") or (os.getenv("HOME") .. "/.config")) .. "/hypr"
local modules = {
    "00-theme",     -- Dracula palette + dra() helper (globals used by later modules)
    "10-monitors",
    "20-env",
    "30-autostart",
    "40-look",
    "50-input",
    "60-binds",
    "70-rules",
    "75-workspaces", -- workspace partition across the panels
}

for _, name in ipairs(modules) do
    local path = configDir .. "/modules/" .. name .. ".lua"
    local chunk, err = loadfile(path)
    if not chunk then
        error("hyprland.lua: failed to load " .. path .. ": " .. tostring(err))
    end
    chunk()
end
