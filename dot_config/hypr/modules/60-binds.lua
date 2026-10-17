-- Keybindings.
-- SUPER is the main modifier, matching the i3 config this replaces.
--
--   SUPER+RETURN  terminal          SUPER+SPACE  unified menu
--   SUPER+SHIFT+D displays          SUPER+B  bluetooth
--   SUPER+Tab      window switcher (hyprswitch, hold and release)
--   SUPER+Q twice close window (confirm)   SUPER+E  file manager
--   SUPER+L       lock
--   SUPER+1..0    workspaces        SUPER+SHIFT+1..0  move window to workspace
--   SUPER+S       scratchpad (magic)   SUPER+0  workspace 10 (mail)
--   SUPER+arrows / h j k l  focus  SUPER+SHIFT+...  move window
--   PRINT         region screenshot SUPER+SHIFT+PRINT  full screenshot

local mainMod = "SUPER"

local terminal    = "kitty"
-- The unified menu: applications, calculator, symbols, web search and session
-- actions in ONE prompt. anyrun merges every plugin listed in config.ron, so
-- typing "firefox" launches it, "7*6" answers 42, "lock" offers the action and
-- "?hyprland" opens a browser search. This replaced rofi (and fuzzel before it);
-- rofi-calc could not evaluate inside rofi's combi mode, which is what made the
-- old setup need a separate entry to reach the calculator.
local launcher    = "anyrun"
local fileManager = "kitty yazi"
local lockCmd     = "hyprlock"

local ipc     = "hyprctl dispatch"
local helpers = os.getenv("HOME") .. "/.local/bin"

-- Applications
hl.bind(mainMod .. " + RETURN", hl.dsp.exec_cmd(terminal))
hl.bind(mainMod .. " + E",      hl.dsp.exec_cmd(fileManager))
hl.bind(mainMod .. " + B",      hl.dsp.exec_cmd(terminal .. " -e bluetui"))
-- Window switcher: hold-and-release, the Alt-Tab muscle memory.
--
-- OPTIONS, and why each one is here:
--
-- --switch-type workspace
--     TAB steps through WORKSPACES, not individual windows. With the default
--     (client) a single TAB can land on another window that looks identical —
--     this machine usually has two kitty windows open, so "one tab then release"
--     appeared to do nothing. Stepping by workspace makes every step a visible
--     change, and matches the SUPER+1..0 workspace keys right below.
--
-- --include-special-workspaces
--     The "magic" scratchpad (SUPER+S) is otherwise invisible to the switcher,
--     which means a window parked there could never be reached from SUPER+Tab.
--
-- --max-switch-offset 9
--     Number badges 1..9. The default of 6 cannot address a 7th+ entry, and
--     this setup regularly has more than six workspaces worth of windows.

--
-- Hold SUPER and tap TAB to step through windows; release SUPER to switch to
-- the highlighted one (or press Escape to abort). Shift+TAB steps backwards.
--
-- `--mod-key SUPER_L`, NOT `SUPER`. This is subtle and was a real bug here:
-- hyprswitch builds the submap with two different uses of the mod key. The
-- CYCLE binds go through get_mod_from_mod_key(), which maps both SuperL and
-- SuperR to the generic "SUPER" — so cycling works either way. But the
-- RELEASE bind is generated from the literal string: bind(main_mod,
-- mod_key.to_string(), "hyprswitch close", release=true). Passing "SUPER"
-- therefore registers a release bind for a key name Hyprland never reports
-- (the real key is SUPER_L), so letting go of Super did nothing the first
-- time — the submap stayed open and only closed on the next attempt. Upstream
-- issue #5 is exactly this, fixed by using the physical key name.
--
-- `--close mod-key-release` is the other load-bearing flag: hyprswitch defaults
-- to `--close default`, which requires pressing Enter to commit — the opposite
-- of the behaviour wanted here. Release-to-switch works at all because the
-- submap binds carry `release = true`.
--
-- WHY NOT ANYRUN ANY MORE
-- The previous switcher was `anyrun --plugins libstdin.so`. anyrun's window is a
-- layer-shell surface with keyboard_mode=Exclusive, so it grabs the keyboard and
-- Hyprland stops seeing modifier keys — the SUPER release is unobservable, and
-- no anyrun option changes that. The tradeoff accepted here: hyprswitch has no
-- text input, so typed fuzzy window search on this chord is gone. SUPER+SPACE
-- remains the unified menu.
--
hl.bind(mainMod .. " + Tab", hl.dsp.exec_cmd(
    "hyprswitch gui"
    .. " --mod-key SUPER_L --key TAB"
    .. " --close mod-key-release --reverse-key mod=shift"
    .. " --switch-type workspace"
    .. " --include-special-workspaces"
    .. " --max-switch-offset 9"
))
-- Display management GUI (scale, position, multi-monitor alignment).
hl.bind(mainMod .. " + SHIFT + D", hl.dsp.exec_cmd("nwg-displays"))
--
-- The unified menu has EXACTLY ONE chord: SUPER+SPACE, the Spotlight habit.
--
-- SUPER+D and SUPER+M deliberately carry no launcher binding. SUPER+D used to
-- be a second launcher chord and SUPER+M opened an actions-only anyrun run
-- (anysrun --plugins libactions.so); both were dropped because a single entry
-- point is less to remember, and nothing is lost by it: the power actions are
-- already in config.ron's plugin list, so typing "reboot" or "lock" from the
-- one menu reaches them directly. SUPER+D and SUPER+M are therefore free for
-- anything else.
hl.bind(mainMod .. " + SPACE", hl.dsp.exec_cmd(launcher))

