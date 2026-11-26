local ADDON, CP = ...
if CP.stopped then return end

CP.name = ADDON

-- The addon's media folder, from the folder it loaded from, so a copy under another name uses its own art.
CP.MEDIA = "Interface\\AddOns\\" .. ADDON .. "\\Media\\"

-- Public handle for other addons and the headless tests.
ProfLost = CP

local DEFAULTS = {
    collect = true,   -- plan only with materials the player can gather or buy from vendors
    mapIcons = true,      -- ProfLost's own icons and route lines on the world map and minimap
    otherZones = false,   -- the world map also shows every other zone on the continent, dimmed
    vendorAlerts = true,  -- list pattern vendors of the zone on the Gather tab
    hideInCombat = true,  -- the free guide window hides during a fight
    gatherHideInCombat = true, -- the detached gathering panel hides during a fight
    windowHeight = 560,   -- the free window's largest height outside the One view's step list; it fits its content below that
    guideSteps = 4,       -- step rows the One view lists; 4 is what a default 560 px window showed whole
    gatherSide = "right", -- the attached gathering panel's side of the guide; set once from the old dockSide (CP.CarryOver)
    gatherAttached = true, -- the gathering panel slides out of the guide window; off: its own window
    fishCook = true,      -- Fishing and Cooking paired: waters the Cooking guide needs, fish nearly free
    textScale = 1,        -- ProfLost's text size, 0.85 to 1.15
    windowOpacity = 0.85, -- guide and gathering window background; the default follows Daylight UI's window opacity
    font = "general",     -- ProfLost's font: a Daylight UI font key, "general" = the player's
    unitTooltip = true,   -- creature tooltips list what skinning (or herbing, mining) the corpse gives
    itemTooltip = true,   -- item tooltips list guide needs and where to farm
    neededMarks = true,   -- a dot on bag slots holding items the guides still need
    route = true,         -- the gathering route on the map (the panel's pin); off is saved as false
    routeOnMap = true,    -- the route's line and stops drawn on the maps (the world map's button)
    minimapButton = true, -- the minimap button; LibDBIcon's hide follows it
    whatsNew = true,      -- What's New once after each update (UI/News.lua)
    newerNotice = true,   -- a note when another player runs a newer ProfLost (Engine/Peers.lua)
    gloweyGuide = false,  -- the leveling guide left to Glowey's Recipes (Core/Glowey.lua)
    gloweyBuy = false,    -- the vendor Buy button left to Glowey's Recipes
    gloweyTips = false,   -- the item tooltip lines left to Glowey's Recipes
}
CP.DEFAULTS = DEFAULTS   -- read by the DaylightUI plugin for its module's defaults

local function applyDefaults(db, defaults)
    for k, v in pairs(defaults) do
        if db[k] == nil then db[k] = v end
    end
    return db
end

-- Event hub. Modules call CP:On(event, fn); several handlers per event are allowed.
-- Names starting ProfLost_ are ProfLost's own signals. CP:Emit raises them; the game never
-- hears of them. UNIT_ events register for the player alone: every handler of one reads
-- only the player.

-- The prefix of ProfLost's own signal names.
local SIGNAL = "ProfLost_"
CP.SIGNAL = SIGNAL

local handlers = {}
local hub = CreateFrame("Frame")
CP.hub = hub

-- /proflost mem: calls and KB allocated per event, signal and coalesced job since the last
-- report. Off by default; while off the hub pays one boolean test per event.
local mem = { on = false, depth = 0, rows = {}, since = 0 }

local function measure(label, fn, ...)
    local row = mem.rows[label]
    if not row then
        row = { calls = 0, kb = 0, gc = 0 }
        mem.rows[label] = row
    end
    row.calls = row.calls + 1

    -- A nested call (a signal inside an event) counts, and its KB stays with its parent.
    if mem.depth > 0 then return fn(...) end
    mem.depth = 1
    local before = collectgarbage("count")
    local ok, err = pcall(fn, ...)
    local used = collectgarbage("count") - before
    mem.depth = 0

    -- A collection during the call makes its delta meaningless.
    if used >= 0 then row.kb = row.kb + used else row.gc = row.gc + 1 end
    if not ok then error(err, 0) end
