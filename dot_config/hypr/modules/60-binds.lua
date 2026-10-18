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
--   SUPER+CTRL+1..0 move window to ws   SUPER+SHIFT+3/4/5 capture trio

local mainMod = "SUPER"

local terminal    = "kitty"
-- The unified menu is the shell's launcher now
-- (dot_config/quickshell/Launcher.qml): applications, and the clipboard history
-- on its own chord below. It replaced anyrun, whose plugins are why this used to
-- be a single prompt doing five jobs — `qs ipc call` reaches the running shell,
-- so nothing is started per keypress.
local launcher    = "qs ipc call launcher toggleApps"
local fileManager = "kitty yazi"
local lockCmd     = "hyprlock"

local ipc     = "hyprctl dispatch"

-- Applications
hl.bind(mainMod .. " + RETURN", hl.dsp.exec_cmd(terminal))
hl.bind(mainMod .. " + E",      hl.dsp.exec_cmd(fileManager))
hl.bind(mainMod .. " + B",      hl.dsp.exec_cmd(terminal .. " -e bluetui"))
-- Window switcher: hold-and-release, the Alt-Tab muscle memory.
--
-- The switcher is part of the shell now (dot_config/quickshell/Switcher.qml).
-- `qs ipc call switcher toggle` opens the overlay; the shell's own overlay takes
-- keyboard focus, so it sees the TAB taps and, crucially, the SUPER *release*
-- that commits the switch. That is what the old `--mod super` argument was for:
-- snappy-switcher watched the modifier itself because Hyprland's release binds
-- were unreliable (see below). Nothing watches XKB here — Qt receives the
-- release because the overlay holds keyboard focus.
--
-- WHY THE OLD SWITCHER IS GONE
-- snappy-switcher was a separate daemon with its own IPC socket, config file and
-- layer surface, and it drew a snapshot rather than live content. The shell can
-- do all of it with the theme it already has, and with live thumbnails: each
-- card is a ScreencopyView capturing the window as it is right now.
--
-- (It replaced hyprswitch, which generated its own submap while open, with the
-- release-to-commit expressed as a bind carrying `release = true`. That bind
-- needs `submap_universal = true` to fire while a submap is active; the flag was
-- only added upstream in 3b5bb6a (2026-08-28) and no hyprswitch release contains
-- it, so letting go of SUPER did nothing on the first attempt. snappy-switcher
-- never generated a submap, and neither does this.)
--
-- Hold SUPER and tap TAB to step through windows (most-recently-used order, so
-- tapping twice goes back two windows); release SUPER to switch, Escape to abort,
-- or click a card. Windows on other workspaces are labelled with where they are.
hl.bind(mainMod .. " + Tab", hl.dsp.exec_cmd("qs ipc call switcher toggle"))
-- Picture-in-picture has no bind: it is dragged out of the bar. Press a
-- workspace pill and pull downward and a floating live view of that workspace
-- comes with the pointer (see dot_config/quickshell/PiP.qml); it stays where it
-- is dropped, and can be dragged, resized, switched to or closed from its own
-- header. `qs ipc call pip open <workspace id>` still exists for scripts.
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
-- Moving a window there is SUPER+CTRL+<n>. It used to be SUPER+SHIFT+<n>, but
-- SUPER+SHIFT+3/4/5 are the macOS screenshot trio Reza asked for (there is no
-- Print key on this keyboard), and Hyprland dispatches *all* matching binds —
-- the two homes could not coexist without every capture also moving a window,
-- so the move family moved rather than the captures.
for i = 1, 10 do
    local key = i % 10
    hl.bind(mainMod .. " + " .. key, hl.dsp.focus({ workspace = i }))
    hl.bind(mainMod .. " + CTRL + " .. key, hl.dsp.window.move({ workspace = i }))
end

hl.bind(mainMod .. " + S",         hl.dsp.workspace.toggle_special("magic"))
hl.bind(mainMod .. " + SHIFT + S", hl.dsp.window.move({ workspace = "special:magic" }))

-- Clipboard history (cliphist), fed by the cliphist systemd user unit.
-- One bind only: the old config had a second identical chord routing the same
-- helper through an extra hyprctl dispatch, which added nothing.
--
-- The picking happens in the shell's launcher now, which reads `cliphist list`
-- itself, decodes the chosen entry and puts it on the clipboard — the old
-- `cliphist list | anyrun | cliphist decode | wl-copy` pipeline is gone.
hl.bind(mainMod .. " + C", hl.dsp.exec_cmd("qs ipc call launcher openClipboard"))
-- Cycle through workspaces with SUPER + scroll
hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mainMod .. " + mouse_up",   hl.dsp.focus({ workspace = "e-1" }))