-- Session
--
-- Closing a window is the one bind here that destroys work, so it asks first.
--
-- A single SUPER+Q used to kill the focused window on the spot, which made one
-- mis-press cost the whole window. SUPER+Q now arms a confirmation instead: the
-- first press names the window in a toast, a second SUPER+Q on that same window
-- within CLOSE_CONFIRM_MS closes it, and anything else — waiting the toast out,
-- moving focus, closing the window some other way — drops the request.
--
-- Deliberately NOT a confirm submap. While a submap is active every keybind
-- that is not `submap_universal` stops matching, so a stray SUPER+Q would take
-- the whole SUPER layer offline until the submap is left again — the cure would
-- be worse than the disease. Keeping the pending state in plain Lua upvalues
-- leaves every other bind working and needs no escape hatch: doing nothing is
-- the cancel.
--
-- The address is captured at arm time and re-checked at confirm time, so
-- SUPER+Q SUPER+Q can only ever close the window the toast named. If focus
-- moved in between, the second press just re-arms for the window now in front
-- instead of closing something the user is no longer looking at.

local CLOSE_CONFIRM_MS = 3000

-- Pending confirmation: the window it aims at (by address, so it does not
-- depend on a stale window object), the toast advertising it, and a sequence
-- number so a lapsed timer can tell a live arm from one it no longer owns.
local closeArmed  = nil
local closeArmSeq = 0

local function closeArmCancel()
    if not closeArmed then
        return
    end

    if closeArmed.toast then
        closeArmed.toast:dismiss()
    end

    closeArmed = nil
end

local function closeArmLabel(win)
    local label = win.title
    if label == nil or label == "" then
        label = win.class
    end
    if label == nil or label == "" then
        return "this window"
    end

    -- The overlay renders a single unwrapped line, so a long title would run
    -- off the screen edge; cut it on a character boundary, not a byte one.
    local cut = utf8.offset(label, 41)
    if cut then
        label = label:sub(1, cut - 1) .. "…"
    end

    return label
end

-- Close the focused window, but only if the same window was already named by
-- a SUPER+Q press within the last CLOSE_CONFIRM_MS.
local function closeWithConfirm()
    local win = hl.get_active_window()
    if not win then
        return
    end

    if closeArmed and closeArmed.address == win.address then
        local target = closeArmed.address

        closeArmCancel()
        -- Close by the address captured at arm time rather than "the active
        -- window": the toast promised one specific window, and this cannot
        -- drift onto a different one if focus moves before the dispatch runs.
        hl.dispatch(hl.dsp.window.close({ window = "address:" .. target }))
        return
    end

    -- Anything else arms a fresh confirmation for the window in front: the
    -- very first press, a different window, or a toast whose time already ran
    -- out. Re-arming is also the "no" path — nothing has to be pressed to
    -- abort, the request simply expires.
    closeArmCancel()

    closeArmSeq = closeArmSeq + 1
    local seq   = closeArmSeq

    closeArmed = {
        address = win.address,
        seq     = seq,
        toast   = hl.notification.create({
            text     = ("Close %s? Press SUPER+Q again to confirm"):format(closeArmLabel(win)),
            duration = CLOSE_CONFIRM_MS,
            icon     = "warning",
            color    = dra(DRA.yellow),
        }),
    }

    -- One timer per press, left to fire rather than cancelled early. A oneshot
    -- timer is unref'd and dropped by the config manager once it runs, whereas
    -- disabling it would strand the handle in its timer table until the next
    -- reload; and `set_enabled` cannot be called at config load time at all —
    -- it dereferences an event loop manager that does not exist yet under
    -- `--verify-config`, which crashes the verifier. A stale timer instead
    -- compares its sequence number against the live arm and does nothing.
    hl.timer(function()
        if closeArmed and closeArmed.seq == seq then
            closeArmCancel()
        end
    end, { timeout = CLOSE_CONFIRM_MS, type = "oneshot" })
end

hl.bind(mainMod .. " + Q", closeWithConfirm)

hl.bind(mainMod .. " + L", hl.dsp.exec_cmd(lockCmd))
-- SUPER+M is intentionally unbound. It used to open an actions-only anyrun run;
-- those actions are in the unified menu now, so the chord is free.
hl.bind(mainMod .. " + SHIFT + Q", hl.dsp.exit())

