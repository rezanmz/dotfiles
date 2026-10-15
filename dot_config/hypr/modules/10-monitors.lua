-- Monitors: Dell U3225QE on HDMI-A-1.
-- The generic rule runs first and is then overridden by the specific one, so a
-- second/unknown display still gets a sane "preferred" mode.

hl.monitor({
    output   = "",
    mode     = "preferred",
    position = "auto",
    scale    = "auto",
})

hl.monitor({
    output   = "HDMI-A-1",
    mode     = "3840x2160@120",
    position = "0x0",
    scale    = 1,
})
