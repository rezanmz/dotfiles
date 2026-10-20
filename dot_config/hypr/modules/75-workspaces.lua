-- Workspace partition across the two panels.
--
-- THE MODEL (A1): one global numbering, split between the panels.
--   Dell U3225QE (4K, the main panel) owns workspaces 1-5.
--   Dell SE2723DS  (2K, the sidecar)   owns workspaces 6-10.
-- SUPER+1..SUPER+5 always land on the 4K, SUPER+6..SUPER+0 on the 2K. Mail
-- stays on workspace 10, which is on the 2K, so Thunderbird does not move.
--
-- WHY THE RULES ARE DECLARED UP FRONT:
-- Hyprland picks a monitor's starting workspace when that monitor connects
-- (CMonitor::setupDefaultWS), reading the rules as they are at that moment.
-- The rules therefore have to be in place BEFORE the panels come up, or the
-- compositor picks a default from whatever it happens to find. So the split is
-- declared at config load time, when no monitor exists yet - that is fine, a
-- rule naming a panel that is not connected is simply skipped until it is
-- (WorkspacePlacementController.cpp: "don't do anything yet, as the monitor is
-- not yet present").
--
-- WHY `persistent = true`:
-- A workspace rule's `monitor` binding is enforced at connect time and on a
-- monitor-state refresh, and only for rules marked persistent. Without it the
-- binding is a one-shot placement that a later window move can undo, and the
-- workspaces are never created up front.
--
-- WHY THE PANELS ARE NAMED BY DESCRIPTION:
-- "desc:" selectors identify a PANEL by its EDID identity (make, model,
-- serial), so the partition follows the physical screen to whatever socket it
-- is plugged into. A connector name would not survive a replug. The selector
-- is a case-sensitive PREFIX of the description, and Hyprland matches it
-- against both the full description ("Dell Inc. DELL U3225QE 3Y4F584 (DP-1)")
-- and the short one ("Dell Inc. DELL U3225QE 3Y4F584"), so a selector that
-- omits the connector matches either way.
--
-- ONE PANEL:
-- With only one panel connected, that panel takes the whole 1-10 range, so
-- every workspace is on the single screen. The partition is recomputed from
-- the connected monitors whenever that set changes; see apply().

-- The panels, in the order they claim workspace numbers.
local PANELS = {
    {
        model = "DELL U3225QE",
        desc  = "desc:Dell Inc. DELL U3225QE 3Y4F584",
        first = 1,
        last  = 5,
    },
    {
        model = "DELL SE2723DS",
        desc  = "desc:Dell Inc. DELL SE2723DS 5P097V3",
        first = 6,
        last  = 10,
    },
}

-- The complete set of workspaces.
local ALL_FIRST = 1
local ALL_LAST  = 10

-- Bind a range of workspaces to a panel.
local function bind(panel, first, last)
    for ws = first, last do
        hl.workspace_rule({
            workspace  = tostring(ws),
            monitor    = panel.desc,
            persistent = true,
        })
    end
end

-- The panels that are connected right now, in PANELS order.
--
-- A panel is matched on the model token inside its EDID description, so this
-- identifies the physical screen rather than the socket it is plugged into.
local function connectedPanels()
    local present = {}

    for _, mon in ipairs(hl.get_monitors()) do
        for _, panel in ipairs(PANELS) do
            if mon.description:find(panel.model, 1, true) then
                present[panel.model] = panel
            end
        end
    end

    local panels = {}
    for _, panel in ipairs(PANELS) do
        if present[panel.model] then
            panels[#panels + 1] = panel
        end
    end

    return panels
end

-- Apply the partition for the panels that are connected.
--
-- Both panels -> the fixed split: the 4K takes 1-5, the 2K takes 6-10.
-- One panel  -> it takes the complete 1-10 range, so the whole set of
--               workspaces lands on the single screen.
-- No panels   -> nothing is bound; there is nowhere to bind anything.
--
-- Each call re-states the binding for every workspace. hl.workspace_rule()
-- merges into the existing rule for that workspace, so this is idempotent and
-- never leaves a workspace pointing at a panel that is gone: a workspace
-- always names the panel it is on, or is left with the rule that names the
-- panel it should be on once that panel is back.
local function apply()
    local panels = connectedPanels()

    if #panels == 0 then
        return
    end

    if #panels == 1 then
        -- One panel: it takes everything.
        bind(panels[1], ALL_FIRST, ALL_LAST)
    else
        for _, panel in ipairs(panels) do
            bind(panel, panel.first, panel.last)
        end
    end

    -- Workspace 1 is the default workspace. The rule merges into the rule for
    -- workspace 1 above, so it inherits that panel's binding and names the
    -- panel that owns workspace 1 as the default. A panel that is not bound to
    -- workspace 1 then starts on the first workspace bound to it
    -- (CMonitor::findAvailableDefaultWS skips the workspaces that belong
    -- elsewhere), so the 4K starts on 1 and the 2K on 6.
    hl.workspace_rule({
        workspace = "1",
        default   = true,
    })
end

-- Declare the split for the case where every panel is present.
--
-- This runs at config load time, before any monitor exists, so that
-- setupDefaultWS finds the right default when the panels connect. If the
-- panel set turns out to be different, apply() corrects it below.
for _, panel in ipairs(PANELS) do
    bind(panel, panel.first, panel.last)
end

hl.workspace_rule({
    workspace = "1",
    default   = true,
})

-- Recompute the partition when the monitor set changes.
--
-- The work is deferred by a short timer rather than done in the event
-- handler: monitor.added fires per panel, and the partition depends on the
-- whole set, so the last event of a burst is the one that decides the
-- result. The timer also guarantees the monitor list has settled - the
-- compositor's own bookkeeping of connected monitors runs as a listener on
-- the same event, so it may not be visible yet inside the handler.
--
-- A fresh timer is created per event rather than re-arming one: a oneshot
-- timer drops its callback reference once it has fired, so it is not a thing
-- to re-arm.
local function schedule()
    hl.timer(function()
        apply()
    end, { timeout = 120, type = "oneshot" })
end

hl.on("monitor.added", schedule)
hl.on("monitor.removed", schedule)

-- hyprland.start fires from the renderer's first frame, which is after the
-- panels are connected. It is the backstop for the case where a monitor event
-- was missed.
hl.on("hyprland.start", schedule)