-- Drag and resize with the mouse
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- Screenshots and recording, the macOS ⇧⌘3/4/5 model.
-- There is no Print key on this keyboard, so the trio is SUPER+SHIFT+3 (whole
-- screen, ⌘⇧3), SUPER+SHIFT+4 (drag a selection, ⌘⇧4) and SUPER+SHIFT+5 (the
-- capture toolbar, ⌘⇧5: modes, save-to, timer, thumbnail, recording). All of
-- it goes through the shell's capture IPC (dot_config/quickshell/Capture.qml);
-- ~/.local/bin/screenshot and record-toggle are thin wrappers over the same
-- calls, kept for scripts and old muscle memory.
hl.bind(mainMod .. " + SHIFT + 3", hl.dsp.exec_cmd("qs ipc call capture screen"))
hl.bind(mainMod .. " + SHIFT + 4", hl.dsp.exec_cmd("qs ipc call capture selection"))
hl.bind(mainMod .. " + SHIFT + 5", hl.dsp.exec_cmd("qs ipc call shell togglePanel capture"))
-- Control added, as on macOS (⌃⌘⇧3 / ⌃⌘⇧4): the same captures, but they go to
-- the clipboard and leave no file behind.
-- The modifiers must be in bit order (SHIFT before CTRL): written the other way
-- round the chord is accepted by the config and never registered, which looks
-- exactly like the key doing nothing. Verified against `hyprctl binds` (modmask
-- 69 = SUPER+SHIFT+CTRL).
hl.bind(mainMod .. " + SHIFT + CTRL + 3", hl.dsp.exec_cmd("qs ipc call capture screenClipboard"))
hl.bind(mainMod .. " + SHIFT + CTRL + 4", hl.dsp.exec_cmd("qs ipc call capture selectionClipboard"))

-- Media keys (Logitech MX Master and the Keychron consumer keys)
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),      { locked = true, repeating = true })
hl.bind("XF86AudioMute",        hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),     { locked = true, repeating = true })
hl.bind("XF86AudioMicMute",     hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),   { locked = true, repeating = true })
-- Transport goes through the shell (MPRIS) rather than playerctl: playerctl was
-- a dependency of waybar and went with it, which silently broke these keys. The
-- shell is the media client now, so the keys ask it (`qs ipc call player ...`).
hl.bind("XF86AudioPlay",        hl.dsp.exec_cmd("qs ipc call player toggle"),   { locked = true })
hl.bind("XF86AudioPause",       hl.dsp.exec_cmd("qs ipc call player toggle"),   { locked = true })
hl.bind("XF86AudioNext",        hl.dsp.exec_cmd("qs ipc call player next"),     { locked = true })
hl.bind("XF86AudioPrev",        hl.dsp.exec_cmd("qs ipc call player previous"), { locked = true })

-- Panels that are not attached to a bar widget.
--
-- The keybind cheatsheet is generated from this file at runtime
-- ("slash", not "/": the bind parser wants a keysym name)
-- (dot_config/quickshell/Keybinds.qml), so it cannot drift from what is bound.
hl.bind(mainMod .. " + slash", hl.dsp.exec_cmd("qs ipc call shell togglePanel keys"))
-- Quick settings: do-not-disturb, cinema mode, night light, radios, volume.
hl.bind(mainMod .. " + A", hl.dsp.exec_cmd("qs ipc call shell togglePanel controls"))

-- Utilities.
-- Notification centre: the shell keeps the history itself now (it is the
-- notification server), so this opens a panel instead of piping `dunstctl
-- history` through python into anyrun's stdin plugin.
hl.bind(mainMod .. " + N", hl.dsp.exec_cmd("qs ipc call shell togglePanel notifications"))
-- Colour picker (hyprpicker copies the picked colour to the clipboard).
hl.bind(mainMod .. " + SHIFT + P", hl.dsp.exec_cmd("hyprpicker --autocopy"))
-- Screen recording has no chord of its own: SUPER+SHIFT+5 opens the capture
-- toolbar with Record/Stop Recording, and the REC pill in the bar is the stop
-- button while one runs (the old SUPER+SHIFT+R toggle is gone).

