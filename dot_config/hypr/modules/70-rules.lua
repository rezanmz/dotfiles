-- Window and workspace rules.

-- Suppress maximize requests: Hyprland's own fullscreen state is authoritative
-- and apps that force-maximize fight the tiler.
hl.window_rule({
    name  = "suppress-maximize-events",
    match = { class = ".*" },
    suppress_event = "maximize",
})

-- XWayland drag ghost windows: never focus them.
hl.window_rule({
    name  = "fix-xwayland-drags",
    match = {
        class      = "^$",
        title      = "^$",
        xwayland   = true,
        float      = true,
        fullscreen = false,
        pin        = false,
    },
    no_focus = true,
})

-- hyprland-run output window (used by `hyprctl dispatch exec` with rules).
hl.window_rule({
    name  = "move-hyprland-run",
    match = { class = "hyprland-run" },
    move  = "20 monitor_h-120",
    float = true,
})

-- Floating utility windows: dialogs stay centered and small.
hl.window_rule({
    name   = "center-dialogs",
    match  = { class = "^(xdg-desktop-portal-gtk|xdg-desktop-portal-hyprland)$" },
    float  = true,
    center = true,
    size   = "60% 60%",
})

-- Picture-in-picture and small video windows float.
hl.window_rule({
    name  = "float-pip",
    match = { title = "^(Picture-in-Picture)$" },
    float = true,
    pin   = true,
    size  = "30% 30%",
    move  = "100%-20 20",
})

-- Bluetui/htop-style TUIs launched into a scratch workspace behave normally, but
-- terminal file managers are plenty usable tiled.

-- Workspaces 1-4 belong to the single monitor; keep workspace 1 as the default
-- and let Hyprland manage the rest dynamically.
hl.workspace_rule({
    workspace = "1",
    default   = true,
})

-- Thunderbird on the special workspace ("scratchpad"), opened with SUPER+0 and
-- available on every workspace. Autostarted into workspace 0 by 30-autostart.lua
-- so the window already exists and SUPER+0 only has to toggle visibility.
hl.window_rule({
    name      = "thunderbird-scratchpad",
    match     = { class = "^(org\\.mozilla\\.Thunderbird|scratchpad-mail)$" },
    workspace = "special:scratchpad",
    float     = true,
    size      = { 1400, 1000 },
    center    = true,
    -- No `tile = true` here: it contradicts `float` and wins, which would make
    -- the mail window fill the screen instead of floating.
})
