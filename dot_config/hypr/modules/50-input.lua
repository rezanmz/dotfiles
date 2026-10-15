-- Input: Keychron K8 Pro over USB/Bluetooth and a Logitech MX Master 3S.
-- No touchpad on this machine, so touchpad/gesture blocks are omitted.

hl.config({
    input = {
        -- Two layouts: US first, Persian second. Order matters beyond looks:
        -- Hyprland resolves keybinds against the FIRST layout, so with "us,ir"
        -- every bind in 60-binds.lua keeps matching plain Latin keys. Reversing
        -- this to "ir,us" would break them all.
        kb_layout  = "us,ir",
        -- The variant list is positional and must line up with kb_layout, hence
        -- the leading comma: US has no variant, Persian uses "winkeys".
        --
        -- "winkeys" (Persian, Windows-style) rather than plain "pes" because the
        -- digits stay Latin on the base layer; "pes" types Persian digits (۱-۹)
        -- by default, which is wrong for code, URLs and most terminals. winkeys
        -- still gives Persian digits on Shift and puts ZWNJ (U+200C, the
        -- half-space) on AltGr+2, which Persian writing needs constantly.
        kb_variant = ",winkeys",
        -- Ctrl+Space switches layouts. XKB handles this itself, so no Hyprland
        -- bind is needed or wanted; nothing in 60-binds.lua uses Ctrl+Space,
        -- and no IME daemon (fcitx/ibus) is installed to compete for it.
        --
        -- Caveat: XKB binds this to the Space key itself, so the toggle
        -- CONSUMES Ctrl+Space — editors that use it for completion or
        -- select-all-occurrences will not see the keypress. Space alone still
        -- types normally. To keep Ctrl+Space free in apps, use
        -- "grp:alt_shift_toggle" instead.
        kb_options = "grp:ctrl_space_toggle",
        kb_model   = "",
        kb_rules   = "",

        follow_mouse = 1,
        sensitivity  = 0,
    },
})

-- Mouse acceleration is off by default for the Logitech; if pointer feel is
-- wrong, add:
-- hl.device({ name = "logitech-mx-master-3s", accel_profile = "flat" })
