-- Keybindings.
-- SUPER is the main modifier, matching the i3 config this replaces.
--
--   SUPER+RETURN  terminal          SUPER+SPACE  unified menu
--   SUPER+SHIFT+D displays          SUPER+B  bluetooth
--   SUPER+Tab     window switcher (snappy-switcher, hold and release)
--   SUPER+Q twice close window (confirm)   SUPER+E  file manager
--   SUPER+SHIFT+Q twice exit Hyprland (confirm)
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
-- `snappy-switcher next` is only an IPC client: it hands the command to the
-- daemon started in 30-autostart.lua over a unix socket and returns at once.
-- The window list, the Cairo/Pango overlay and the input handling live in the
-- daemon, which is what makes hold-and-release work at all.
--
-- `--mod super` MUST match the modifier in the bind. The daemon watches that
-- key to know when to commit. It is matched through XKB
-- (xkb_state_mod_name_is_active on the name "super"), not by registering a
-- Hyprland release bind, so this does not depend on Hyprland reporting a
-- release event for a particular physical key name.
--
-- WHY THIS REPLACED HYPRSWITCH
-- hyprswitch generated its own Hyprland submap while open, with the release to
-- commit expressed as a bind carrying `release = true`. That bind needs
-- `submap_universal = true` to fire while a submap is active; that flag was
-- only added in upstream commit 3b5bb6a (2026-08-28), and no hyprswitch release
-- contains it — v5.0.0, the newest tag, was cut before that commit. The
-- installed binary still emitted `{ release = true, transparent = true }`, so
-- letting go of SUPER did nothing on the first attempt and the overlay stayed
-- up until a second try. Verified by `strings` on the installed binary.
-- snappy-switcher never generates a submap at all, so the class of bug cannot
-- occur here.
--
-- Escaping the old switcher also means the --switch-type workspace workaround
-- is gone. That existed because stepping client-to-client could land on an
-- identical-looking window; snappy groups tiled windows that share a workspace
-- AND app class into a single card (`mode = context` in its config.ini), so the
-- two kitty windows appear as one entry and every step is still a visible
-- change.
--
-- Hold SUPER and tap TAB to step through entries; release SUPER to switch to
-- the highlighted one (or press Escape to abort). Shift+TAB steps backwards.
-- No text search here: unlike anyrun on SUPER+SPACE, this is a pure cycle.
hl.bind(mainMod .. " + Tab", hl.dsp.exec_cmd("snappy-switcher next --mod super"))
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
-- Two binds here destroy something the user cannot get back: closing a window
-- (SUPER+Q) and ending the session (SUPER+SHIFT+Q). Both ask first.
--
-- Each arms a confirmation: the first press names what is about to go away in
-- a toast, the second press of the same chord within CONFIRM_MS does it, and
-- anything else — waiting the toast out, moving on to other work — drops the
-- request. One engine drives both chords; only the wording and the action
-- differ.
--
-- WHY NOT A CONFIRM SUBMAP
-- While a submap is active every keybind that is not `submap_universal` stops
-- matching, so a stray SUPER+Q would take the whole SUPER layer offline until
-- the submap is left again — the cure would be worse than the disease. Keeping
-- the pending state in plain Lua upvalues leaves every other bind working and
-- needs no escape hatch: doing nothing is the cancel.
--
-- Close uses a window-scoped arm whose target address is captured at arm time
-- and re-checked at confirm time, so SUPER+Q SUPER+Q can only ever close the
-- window the toast named. If focus moved in between, the second press re-arms
-- for the window now in front instead of closing something the user is no
-- longer looking at. Exit has no target: the arm simply names the action.

local CONFIRM_MS = 3000

-- Pending confirmation: the action it will run, the key that must be pressed
-- again to run it, the toast advertising it, and a sequence number so a lapsed
-- timer can tell a live arm from one it no longer owns.
local confirmArmed = nil
local confirmSeq   = 0

local function confirmCancel()
    if not confirmArmed then
        return
    end

    if confirmArmed.toast then
        confirmArmed.toast:dismiss()
    end

    confirmArmed = nil
end

local function confirmLabel(win)
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

-- Arm `action` behind a second press of the same chord: the caller only has to
-- pass what the toast should say, what is being armed (so an arm for one thing
-- can never be confirmed by a press meant for another), and the work itself.
local function confirmArm(chord, text, key, action)
    confirmCancel()

    confirmSeq = confirmSeq + 1
    local seq  = confirmSeq

    confirmArmed = {
        chord  = chord,
        key    = key,
        action = action,
        seq    = seq,
        toast  = hl.notification.create({
            text     = text,
            duration = CONFIRM_MS,
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
        if confirmArmed and confirmArmed.seq == seq then
            confirmCancel()
        end
    end, { timeout = CONFIRM_MS, type = "oneshot" })
end

-- The armed action of this chord, if the press is a repeat of the one that
-- armed it. Keyed on the target so one chord's armed request can never be
-- confirmed by another — and so arming a different window re-arms instead of
-- closing the wrong one.
local function confirmTake(chord, key)
    if not confirmArmed or confirmArmed.chord ~= chord or confirmArmed.key ~= key then
        return nil
    end

    local armed = confirmArmed
    confirmCancel()
    return armed.action
end

-- Close the focused window, but only after the same window was named by a
-- SUPER+Q press within the last CONFIRM_MS.
local function closeWithConfirm()
    local win = hl.get_active_window()
    if not win then
        return
    end

    local action = confirmTake("close", win.address)
    if action then
        action()
        return
    end

    -- Anything else arms a fresh confirmation for the window in front: the
    -- very first press, a different window, or a toast whose time already ran
    -- out. Re-arming is also the "no" path — nothing has to be pressed to
    -- abort, the request simply expires.
    local target = win.address

    confirmArm("close", ("Close %s? Press SUPER+Q again to confirm"):format(confirmLabel(win)), target, function()
        -- Close by the address captured at arm time rather than "the active
        -- window": the toast promised one specific window, and this cannot
        -- drift onto a different one if focus moves before the dispatch runs.
        hl.dispatch(hl.dsp.window.close({ window = "address:" .. target }))
    end)
end

-- End the session, but only after a SUPER+SHIFT+Q press within the last
-- CONFIRM_MS. The armed key is a constant because unlike a window there is
-- exactly one session to end, so any confirm press is a press for it.
local function exitWithConfirm()
    local action = confirmTake("exit", "session")
    if action then
        action()
        return
    end

    confirmArm("exit", "Exit Hyprland? Press SUPER+SHIFT+Q again to confirm", "session", function()
        hl.dispatch(hl.dsp.exit())
    end)
end

hl.bind(mainMod .. " + Q", closeWithConfirm)
hl.bind(mainMod .. " + L", hl.dsp.exec_cmd(lockCmd))
-- SUPER+M is intentionally unbound. It used to open an actions-only anyrun run;
-- those actions are in the unified menu now, so the chord is free.
hl.bind(mainMod .. " + SHIFT + Q", exitWithConfirm)

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
