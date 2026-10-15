-- Input: Keychron K8 Pro over USB/Bluetooth and a Logitech MX Master 3S.
-- No touchpad on this machine, so touchpad/gesture blocks are omitted.

hl.config({
    input = {
        kb_layout  = "us",
        kb_variant = "",
        kb_model   = "",
        kb_options = "",
        kb_rules   = "",

        follow_mouse = 1,
        sensitivity  = 0,
    },
})

-- Mouse acceleration is off by default for the Logitech; if pointer feel is
-- wrong, add:
-- hl.device({ name = "logitech-mx-master-3s", accel_profile = "flat" })
