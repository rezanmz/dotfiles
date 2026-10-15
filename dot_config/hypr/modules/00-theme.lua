-- Dracula palette, shared by every module that needs a color.
-- Keep in sync with dot_config/kitty/kitty.conf, dot_config/alacritty and
-- dot_config/waybar/style.css.

DRA = {
    bg        = "282a36",
    fg        = "f8f8f2",
    selection = "44475a",
    comment   = "6272a4",
    cyan      = "8be9fd",
    green     = "50fa7b",
    orange    = "ffb86c",
    pink      = "ff79c6",
    purple    = "bd93f9",
    red       = "ff5555",
    yellow    = "f1fa8c",
}

-- Hyprland color strings are 8-digit hex inside rgba().
-- dra(DRA.purple)      -> "rgba(bd93f9ff)"
-- dra(DRA.purple, "99") -> "rgba(bd93f999)"
function dra(color, alpha)
    return "rgba(" .. color .. (alpha or "ff") .. ")"
end
