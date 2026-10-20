-- Window, workspace and layer rules.

-- The shell's layer surfaces (quickshell). Same pair as before, for the same
-- reason: `blur` frosts whatever is behind a translucent surface, and
-- `ignore_alpha` (Hyprland's `ignorezero`) keeps that blur confined to the
-- pixels actually drawn instead of the whole layer surface, which would read as
-- the screen dimming.
--
-- The bar carries the same rgba(40,42,54,0.92) waybar had (Theme.qml), and the
-- notification stack uses the same translucent card, so both have something for
-- the blur to sample. The OSD is a small card over the desktop, which is the one
-- place a frosted look genuinely helps.
--
-- Namespaces are set by WlrLayershell.namespace in the shell's QML. The bar
-- panels (the drop-downs under the bar widgets) deliberately have no rule here:
-- they are xdg popups, not layer surfaces, so a layer rule cannot match them.
--
-- The launcher is not listed either: it draws a full-screen dim rectangle, and
-- with ignore_alpha that whole surface would be blurred — a full-screen blur on
-- an APU for no visual gain, since its card is nearly opaque.
hl.layer_rule({
    name         = "quickshell-bar-blur",
    match        = { namespace = "^quickshell-bar$" },
    blur         = true,
    ignore_alpha = true,
})

hl.layer_rule({
    name         = "quickshell-notifications-blur",
    match        = { namespace = "^quickshell-notifications$" },
    blur         = true,
    ignore_alpha = true,
})

hl.layer_rule({
    name         = "quickshell-pip-blur",
    match        = { namespace = "^quickshell-pip$" },
    blur         = true,
    ignore_alpha = true,
})

hl.layer_rule({
    name         = "quickshell-osd-blur",
    match        = { namespace = "^quickshell-osd$" },
    blur         = true,
    ignore_alpha = true,
})

-- The switcher overlay (quickshell). Same pair again: the overlay is a
-- translucent dim over the whole screen and the cards are drawn on top, so the
-- blur frosts the desktop behind and ignore_alpha keeps it confined to the drawn
-- pixels rather than the transparent parts of the surface.
--
-- This replaced snappy-switcher's rule; the namespace comes from
-- WlrLayershell.namespace in Switcher.qml.
hl.layer_rule({
    name         = "quickshell-switcher-blur",
    match        = { namespace = "^quickshell-switcher$" },
    blur         = true,
    ignore_alpha = true,
})

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

-- The workspace-to-panel split lives in 75-workspaces.lua, which computes it
-- from the connected monitors. There is deliberately no workspace rule here:
-- two places claiming the same workspace would fight over its binding.

-- Thunderbird belongs on workspace 10, which is a normal workspace (SUPER+0).
-- It is deliberately not floated or pinned: it behaves like any other window,
-- so it tiles normally and SUPER+0 switches to it exactly like SUPER+1..9.
hl.window_rule({
    name             = "thunderbird-workspace-10",
    match            = { class = "^org\\.mozilla\\.Thunderbird$" },
    workspace        = "10",
    -- Without these, mail starting at login drags the active workspace to 10,
    -- so the session begins on mail instead of workspace 1. Thunderbird
    -- activates itself on startup, so the "activate" request is suppressed too.
    no_initial_focus = true,
    suppress_event   = "activate",
})
