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

-- Thunderbird belongs on workspace 10, which is a normal workspace (SUPER+0).
-- It is deliberately not floated or pinned: it behaves like any other window,
-- so it tiles normally and SUPER+0 switches to it exactly like SUPER+1..9.
hl.window_rule({
    name      = "thunderbird-workspace-10",
    match     = { class = "^org\\.mozilla\\.Thunderbird$" },
    workspace = "10",
})