end

local function dispatch(event, ...)
    local list = handlers[event]
    if not list then return end
    for i = 1, #list do
        local fn = list[i]
        if fn then fn(event, ...) end
    end
end

local PLAYER = {}   -- UNIT_ events, which reach the handlers for the player only

hub:SetScript("OnEvent", function(_, event, ...)
    if PLAYER[event] and ... ~= "player" then return end
    if mem.on then return measure(event, dispatch, event, ...) end
    dispatch(event, ...)
end)

-- An event this client doesn't know fails to register quietly, so its handler never errors.

function CP:On(event, fn)
    if not handlers[event] then
        handlers[event] = {}
        if event:sub(1, 5) == "UNIT_" then
            PLAYER[event] = true
            pcall(hub.RegisterUnitEvent, hub, event, "player")
        elseif event:sub(1, #SIGNAL) ~= SIGNAL then
            pcall(hub.RegisterEvent, hub, event)
        end
    end
    table.insert(handlers[event], fn)
end

-- Drops handler `fn` of `event`; the hub stops listening once the event has none.
function CP:Off(event, fn)
    local list = handlers[event]
    if not list then return end
    for i = #list, 1, -1 do
        if list[i] == fn then table.remove(list, i) end
    end
    if #list > 0 then return end
    handlers[event], PLAYER[event] = nil, nil
    if event:sub(1, #SIGNAL) ~= SIGNAL then pcall(hub.UnregisterEvent, hub, event) end
end

-- Raises ProfLost signal `signal` to its CP:On handlers.
function CP:Emit(signal, ...)
    if mem.on then return measure(signal, dispatch, signal, ...) end
    dispatch(signal, ...)
end

-- Coalesce bursts of events into one call on the next frame.

local pending = {}

function CP:Soon(key, fn)
    if pending[key] then return end
    pending[key] = true
    C_Timer.After(0, function()
        pending[key] = nil
        if mem.on then return measure("soon:" .. key, fn) end
        fn()
    end)
end

-- Calls `fn` once a burst of calls under `key` stops: `quiet` seconds after the last one,
-- and at most `most` seconds after the first.

local later = {}

function CP:Later(key, quiet, most, fn)
    local now = GetTime()
    local w = later[key]
    if w then
        w.due = math.min(now + quiet, w.limit)
        return
    end
    w = { due = now + quiet, limit = now + most }
    later[key] = w
    local function check()
        local left = w.due - GetTime()
        if left > 0.001 then return C_Timer.After(left, check) end
        later[key] = nil
        if mem.on then return measure("later:" .. key, fn) end
        fn()
    end
    C_Timer.After(quiet, check)
end

-- Turns the memory count on or off, or prints it and starts it over.
function CP.Mem(arg)
    if arg == "on" or arg == "off" then
        mem.on, mem.rows, mem.since = arg == "on", {}, GetTime()
        CP:Print("memory count " .. arg .. ".")
        return
    end
    if not mem.on then
        CP:Print("memory count is off. /proflost mem on starts it.")
        return
    end
    local list, total = {}, 0
    for label, row in pairs(mem.rows) do
        list[#list + 1] = { label = label, row = row }
        total = total + row.kb
    end
    table.sort(list, function(a, b) return a.row.kb > b.row.kb end)
    local secs = math.max(GetTime() - mem.since, 0.001)
    CP:Print(("memory over %.0f s: %.0f KB, %.0f KB/min"):format(secs, total, total * 60 / secs))
    for _, e in ipairs(list) do
        local gc = e.row.gc > 0 and (", %d skipped by GC"):format(e.row.gc) or ""
        print(("  %s: %d calls, %.1f KB%s"):format(e.label, e.row.calls, e.row.kb, gc))
    end
    mem.rows, mem.since = {}, GetTime()
end

-- Items ProfLost asked the game to load. Their GET_ITEM_INFO_RECEIVED raises
-- ProfLost_ITEM_LOADED; loads other addons asked for cost nothing.
local waiting = {}

function CP.RequestItem(id)
    if not id then return end
    waiting[id] = true
    -- A client without the call (the Daylight UI tier's stand-in game) leaves the name to arrive later.
    if C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
end

-- Item `id`'s name, or nil while it loads. A miss asks for it.
function CP.ItemName(id)
    local name = C_Item.GetItemNameByID(id)
    if not name then CP.RequestItem(id) end
    return name
end

CP:On("GET_ITEM_INFO_RECEIVED", function(_, id)
    if not (id and waiting[id]) then return end
    waiting[id] = nil
    CP:Emit("ProfLost_ITEM_LOADED", id)
end)

-- The plugin's colours, teal to green to brass: the TOC title, the chat prefix and the
-- Daylight UI sidebar colour.
CP.ACCENT = { "1fb5a6", "6cc36f", "e0b43c" }

-- `text` with one colour per letter along CP.ACCENT; spaces stay uncoloured. Each text is
-- coloured once; the panel measures its title on every refresh.
local painted = {}

function CP.Gradient(text)
    if painted[text] then return painted[text] end
    local stops = {}
    for i, hex in ipairs(CP.ACCENT) do
        stops[i] = { tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16) }
    end
    local letters = #(text:gsub(" ", ""))
    local out, n = {}, 0
    for c in text:gmatch(".") do
        if c == " " then
            out[#out + 1] = c
        else
            local t = letters > 1 and n / (letters - 1) or 0
            local seg = math.min(math.floor(t * (#stops - 1)), #stops - 2)
            local u = t * (#stops - 1) - seg
            local a, b = stops[seg + 1], stops[seg + 2]
            local rgb = {}
            for k = 1, 3 do rgb[k] = math.floor(a[k] + (b[k] - a[k]) * u + 0.5) end
            out[#out + 1] = ("|cff%02x%02x%02x%s|r"):format(rgb[1], rgb[2], rgb[3], c)
            n = n + 1
        end
    end
    painted[text] = table.concat(out)
    return painted[text]
end

local PREFIX = CP.Gradient("Professionally Lost")

function CP:Print(msg)
    print(PREFIX .. ": " .. tostring(msg))
end

-- Developer traces in chat, by tag: open, buy, scan, marks, look. Each starts off and is
-- on only for the session that turns it on; a reload or login clears them all.
CP.trace = {}

-- Saved trace switches from older builds, cleared at load.
CP.OLD_TRACE_KEYS = { "traceOpen", "traceBuy", "traceScan", "traceMarks", "watchLook" }

-- Turns trace `tag` on or off for this session.
function CP.SetTracing(tag, on)
    CP.trace[tag] = on and true or nil
end

-- One line of a developer trace in chat: `tag`, a time, and `fmt` filled in. Silent
-- unless trace `tag` is on.
function CP.TraceLine(tag, at, fmt, ...)
    if not CP.trace[tag] then return end
    local ok, text = pcall(string.format, fmt, ...)
    print(("|cff1fb5a6ProfLost %s|r %.2f s: %s"):format(tag, at, ok and text or fmt))
end

-- Saved keys from older builds, carried over once. A hidden checklist, or a window set to
-- show only with a profession window or only when opened, becomes a closed window. "Always"
-- keeps it up in combat.
function CP.CarryOver(db)
    local existing = next(db) ~= nil   -- false for a first run
    if db.gatherOpen == nil then db.gatherOpen = db.gatherList ~= false end
    if db.gatherList ~= nil then
        if db.gatherList == false and db.windowShow == nil then db.windowShow = "profession" end
        db.gatherList = nil
    end
    if db.windowShow ~= nil then
        local was = db.windowShow
        if (was == "profession" or was == "manual") and db.windowClosed == nil then db.windowClosed = true end
        if was == "always" and db.hideInCombat == nil then
            db.hideInCombat = false
            db.hideInCombatCarried = true
        end
        db.windowShow, db.windowShowCarried = nil, nil
    end
    if db.gatherCollapsed ~= nil then
        if db.windowCollapsed == nil then db.windowCollapsed = db.gatherCollapsed or nil end
        db.gatherCollapsed = nil
    end

    -- One "Hide in combat" became one per window, both from the old value. Daylight UI's
    -- copy arrives later (Plugin.Sync) and is carried over again while this flag holds.
    if db.gatherHideInCombat == nil then
        db.gatherHideInCombat = db.hideInCombat ~= false
        db.gatherHideCarried = true
    end

    -- The detached panel has its own padlock, closed if the guide's was.
    if db.gatherLocked == nil then db.gatherLocked = db.windowLocked == true end

    -- The panel's side is left or right of the guide. A new save, or an old "auto", takes
    -- the side away from the profession window once. Daylight UI's copy is settled later
    -- (Plugin.Sync) while the flag holds.
    if db.gatherSide ~= "left" and db.gatherSide ~= "right" then
        db.gatherSide = db.dockSide == "LEFT" and "left" or "right"
        db.gatherSideCarried = true
    end

    -- The guide window no longer docks beside a profession window (DOCKLESS-01). Every save
    -- from a docking build holds dockSide. The docked window's close and side go, and a
    -- player who kept the free window closed but the docked one open finds it open once,
    -- where it last stood free (else beside the chat box).
    if db.dockSide ~= nil or db.dockClosed ~= nil then
        if db.windowClosed and not db.dockClosed then db.windowClosed = nil end
        db.dockSide, db.dockClosed = nil, nil
    end

    -- The corner grip saved a width and a most height (windowSize). The height becomes a step
    -- count once, by whole rows from the default window's; Daylight UI's copy is settled later
    -- (Plugin.Sync) while the flag holds.
    local size = db.windowSize
    if type(size) == "table" then
        if type(size[1]) == "number" and db.windowWidth == nil then db.windowWidth = size[1] end
        if type(size[2]) == "number" and db.guideSteps == nil then
            local rows = (size[2] - DEFAULTS.windowHeight) / CP.GuideTab.RowHeight()
            db.guideSteps = CP.Settings.Bound("guideSteps", DEFAULTS.guideSteps + math.floor(rows + 0.5))
            db.guideStepsCarried = true
        end
        db.windowSize = nil
    end

    -- One "Window scale" became a guide window scale and a gathering panel scale, both from the
    -- old value. Without Daylight UI's mover the old key is split here; with it, Daylight UI's
    -- guide scale is copied to the panel's mover later (Plugin.Sync) while the flag holds. A new
    -- save has nothing to carry.
    if db.scalesSplit == nil then
        if db.windowScale ~= nil then
            if db.guideScale == nil then db.guideScale = db.windowScale end
            if db.gatherScale == nil then db.gatherScale = db.windowScale end
            db.windowScale = nil
        end
        if existing then db.gatherScaleCarried = true end
        db.scalesSplit = true
    end
    return db
end

-- Reads the saved variables at load. Every developer trace starts off, and so does a
-- profession preview (UI/Preview.lua).
function CP.LoadSaved()
    if CP.Preview then CP.Preview.Drop() end
    ProfLostDB = applyDefaults(CP.CarryOver(ProfLostDB or {}), DEFAULTS)
    ProfLostDB.colourSeen = nil   -- no longer collected; clears it from saved files
    for _, key in ipairs(CP.OLD_TRACE_KEYS) do ProfLostDB[key] = nil end
    for tag in pairs(CP.trace) do CP.trace[tag] = nil end
    mem.on = false
    ProfLostCharDB = ProfLostCharDB or {}
    ProfLostCharDB.merchants = nil   -- vendors once remembered for Buy's targeting; no longer kept
    CP.db = ProfLostDB
    CP.charDB = ProfLostCharDB
end

CP:On("ADDON_LOADED", function(_, name)
    if name ~= ADDON then return end
    CP.LoadSaved()
end)

-- The first time ProfLost loads, a short how-to in chat, once the chat window is up.
CP.WELCOME_SETTINGS = "Settings: right-click the minimap button, /proflost settings, or /dui and pick ProfLost under Plugins."

function CP.Welcome()
    CP:Print("ready. The guide window shows your professions' leveling guides, with craft buttons while a profession window is open.")
    CP:Print("The tab on its edge slides out what to gather where you stand. The minimap button or /proflost shows or hides the window.")
    if CP.Settings and CP.Settings.Daylight and CP.Settings.Daylight() then
        CP:Print("Add the Professionally Lost data text (/dui > Info Panel) for each profession's next step. "
            .. CP.WELCOME_SETTINGS)
    else
        CP:Print(CP.WELCOME_SETTINGS)
    end
end

CP:On("PLAYER_ENTERING_WORLD", function()
    if not CP.db or CP.db.welcomed then return end
    CP.db.welcomed = true
    C_Timer.After(3, CP.Welcome)
end)

-- The slash command: shows or hides the guide window ('gather' the gathering panel,
-- 'bug' opens a report to copy, 'finds' counts saved finds, 'collect on|off' switches
-- the owner's collector). Any other word, 'settings' among them, opens the settings.

SLASH_PROFLOST1 = "/proflost"
SlashCmdList.PROFLOST = function(rest)
    -- Hidden: stops all sharing between players, both ways.
    local share = rest:match("^share (%a+)$")
    if share == "off" or share == "on" then
        CP.db.shareOff = share == "off" or nil
        CP:Print(share == "off" and "sharing with other players is off." or "sharing with other players is on.")
        return
    end
    -- Hidden: the memory count (CP.Mem).
    local memArg = rest:match("^mem%s*(%a*)$")
    if memArg then
        CP.Mem(memArg)
        return
    end
    -- Hidden: each step of an Open click in chat (Window.Trace).
    local traceArg = rest:match("^trace open (%a+)$")
    if (traceArg == "on" or traceArg == "off") and CP.Window then
        CP.Window.SetTrace(traceArg == "on")
        return
    end
    -- Hidden: each step of a vendor Buy in chat (Buying.Trace).
    local buyArg = rest:match("^trace buy (%a+)$")
    if (buyArg == "on" or buyArg == "off") and CP.Buying then
        CP.Buying.SetTrace(buyArg == "on")
        return
    end
    -- Hidden: each bag mark painted, and why one isn't (NeededMarks.SetTrace).
    local marksArg = rest:match("^trace marks (%a+)$")
    if (marksArg == "on" or marksArg == "off") and CP.NeededMarks then
        CP.NeededMarks.SetTrace(marksArg == "on")
        return
    end
    -- Hidden: the auction scan's phases, counts and timings (Scan.SetTrace).
    local scanArg = rest:match("^trace scan (%a+)$")
    if (scanArg == "on" or scanArg == "off") and CP.Scan then
        CP.Scan.SetTrace(scanArg == "on")
        return
    end
    -- Hidden: every change of the guide window's look in chat (Look.SetWatch).
    local watchArg = rest:match("^watch look (%a+)$")
    if (watchArg == "on" or watchArg == "off") and CP.Look then
        CP.Look.SetWatch(watchArg == "on")
        return
    end
    -- Hidden: a developer's preview of another profession's windows (UI/Preview.lua).
    local previewArg = rest:match("^preview%s*(%a*)")
    if previewArg and CP.Preview then
        if previewArg == "off" then
            CP.Preview.Stop()
        elseif previewArg == "on" then
            CP.Preview.Resume()
        else
            CP.Preview.Command(rest:match("^preview%s*(.-)%s*$"))
        end
        return
    end
    -- Hidden: the guide window's alphas, parents, levels and shells (Look.Dump).
    if rest == "dump look" and CP.Look then
        CP.Look.Dump()
        return
    end
    -- Hidden: what ProfLost reads of the Working Overtime legacy perk (Professions.ReadOvertime).
    if rest == "check overtime" and CP.Professions then
        local P = CP.Professions
        if P.RefreshOvertime() then CP:Emit("ProfLost_SKILLS") end
        local o = P.overtime
        CP:Print(("overtime: tree found: %s"):format(o.tree and "yes" or "no"))
        CP:Print(("overtime: node found: %s"):format(o.node and "yes" or "no"))
        CP:Print(("overtime: rank %d of %d"):format(o.rank, o.max))
        CP:Print(("overtime: multiplier %.2f"):format(CP.Guide and CP.Guide.boost or 1))
        return
    end
    -- Hidden: every rule the shown windows' look breaks, or "look ok" (Look.Check).
    if rest == "check look" and CP.Look then
        CP.Look.PrintCheck()
        return
    end
    -- Hidden: where the zone checks put the player's spot and this zone's spawns.
    if rest == "border" and CP.Gather then
        local zone = CP.Gather.PlayerZone()
        if not zone or CP.Gather.IsInstance(zone) then
            CP:Print("border: no outdoor zone here.")
            return
        end
        local pos = C_Map.GetPlayerMapPosition(zone, "player")
        local px, py
        if pos then px, py = pos:GetXY() end
        CP:Print(("border: zone %d"):format(zone))
        for _, line in ipairs(CP.Gather.BorderReport(zone, px, py)) do CP:Print(line) end
        -- The grind spots drawn now: where each sits, whose zone that is, and what it counts.
        local spots, drawnFor = {}, nil
        if CP.RouteMap and CP.RouteMap.Spots then spots, drawnFor = CP.RouteMap.Spots() end
        if #spots == 0 then
            CP:Print("border: no grind spots drawn (turn the route on).")
        else
            if drawnFor and drawnFor ~= zone then
                CP:Print(("border: these spots were drawn for zone %d, not %d"):format(drawnFor, zone))
            end
            for _, s in ipairs(spots) do
                local owner = CP.Gather.ZoneAt(zone, s.x, s.y)
                local info = owner and C_Map.GetMapInfo(owner)
                local names = {}
                for k, n in pairs(s.parts or {}) do names[#names + 1] = ("%s %d"):format(k, n) end
                table.sort(names)
                CP:Print(("border: spot %d at %.1f, %.1f is in %s; counts %s"):format(s.rank or 0, s.x * 100, s.y * 100,
                    info and info.name or "can't say", table.concat(names, ", ")))
            end
        end
        return
    end
    -- Hidden: every zone the route solved, its grind spots and the pins drawn now.
    if rest == "zones" and CP.RouteMap and CP.RouteMap.ZonesReport then
        for _, line in ipairs(CP.RouteMap.ZonesReport()) do CP:Print("zones: " .. line) end
        return
    end
    -- Hidden: spot 1 of each zone on its continent, by HereBeDragons and by the game.
    if rest == "pins" and CP.RouteMap and CP.RouteMap.PinsReport then
        for _, line in ipairs(CP.RouteMap.PinsReport()) do CP:Print("pins: " .. line) end
        return
    end
    if rest == "bug" and CP.BugReport then
        CP.BugReport.Show()
        return
    end
    if rest == "finds" and CP.Finds then
        local zones, nodes, mobs = CP.Finds.Count()
        CP:Print(("finds saved: %d nodes, %d beasts, in %d zones"):format(nodes, mobs, zones))
        return
    end
    -- The owner's collector (Engine/Peers.lua): pulls every zone's finds from each peer.
    local collect = rest and rest:match("^collect (%a+)$")
    if (collect == "on" or collect == "off") and CP.db then
        CP.db.collect_all = collect == "on" or nil
        CP:Print("collecting every zone's finds from other players: " .. collect)
        return
    end
    if rest:match("^%s*$") and CP.Window then
        CP.Window.Toggle()
        return
    end
    if rest == "gather" and CP.GatherPanel then
        CP.GatherPanel.ToggleShown()
        return
    end
    if CP.Panel and CP.Panel.OpenSettings then
        CP.Panel:OpenSettings()
    end
end