-- Window management
hl.bind(mainMod .. " + F",          hl.dsp.window.fullscreen({ mode = "fullscreen", action = "toggle" }))
hl.bind(mainMod .. " + SHIFT + F",  hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" }))
hl.bind(mainMod .. " + V",          hl.dsp.window.float({ action = "toggle" }))
hl.bind(mainMod .. " + P",          hl.dsp.window.pseudo())
hl.bind(mainMod .. " + J",          hl.dsp.layout("togglesplit"))
hl.bind(mainMod .. " + SHIFT + J",  hl.dsp.window.swap({ direction = "down" }))
hl.bind(mainMod .. " + SHIFT + K",  hl.dsp.window.swap({ direction = "up" }))

-- Focus
hl.bind(mainMod .. " + left",  hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + right", hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. " + up",    hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + down",  hl.dsp.focus({ direction = "down" }))
hl.bind(mainMod .. " + h",     hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + l",     hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. " + k",     hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + j",     hl.dsp.focus({ direction = "down" }))

-- Move windows
hl.bind(mainMod .. " + SHIFT + left",  hl.dsp.window.move({ direction = "left" }))
hl.bind(mainMod .. " + SHIFT + right", hl.dsp.window.move({ direction = "right" }))
hl.bind(mainMod .. " + SHIFT + up",    hl.dsp.window.move({ direction = "up" }))
hl.bind(mainMod .. " + SHIFT + down",  hl.dsp.window.move({ direction = "down" }))

-- Resize windows with the keyboard
hl.bind(mainMod .. " + CTRL + left",  hl.dsp.window.resize({ x = -40, y = 0, relative = true }), { repeating = true })
hl.bind(mainMod .. " + CTRL + right", hl.dsp.window.resize({ x = 40,  y = 0, relative = true }), { repeating = true })
hl.bind(mainMod .. " + CTRL + up",    hl.dsp.window.resize({ x = 0, y = -40, relative = true }), { repeating = true })
hl.bind(mainMod .. " + CTRL + down",  hl.dsp.window.resize({ x = 0, y = 40,  relative = true }), { repeating = true })

-- Workspaces
-- Workspaces 1-10. SUPER+0 reaches workspace 10, which is where mail lives.
-- Nothing special about it: it behaves exactly like 1-9.
for i = 1, 10 do
    local key = i % 10
    hl.bind(mainMod .. " + " .. key,         hl.dsp.focus({ workspace = i }))
    hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }))
end

hl.bind(mainMod .. " + S",         hl.dsp.workspace.toggle_special("magic"))
hl.bind(mainMod .. " + SHIFT + S", hl.dsp.window.move({ workspace = "special:magic" }))

-- Clipboard history (cliphist), fed by the cliphist systemd user unit.
-- One bind only: the old config had a second identical chord routing the same
-- helper through an extra hyprctl dispatch, which added nothing.
hl.bind(mainMod .. " + C", hl.dsp.exec_cmd(helpers .. "/clipboard-pick"))
-- Cycle through workspaces with SUPER + scroll
hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mainMod .. " + mouse_up",   hl.dsp.focus({ workspace = "e-1" }))

-- Drag and resize with the mouse
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- Screenshots
hl.bind("PRINT",         hl.dsp.exec_cmd(helpers .. "/screenshot region"))
hl.bind(mainMod .. " + PRINT", hl.dsp.exec_cmd(helpers .. "/screenshot full"))
hl.bind(mainMod .. " + SHIFT + PRINT", hl.dsp.exec_cmd(helpers .. "/screenshot window"))

-- Media keys (Logitech MX Master and the Keychron consumer keys)
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),      { locked = true, repeating = true })
hl.bind("XF86AudioMute",        hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),     { locked = true, repeating = true })
hl.bind("XF86AudioMicMute",     hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),   { locked = true, repeating = true })
hl.bind("XF86AudioPlay",        hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPause",       hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioNext",        hl.dsp.exec_cmd("playerctl next"),       { locked = true })
hl.bind("XF86AudioPrev",        hl.dsp.exec_cmd("playerctl previous"),   { locked = true })

-- Utilities.
-- Notification history: anyrun fed by dunst's history, newest first.
hl.bind(mainMod .. " + N", hl.dsp.exec_cmd(helpers .. "/notif-history"))
-- Colour picker (hyprpicker copies the picked colour to the clipboard).
hl.bind(mainMod .. " + SHIFT + P", hl.dsp.exec_cmd("hyprpicker --autocopy"))
-- Screen recording toggle.
-- wf-recorder: SUPER+SHIFT+R starts a region recording, pressing it again stops.
hl.bind(mainMod .. " + SHIFT + R", hl.dsp.exec_cmd(helpers .. "/record-toggle"))
