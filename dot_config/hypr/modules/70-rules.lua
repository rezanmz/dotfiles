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
    name         = "quickshell-osd-blur",
    match        = { namespace = "^quickshell-osd$" },
    blur         = true,
    ignore_alpha = true,
})

-- snappy-switcher (the SUPER+Tab window switcher). Same pair as anyrun above,
-- for the same reason: `blur` frosts the desktop behind the overview, and
-- `ignore_alpha` keeps that blur confined to the pixels actually drawn rather
-- than the whole full-screen layer surface.
--
-- The overview is the one place where frosted glass genuinely earns its keep —
-- it is a transient overlay you look *through* while deciding where to go, so
-- the windows behind should stay legible as shapes while being clearly
-- out-of-focus. The card fills are overridden to translucent values in
-- dot_config/snappy-switcher/config.ini for exactly this reason; a fully opaque
-- card would give the blur nothing to sample and make this rule a no-op.
--
-- The namespace is the layer-surface name baked into the snappy-switcher
-- binary, not the process or window title.
hl.layer_rule({
    name        = "snappy-switcher-blur",
    match       = { namespace = "^snappy-switcher$" },
    blur        = true,
    ignore_alpha = true,
})

-- The daemon is started from 30-autostart.lua, not here; a layer rule for a
-- surface that does not exist yet is harmless, but the ordering below the two
-- rules matters more than this comment.

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
    name             = "thunderbird-workspace-10",
    match            = { class = "^org\\.mozilla\\.Thunderbird$" },
    workspace        = "10",
    -- Without these, mail starting at login drags the active workspace to 10,
    -- so the session begins on mail instead of workspace 1. Thunderbird
    -- activates itself on startup, so the "activate" request is suppressed too.
    no_initial_focus = true,
    suppress_event   = "activate",
})
