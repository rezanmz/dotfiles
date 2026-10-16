-- Window, workspace and layer rules.

-- anyrun (the launcher, which replaced rofi).
--
-- `blur` frosts whatever is behind the runner. On its own it also blurs the
-- transparent parts of the full-screen layer surface, which reads as the whole
-- screen dimming; `ignore_alpha` (Hyprland's `ignorezero`) restricts the blur
-- to pixels that are actually drawn, so only the card is frosted. Together they
-- are the pair the anyrun documentation recommends.
--
-- The card itself is translucent in style.css — an opaque background would give
-- the blur nothing to sample and it would appear to do nothing.
hl.layer_rule({
    name        = "anyrun-blur",
    match       = { namespace = "^anyrun$" },
    blur        = true,
    ignore_alpha = true,
})

-- hyprswitch (the SUPER+Tab window switcher). Same pair as anyrun above, for
-- the same reason: `blur` frosts the desktop behind the overview, and
-- `ignore_alpha` keeps that blur confined to the pixels actually drawn rather
-- than the whole full-screen layer surface.
--
-- The overview is the one place where frosted glass genuinely earns its keep —
-- it is a transient overlay you look *through* while deciding where to go, so
-- the windows behind should stay legible as shapes while being clearly
-- out-of-focus. style.css keeps the outer frame translucent (0.62 alpha) so
-- there is something for the blur to sample; an opaque frame would make this
-- rule a no-op.
hl.layer_rule({
    name        = "hyprswitch-blur",
    match       = { namespace = "^hyprswitch$" },
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
