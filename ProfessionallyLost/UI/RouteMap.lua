local _, CP = ...
if CP.stopped then return end

-- Draws the gathering loop on the world map and the minimap through HereBeDragons
-- pins: small dots along the path and a colored marker on every herb or ore stop,
-- plus a large marker on each creature grind spot.
-- Loops are solved in coroutines, FRAME_MS per frame, so a big zone doesn't stall.
-- The player's zone shows on the minimap, its zone map and its continent map. With
-- "Other zones", every other zone on the player's continent is solved after
-- it, at low priority, and drawn dimmed on its zone map and the continent map. While the
-- player plans a picked zone, that zone takes the player's slot and the player's own zone
-- is one of the others. Farm follows the setting as the guide does. What is drawn never
-- depends on which map the world map (or a map addon) shows.

local S = CP.Style
local Route = CP.Route
local Pins = LibStub("HereBeDragons-Pins-2.0")

local RouteMap = {}
CP.RouteMap = RouteMap

RouteMap.DIM = 0.7           -- opacity of another zone's pins and lines
RouteMap.ESTIMATED = "Chances estimated from its level"

-- HereBeDragons-Pins show flags. Every pin shows only on the map it is registered on.
-- A grind spot gets a second pin on its continent map, placed by Waypoint.OnContinent
-- (the game's world transforms). HereBeDragons' own zone-to-continent placement puts
-- them in the wrong place on Forever. Route stops stay on the zone map, where a
-- continent's worth of them would bury the map.
RouteMap.GRIND_FLAG = nil
RouteMap.STOP_FLAG = nil
local pinAlpha = 1           -- set by drawSlot for the pins it makes

local REF = "ProfLost_Route"
local FRAME_MS = 5           -- solver time per frame before it yields
local LIGHT_EVERY = 25       -- light ticks (a map lookup, a point merged) per look at the clock
local MEDIA = CP.MEDIA
local DOT, MASK, BADGE = MEDIA .. "Dot", MEDIA .. "CircleMask", MEDIA .. "Badge"
local RING_MONO, RIM = MEDIA .. "GrindRingMono", MEDIA .. "Ring"   -- white rings, tinted with the accent
local RING_HOLE = 0.67   -- the ring's opening, as a share of its width

local TINT = {
    [CP.Gather.SKINNING] = { 0.86, 0.62, 0.36 },
    [CP.Gather.HERBALISM] = { 0.45, 0.86, 0.42 },
    [CP.Gather.MINING] = { 0.78, 0.80, 0.90 },
    [CP.Gather.COOKING] = { 0.95, 0.55, 0.45 },
}

local pools = { miniMark = {}, worldMark = {}, miniGrind = {}, worldGrind = {}, contGrind = {} }
local used = { miniMark = 0, worldMark = 0, miniGrind = 0, worldGrind = 0, contGrind = 0 }

-- Skill colours, as the profession window shows them, and red for not yet.
local SKILL_COLOR = { { 1, 0.5, 0.25 }, { 1, 1, 0 }, { 0.25, 0.75, 0.25 }, { 0.5, 0.5, 0.5 } }
RouteMap.SKILL_COLOR = SKILL_COLOR
local TOO_HIGH = { 0.9, 0.2, 0.2 }

-- The skills a redraw reads once, for every pin it makes; nil outside a redraw.
local skillsNow

-- A redraw registers the player's zone at once and the other zones a few at a time on
-- later frames (`queue`, `queued` steps done), so one frame never registers thousands of
-- pins. A new redraw drops what is left of the last one.
local queue, queued = {}, 0
local drawnZones = {}   -- [zone] = true for each zone the last draw placed
local runner

local function skillColor(prof, need)
    local rank = (skillsNow or CP.Gather.Skills())[prof]
    if not (rank and need) then return nil end
    if rank < need then return TOO_HIGH end
    return SKILL_COLOR[CP.GatherGuide.Difficulty(rank, need)]
end

-- A stop's shared spawn points, one line per mix: "Tin Vein 80% · Silver Vein 20%".
RouteMap.MIX_LINES = 3
function RouteMap.MixLines(stop)
    local byText = {}
    for spot in pairs(stop and stop.mixes or {}) do
        local text = CP.Gather.MixText(spot)
        byText[text] = (byText[text] or 0) + spot.n
    end
    local list = {}
    for text, n in pairs(byText) do list[#list + 1] = { text, n } end
    table.sort(list, function(a, b)
        if a[2] ~= b[2] then return a[2] > b[2] end
        return a[1] < b[1]
    end)
    local out = {}
    for i = 1, math.min(#list, RouteMap.MIX_LINES) do out[i] = list[i][1] end
    return out
end

-- A stop's tooltip: each herb or ore there, the skill it needs in its colour, and what
-- the player's guides still need from it.
local function stopTip(self)
    local p = self.stop
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(p.name or "Stop", 1, 1, 1)
    local names = {}
    for name in pairs(p.parts or {}) do names[#names + 1] = name end
    table.sort(names)
    local line = p.prof == CP.Gather.MINING and "Mining" or p.prof == CP.Gather.HERBALISM and "Herbalism" or nil
    -- One kind of node: its skill under the title. Several: each by name.
    for _, name in ipairs(names) do
        local about = p.about and p.about[name] or {}
        local c = skillColor(p.prof, about.skill) or { 0.9, 0.9, 0.9 }
        local right = line and about.skill and ("%s %d"):format(line, about.skill) or ""
        if #names == 1 then
            if right ~= "" then GameTooltip:AddLine(right, c[1], c[2], c[3]) end
        else
            GameTooltip:AddDoubleLine(name, right, 0.9, 0.9, 0.9, c[1], c[2], c[3])
        end
    end
    local mixes = RouteMap.MixLines(p)
    if #mixes > 0 then
        GameTooltip:AddLine("Spawns one of:", 0.6, 0.6, 0.6)
        for _, text in ipairs(mixes) do GameTooltip:AddLine(text, 0.9, 0.9, 0.9, true) end
    end
    -- Farm names no guide need.
    local wants = {}
    for item in pairs(not CP.Gather.RouteFarming() and p.items or {}) do
        if item > 0 then wants[#wants + 1] = CP.ItemName(item) or ("item " .. item) end
    end
    table.sort(wants)
    if #wants > 0 then GameTooltip:AddLine("Your guides need: " .. table.concat(wants, ", "), 1, 0.82, 0, true) end
    GameTooltip:Show()
end

-- A route stop: what it yields as a small round icon in a ring tinted by the skill
-- colour of its main node (the profession's tint when there's none).
local function pin(kind, size, color, stop)
    used[kind] = used[kind] + 1
    local f = pools[kind][used[kind]]
    if not f then
        f = CreateFrame("Frame")
        CP.MapPins.Adopt(f)
        f.ring = f:CreateTexture(nil, "ARTWORK")
        f.ring:SetAllPoints()
        f.ring:SetTexture(DOT)
        f.icon = f:CreateTexture(nil, "OVERLAY")
        f.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        local mask = f:CreateMaskTexture()
        mask:SetAllPoints(f.icon)
        mask:SetTexture(MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        f.icon:AddMaskTexture(mask)
        f.rim = f:CreateTexture(nil, "OVERLAY", nil, 1)
        f.rim:SetAllPoints()
        f.rim:SetTexture(RIM)
        S.AccentRing(f.rim)
        f:SetScript("OnEnter", stopTip)
        f:SetScript("OnLeave", GameTooltip_Hide)
        pools[kind][used[kind]] = f
    end
    f:SetSize(size, size)
    local about = stop and stop.about and stop.name and stop.about[stop.name]
    local tint = about and skillColor(stop.prof, about.skill) or color
    f.ring:SetVertexColor(tint[1], tint[2], tint[3], 1)
    local item = about and about.item
    f.icon:ClearAllPoints()
    f.icon:SetPoint("TOPLEFT", 2, -2)
    f.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    f.icon:SetTexture(item and C_Item.GetItemIconByID(item) or nil)
    f.icon:SetShown(item ~= nil)
    f.stop = stop
    f:SetAlpha(pinAlpha)
    f.alpha, f.dimmed = pinAlpha, pinAlpha < 1
    f:EnableMouse(stop ~= nil)
    return f
end

-- A minimap stop: one small open ring in the node's colour, with no icon and no accent
-- rim. The game's own tracking blip sits on the same spot and stays the main mark.
RouteMap.MINI_STOP = 6   -- minimap stop size in pixels
local STOP_RING = MEDIA .. "StopRing"

local function hollow(f)
    f.ring:SetTexture(STOP_RING)
    f.icon:Hide()
    f.rim:Hide()
    return f
end

-- A minimap stop pin outside the pools, for tests.
function RouteMap.TestMiniStop(stop)
    local f = hollow(pin("miniMark", RouteMap.MINI_STOP, { 1, 1, 1 }, stop))
    used.miniMark = used.miniMark - 1
    return f
end

-- The materials a grind spot is for, by name: "Light Leather, Thick Leather".
function RouteMap.SpotFor(spot)
    local names = {}
    for item in pairs(spot.items or {}) do
        if item > 0 then names[#names + 1] = CP.ItemName(item) or ("item " .. item) end
    end
    table.sort(names)
    return table.concat(names, ", ")
end

-- A grind spot marker: the main item's icon, rounded, in ProfLost's brass ring, with its
-- rank on a small badge. Its tooltip names the materials it's for and lists every
-- creature there, biggest share first.
local function grindTip(self)
    local spot = self.spot
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(("Grind spot %d of %d"):format(spot.rank or 1, spot.of or self.of or 1), 1, 1, 1)
    local mats = RouteMap.SpotFor(spot)
    if mats ~= "" then GameTooltip:AddLine("For " .. mats, 1, 1, 1) end
    GameTooltip:AddLine("Click: waypoint here", 0.6, 0.6, 0.6)
    local list = {}
    for name, v in pairs(spot.parts or {}) do list[#list + 1] = { name, v } end
    table.sort(list, function(a, b) return a[2] > b[2] end)
    for _, e in ipairs(list) do
        local about = spot.about and spot.about[e[1]]
        local left = e[1]
        if about and about.minLevel then
            left = about.minLevel == about.maxLevel and ("%s (%d)"):format(e[1], about.minLevel)
                or ("%s (%d-%d)"):format(e[1], about.minLevel, about.maxLevel)
        end
        local drops = {}
        for item, chance in pairs(about and about.drops or {}) do
            local name = CP.ItemName(item) or ("item " .. item)
            drops[#drops + 1] = ("%s %d%%"):format(name, math.floor(chance + 0.5))
        end
        table.sort(drops)
        GameTooltip:AddDoubleLine(left, table.concat(drops, ", "), 0.9, 0.9, 0.9, 0.6, 0.6, 0.6)
        if about and about.how == "estimated" then GameTooltip:AddLine("  " .. RouteMap.ESTIMATED, 0.6, 0.6, 0.6) end
    end
    GameTooltip:Show()
end

local function grindPin(kind, size, color, spot)
    used[kind] = used[kind] + 1
    local f = pools[kind][used[kind]]
    if not f then
        f = CreateFrame("Frame")
        CP.MapPins.Adopt(f)
        f.icon = f:CreateTexture(nil, "ARTWORK")
        f.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        local mask = f:CreateMaskTexture()
        mask:SetAllPoints(f.icon)
        mask:SetTexture(MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        f.icon:AddMaskTexture(mask)
        f.border = f:CreateTexture(nil, "OVERLAY")
        f.border:SetAllPoints()
        f.border:SetTexture(RING_MONO)
        S.AccentRing(f.border)
        f.badge = f:CreateTexture(nil, "OVERLAY", nil, 1)
        f.badge:SetTexture(BADGE)
        f.badge:SetSize(12, 12)
        f.badge:SetPoint("CENTER", f, "BOTTOMRIGHT", -2, 2)
        f.rank = f:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
        f.rank:SetDrawLayer("OVERLAY", 2)
        f.rank:SetPoint("CENTER", f.badge, "CENTER", 0, 0)
        f:EnableMouse(true)
        f:SetScript("OnEnter", grindTip)
        f:SetScript("OnLeave", GameTooltip_Hide)
        -- A click sets the waypoint to the spot.
        f:SetScript("OnMouseUp", function(self, button)
            if button ~= "LeftButton" or not self.zone then return end
            local spot = self.spot
            local mats = RouteMap.SpotFor(spot)
            CP.Waypoint.PlaceOnMap(self.zone, spot.x, spot.y, ("Grind spot %d: %s"):format(spot.rank or 1,
                mats ~= "" and mats or spot.name or ""))
        end)
        pools[kind][used[kind]] = f
    end
    f:SetSize(size, size)
    -- The icon fills the ring's opening, with a pixel of overlap under the brass.
    local inset = math.floor(size * (1 - RING_HOLE) / 2)
    f.icon:ClearAllPoints()
    f.icon:SetPoint("TOPLEFT", inset, -inset)
    f.icon:SetPoint("BOTTOMRIGHT", -inset, inset)
    f.icon:SetTexture(spot.itemID and C_Item.GetItemIconByID(spot.itemID) or "Interface\\Icons\\INV_Misc_QuestionMark")
    f.spot = spot
    f:SetAlpha(pinAlpha)
    f.alpha, f.dimmed = pinAlpha, pinAlpha < 1
    f.rank:SetText(spot.rank or "")
    f.badge:SetShown(spot.rank ~= nil)
    return f
end

-- A grind pin outside the pools, for tests.
function RouteMap.TestPin(spot, zone)
    local f = grindPin("worldGrind", 26, { 1, 1, 1 }, spot)
    f.zone = zone
    used.worldGrind = used.worldGrind - 1
    return f
end

-- A route stop pin outside the pools, for tests. `stop` is optional.
function RouteMap.TestStop(stop)
    local f = pin("worldMark", 16, { 1, 1, 1 }, stop)
    used.worldMark = used.worldMark - 1
    return f
end

-- `here` is the player's zone: minimap, its zone map and the continent. `others[zone]`
-- holds every other zone on the continent, solved only with "Other zones". A zone the
-- player picked to plan ahead takes `here` with `away` set: its zone map and the continent
-- only, no minimap trail until the player is there.
local here = {}
local others = {}           -- [zone] = { key, result }
local current = here
local jobs = {}             -- here, others: the player's zone always runs first
local pass = { key = nil }  -- what the last other-zones pass was started for

function RouteMap.Clear()
    Pins:RemoveAllMinimapIcons(REF)
    Pins:RemoveAllWorldMapIcons(REF)
    for k in pairs(used) do used[k] = 0 end
    wipe(queue)
    wipe(drawnZones)
    queued, skillsNow = 0, nil
end

-- True while the map button shows the route's line, stops and grind spots
-- (CP.db.routeOnMap). The solves and the gathering panel never read it.
function RouteMap.LineShown()
    return CP.db == nil or CP.db.routeOnMap ~= false
end

-- `dim` is another zone's slot. Without `onMinimap`, no pin or line goes on the minimap.
local function drawSlot(zone, result, onMinimap, dim)
    local accent = S.color.accent
    drawnZones[zone] = true
    local own = dim and RouteMap.DIM or 1
    local away = dim and RouteMap.DIM or 1
    if not RouteMap.LineShown() then return end
    for _, spot in ipairs(result.spots or {}) do
        local tint = TINT[spot.prof] or accent
        pinAlpha = own
        local world = grindPin("worldGrind", 26, tint, spot)
        world.of, world.zone = spot.of or #result.spots, zone
        -- The waypoint layer sits above the area-POI layer most addons' pins use.
        Pins:AddWorldMapIconMap(REF, world, zone, spot.x, spot.y, RouteMap.GRIND_FLAG, "PIN_FRAME_LEVEL_WAYPOINT_LOCATION")
        local top, cx, cy = CP.Waypoint.OnContinent(zone, spot.x, spot.y)
        if top then
            pinAlpha = away
            local cont = grindPin("contGrind", 26, tint, spot)
            cont.of, cont.zone = spot.of or #result.spots, zone
            Pins:AddWorldMapIconMap(REF, cont, top, cx, cy, RouteMap.GRIND_FLAG, "PIN_FRAME_LEVEL_WAYPOINT_LOCATION")
        end
        pinAlpha = own
        if onMinimap then
            local mini = grindPin("miniGrind", 18, tint, spot)
            mini.of, mini.zone = spot.of or #result.spots, zone
            Pins:AddMinimapIconMap(REF, mini, zone, spot.x, spot.y, false, true)
            mini:SetFrameLevel(mini:GetFrameLevel() + 20)
        end
    end
    local lineOpts = dim and { alpha = RouteMap.DIM, noMini = true } or not onMinimap and { noMini = true } or nil
    CP.RouteLines.Set(zone, #result.loop >= 2 and (result.path or result.loop) or nil, accent, lineOpts)
    pinAlpha = own
    for _, p in ipairs(result.loop) do
        local tint = TINT[p.prof] or accent
        if onMinimap then
            Pins:AddMinimapIconMap(REF, hollow(pin("miniMark", RouteMap.MINI_STOP, tint, p)), zone, p.x, p.y, false, false)
        end
        Pins:AddWorldMapIconMap(REF, pin("worldMark", 16, tint, p), zone, p.x, p.y, RouteMap.STOP_FLAG)
    end
end

-- Other zones are solved and drawn with "Other zones", in either route mode.
local function othersOn()
    return CP.db.route ~= false and CP.db.mapIcons ~= false and CP.db.otherZones or false
end
RouteMap.OthersOn = othersOn

RouteMap.DRAW_PINS = 400   -- world map pins one frame registers at most (a zone is never split)

-- The world map pins a zone's draw registers.
local function cost(result)
    return #(result.spots or {}) * 2 + #(result.loop or {})
end

-- Runs queued zones for this frame while the next one fits the pin budget. A zone over
-- the budget runs alone.
local function drawQueued()
    local spent = 0
    while queued < #queue do
        local step = queue[queued + 1]
        if spent > 0 and spent + step.cost > RouteMap.DRAW_PINS then break end
        queued = queued + 1
        spent = spent + step.cost
        CP.RouteLines.Batch(step.run)
        pinAlpha = 1
    end
    if queued >= #queue then
        wipe(queue)
        queued, skillsNow = 0, nil
    end
end

local function drawAll()
    RouteMap.Clear()
    CP.RouteLines.Clear()
    skillsNow = CP.Gather.Skills()
    -- "Icons on the map" off: no pins or lines at all; the solves stay.
    if CP.db.mapIcons == false then
        skillsNow = nil
        return
    end
    if here.result and here.zone then drawSlot(here.zone, here.result, not here.away, false) end
    local zones = {}
    if RouteMap.OthersOn() then
        for zone, slot in pairs(others) do
            if slot.result and zone ~= here.zone then zones[#zones + 1] = zone end
        end
        table.sort(zones)
        for _, zone in ipairs(zones) do
            local result = others[zone].result
            queue[#queue + 1] = { cost = cost(result), run = function() drawSlot(zone, result, false, true) end }
        end
    end
    if #queue == 0 then skillsNow = nil end
end

local function draw()
    CP.RouteLines.Batch(drawAll)
    pinAlpha = 1
    if #queue > 0 then drawQueued() end
    if #queue > 0 and runner then runner:Show() end
    if CP.MapButton then CP.MapButton.Sync() end
end

-- True while a solve holds a loop or grind spots to draw: the player's zone, or another zone's.
local function drawable(result)
    return result ~= nil and (#(result.loop or {}) > 0 or #(result.spots or {}) > 0)
end

function RouteMap.HasRoute()
    if drawable(here.result) then return true end
    for _, slot in pairs(others) do
        if drawable(slot.result) then return true end
    end
    return false
end

-- The map button flipped CP.db.routeOnMap: draw again from the solves held.
function RouteMap.LineChanged()
    draw()
end

-- The grind spots drawn now for the player's zone (for /proflost border), or an empty list.
function RouteMap.Spots()
    local r = here.result
    return r and r.spots or {}, here.zone
end

-- The player's zone's loop stops, as drawn.
function RouteMap.Stops()
    local r = here.result
    return r and r.loop or {}
end

-- The player's zone's walking line as drawn (stops carry a `value`), or nil.
function RouteMap.Path()
    local r = here.result
    return r and r.path
end

-- What the player's zone was last solved from, for the simulator's route check: the zone,
-- the rows the last Update handed in, and the stops and creatures the drawn solve read
-- ({ nodes, mobs, level }). Nil while nothing is solved or a solve runs.
function RouteMap.Solved()
    if jobs.here or not (here.solved and here.handed and here.inputs) then return nil end
    return here.solved, here.handed, here.inputs
end

-- The other zones with something drawn, lowest id first, for tests.
function RouteMap.Others()
    local zones = {}
    for zone, slot in pairs(others) do
        if slot.result then zones[#zones + 1] = zone end
    end
    table.sort(zones)
    return zones
end

-- The zones whose pins and lines the last draw placed, { [zone] = true }, for the simulator.
function RouteMap.Drawn()
    local out = {}
    for zone in pairs(drawnZones) do out[zone] = true end
    return out
end

-- "4.5k yd loop · 3 grind spots" for what's drawn, or nil.
function RouteMap.Status()
    local r = current.result
    if not r then return nil end
    local parts = {}
    if #r.loop > 1 then parts[#parts + 1] = ("%.1fk yd loop"):format(r.length / 1000) end
    local spots = #(r.spots or {})
    if spots == 1 then parts[#parts + 1] = "1 grind spot" end
    if spots > 1 then parts[#parts + 1] = ("%d grind spots"):format(spots) end
    return #parts > 0 and table.concat(parts, " · ") or nil
end

-- True while the player's zone is being solved. Every solve ends, done or failed, so
-- this always turns false.
function RouteMap.Solving()
    return jobs.here ~= nil
end

-- True while the other zones are being solved or their pins are still being drawn. A
-- pass ends too.
function RouteMap.Passing()
    return jobs.others ~= nil or #queue > 0
end

-- One job resumes per frame, the player's zone first.
runner = CreateFrame("Frame", nil, UIParent)
runner:Hide()
runner:SetScript("OnUpdate", function(self)
    if #queue > 0 then drawQueued() end
    local name = jobs.here and "here" or jobs.others and "others"
    if not name then
        if #queue == 0 then self:Hide() end
        return
    end
    local job = jobs[name]
    local ok, err = coroutine.resume(job)
    if not ok then
        if jobs[name] == job then
            jobs[name] = nil

            -- A failed solve of the player's zone ends with nothing drawn.
            if name == "here" then
                here.result, here.zone = nil, nil
                draw()
                if here.done then here.done() end
            end
        end
        -- The error goes to the bug report; chat gets a plain sentence.
        if CP.BugReport and CP.BugReport.Record then CP.BugReport.Record("route: " .. tostring(err)) end
        CP:Print("Couldn't draw the gathering route here. /proflost bug to report it.")
    elseif coroutine.status(job) == "dead" and jobs[name] == job then
        jobs[name] = nil
    end
    if not (jobs.here or jobs.others or #queue > 0) then self:Hide() end
end)

-- The skills the ring colours read, as one string.
local function skillSignature()
    local skills, parts = CP.Gather.Skills(), {}
    for _, id in ipairs(CP.Gather.PROFS) do parts[#parts + 1] = skills[id] or 0 end
    return table.concat(parts, ",")
end

-- The cache key for `zone`'s loop from `rows`: every input Route.Points reads. A skill-up
-- changes a row's creatures, nodes or chances while its item stays, so each
-- row's sources are in the key, and a skill-up that changes none of them keeps the loop. A batch of new footprints in the zone re-keys it.
local function keyOf(zone, rows)
    local parts = {}
    for _, row in ipairs(rows) do
        if row.need and not row.done then
            local s = { row.itemID }
            for _, src in ipairs(row.sources) do
                if (src.kind == "mob" or src.kind == "node") and src.entry then
                    s[#s + 1] = ("%s%d/%s/%s/%s"):format(src.kind == "mob" and "m" or "n", src.entry,
                        tostring(src.chance), tostring(src.minLevel), tostring(src.maxLevel))
                end
            end
            parts[#parts + 1] = table.concat(s, ",")
        end
    end
    table.sort(parts)
    return zone .. ":" .. table.concat(parts, ";") .. ":" .. tostring(CP.Gather.PlayerLevel()) .. ":"
        .. CP.Gather.RouteSignature() .. ":" .. (CP.Terrain and CP.Terrain.batches[zone] or 0)
end
RouteMap.KeyOf = keyOf

-- `zone`'s loop and grind spots for `rows`, or nil when there's nothing to draw.
-- `from` centres the loop. Yields through `tick`, and through `light` for a point's work.
local function solveZone(zone, rows, from, tick, light)
    local level = CP.Gather.PlayerLevel()
    local nodes = Route.Points(zone, rows, nil, "node", nil, light)
    local mobs = Route.Points(zone, rows, nil, "mob", level, light)
    tick()
    local zw, zh = CP.Gather.ZoneSize(zone)
    local grid = #nodes > 1 and CP.Terrain.Grid(zone, zw, zh, { side = UnitFactionGroup("player"), level = level }, light)
        or nil
    tick()
    local farming = CP.Gather.RouteFarming()
    local result = #nodes > 0 and Route.Solve(nodes, zw, zh, tick, farming and Route.FARM_YD or nil, grid or nil, from)
        or { loop = {}, length = 0 }
    result.spots = Route.GrindSpotsByProf(mobs, zw, zh, nil, nil, nil, zone, tick)
    local inputs = { nodes = nodes, mobs = mobs, level = level }
    if #result.loop == 0 and #result.spots == 0 then return nil, inputs end
    return result, inputs
end

-- Solve the player's loop for `zone` and `rows` in the background, then redraw. `away`: a
-- picked zone the player is not in, centred on no spot of theirs.
local function solveHere(zone, rows, done, away)
    away = away and true or false
    if CP.db.route == false or not zone or not CP.Gather.ZoneSize(zone) then
        here.key, here.result, here.zone, here.rows, here.handed, here.inputs = nil, nil, nil, 0, nil, nil
        here.asked = nil
        jobs.here = nil
        draw()
        if done then done() end
        return
    end
    here.handed, here.asked = rows, zone
    local key = RouteMap.KeyOf(zone, rows)
    if key == here.key and away ~= here.away then
        -- The player walked into the zone they picked: the same loop, now on the minimap too.
        here.away = away
        draw()
        return
    end
    if key == here.key then
        -- A skill-up can change a ring's colour and no route source.
        local colours = skillSignature()
        if colours ~= here.colours then
            here.colours = colours
            draw()
        end
        return
    end
    here.colours = skillSignature()
    here.key, here.rows, here.done, here.away = key, #rows, done, away
    local from
    local pos = not away and C_Map.GetPlayerMapPosition(zone, "player")
    local px, py
    if pos then px, py = pos:GetXY() end
    if px and py then from = { x = px, y = py } end
    local job
    job = coroutine.create(function()
        local start, lights = debugprofilestop(), 0
        local function tick()
            if debugprofilestop() - start > FRAME_MS then
                coroutine.yield()
                start = debugprofilestop()
            end
        end
        local function light()
            lights = lights + 1
            if lights % LIGHT_EVERY == 0 then tick() end
        end
        CP.Gather.JobTick(light)
        local result, inputs = solveZone(zone, rows, from, tick, light)
        if here.key ~= key then return end

        -- The job ends before `done` runs, so `done` sees Solving() false.
        if jobs.here == job then jobs.here = nil end
        here.result, here.zone, here.solved, here.inputs = result, result and zone or nil, zone, inputs
        draw()
        if done then done() end
    end)
    jobs.here = job
    runner:Show()
end

-- Other zones ---------------------------------------------------------------------

local CONTINENT, ZONE = 2, 3   -- Enum.UIMapType
local continentZones = {}      -- [continent] = sorted outdoor zone ids with gathering data

-- The continent map holding `zone`, or nil (instances, unknown maps).
local function continentOf(zone)
    local id, hops = zone, 0
    while id and hops < 8 do
        local info = C_Map.GetMapInfo(id)
        if not info then return nil end
        if info.mapType == CONTINENT then return id end
        id, hops = info.parentMapID, hops + 1
    end
end

RouteMap.ContinentOf = continentOf

-- The outdoor zones on `continent` that have gathering data, lowest id first.
function RouteMap.ContinentZones(continent)
    local list = continentZones[continent]
    if list then return list end
    list = {}
    for zone in pairs(CP.GatherData.zones) do
        if zone < CP.Gather.INSTANCE then
            local info = C_Map.GetMapInfo(zone)
            if info and info.mapType == ZONE and continentOf(zone) == continent then list[#list + 1] = zone end
        end
    end
    table.sort(list)
    continentZones[continent] = list
    return list
end

-- What every other zone's loop depends on, cheaply: the player's zone and continent,
-- skills, level, filter, map answers, and the items the guides still need (none in Farm).
local function passKey(zone, continent)
    local skills = CP.Gather.Skills()
    local parts = { zone, continent, here.asked or 0, CP.Gather.PlayerLevel(), CP.Gather.RouteSignature(),
        CP.Gather.MapEpoch() }
    for _, id in ipairs(CP.Gather.PROFS) do parts[#parts + 1] = skills[id] or 0 end
    local wanted = {}
    for item, n in pairs(not CP.Gather.RouteFarming() and (CP.Gather.Needs()) or {}) do
        if CP.Purchases.Have(item) < n then wanted[#wanted + 1] = item end
    end
    table.sort(wanted)
    parts[#parts + 1] = table.concat(wanted, ",")
    return table.concat(parts, "|")
end

-- The last finished pass: zones looked at, zones solved, frames it took, milliseconds of
-- work in all, the longest single frame's work, and seconds from start to finish.
RouteMap.lastPass = { zones = 0, solved = 0, frames = 0, ms = 0, longest = 0, seconds = 0 }

local function dropOthers()
    jobs.others, pass.key = nil, nil
    if next(others) then
        wipe(others)
        draw()
    end
end

-- Solve every other zone on the player's continent, unless nothing they depend on changed.
-- A zone's loop is kept by its key, so a pass re-solves only the zones whose rows changed.
local function solveOthers()
    if not RouteMap.OthersOn() then return dropOthers() end
    local zone = CP.Gather.PlayerZone()
    local continent = zone and continentOf(zone)
    if not continent then return dropOthers() end
    local key = passKey(zone, continent)
    if key == pass.key then return end
    pass.key = key
    local zones = RouteMap.ContinentZones(continent)
    local GL = CP.GatherList
    local job
    job = coroutine.create(function()
        local stats = { zones = 0, solved = 0, frames = 1, ms = 0, longest = 0, seconds = 0 }
        local began = GetTime()
        local start, lights = debugprofilestop(), 0
        local function spend()
            local spent = debugprofilestop() - start
            stats.ms, stats.longest = stats.ms + spent, math.max(stats.longest, spent)
        end
        local function tick()
            if debugprofilestop() - start > FRAME_MS then
                spend()
                coroutine.yield()
                stats.frames = stats.frames + 1
                start = debugprofilestop()
            end
        end
        local function light()
            lights = lights + 1
            if lights % LIGHT_EVERY == 0 then tick() end
        end
        -- Cluster builds inside each zone's rows (Gather.Farmable) yield through it too.
        CP.Gather.JobTick(light)
        local keep = {}

        -- The listed zone has its own slot. The player's zone does too, unless a picked zone holds it.
        local away = here.asked and here.asked ~= zone
        for _, z in ipairs(zones) do
            if z ~= here.asked and (away or z ~= zone) and CP.Gather.ZoneSize(z) then
                stats.zones = stats.zones + 1
                local rows = GL.RouteRows(z, nil, true, GL.OTHER_OPTS)
                tick()
                local k = #rows > 0 and RouteMap.KeyOf(z, rows)
                if k and others[z] and others[z].key == k then
                    keep[z] = others[z]
                elseif k then
                    stats.solved = stats.solved + 1
                    keep[z] = { key = k, rows = #rows, result = solveZone(z, rows, nil, tick, light) }
                    tick()
                end
            end
        end
        spend()
        if jobs.others ~= job then return end
        wipe(others)
        for z, slot in pairs(keep) do others[z] = slot end
        stats.seconds = GetTime() - began
        RouteMap.lastPass = stats
        draw()
    end)
    jobs.others = job
    runner:Show()
end

-- Solve and draw the loop for the player's `zone` and the checklist `rows`, unless it's
-- already up, then every other zone on the continent when that's on. `done()` runs
-- once the player's route is drawn or cleared. `away`: `zone` is one the player picked to
-- plan ahead and is not in, drawn on the world map only.
function RouteMap.Update(zone, rows, done, away)
    solveHere(zone, rows, done, away)
    solveOthers()
end

-- True while the drawn loop is for a picked zone the player is not in.
function RouteMap.Away()
    return here.away == true
end

-- "Other zones" was switched: drop the other zones, or solve them.
function RouteMap.Refresh()
    if not RouteMap.OthersOn() then return dropOthers() end
    solveOthers()
end

-- "Icons on the map" was switched: redraw or clear every pin and line, then the other zones.
function RouteMap.IconsChanged()
    draw()
    if RouteMap.OthersOn() then solveOthers() else dropOthers() end
end

-- The route filter changed: solve the other zones again.
function RouteMap.Revisit()
    pass.key = nil
    solveOthers()
end

-- Drops every solve, running or done, and the pins they drew, as a fresh login starts.
-- The test worlds call it between scenes.
function RouteMap.Forget()
    jobs.here, jobs.others, pass.key = nil, nil, nil
    here.key, here.result, here.zone, here.rows, here.solved, here.done = nil, nil, nil, 0, nil, nil
    here.handed, here.inputs, here.colours, here.away, here.asked = nil, nil, nil, nil, nil
    wipe(others)
    runner:Hide()
    draw()
end

-- Diagnostics ---------------------------------------------------------------------

-- Grind spot pins registered with HereBeDragons now, by the spot's zone: those on the
-- zone map, and those on the continent map.
function RouteMap.PinsByZone()
    local out, onContinent = {}, {}
    for icon in pairs(Pins.worldmapPinRegistry[REF] or {}) do
        local data = Pins.worldmapPins[icon]
        local zone = icon.zone
        if data and icon.spot and zone and data.uiMapID then
            local t = data.uiMapID == zone and out or onContinent
            t[zone] = (t[zone] or 0) + 1
        end
    end
    return out, onContinent
end

-- Chat lines for `/proflost zones`: whether a pass runs, the last pass's timing, then each
-- zone solved (the player's first) with its rows, grind spots and the pins drawn now.
local function mapName(id)
    local info = id and C_Map.GetMapInfo(id)
    return info and info.name or tostring(id)
end

function RouteMap.ZonesReport()
    local pins, onContinent = RouteMap.PinsByZone()
    local function line(zone, rows, result, tag)
        local spots = result and #(result.spots or {}) or 0
        local text = ("%s (%d%s): %d rows, %d grind spots, %d pins drawn, %d on the continent"):format(mapName(zone), zone,
            tag or "", rows or 0, spots, pins[zone] or 0, onContinent[zone] or 0)
        local why = spots == 0 and (rows or 0) > 0 and CP.GatherList and CP.GatherList.SkinReason(zone)
        return why and (text .. "; no skinning spot: " .. why) or text
    end
    local lines = {}
    local running = jobs.here and "your zone solving" or jobs.others and "pass running" or "pass done"
    local on = CP.db and RouteMap.OthersOn() and "on" or "off"
    lines[1] = ("other zones %s; %s"):format(on, running)
    local p = RouteMap.lastPass
    lines[2] = ("last pass: %d zones looked at, %d solved, %.1f s over %d frames, %.0f ms work, longest frame %.1f ms")
        :format(p.zones, p.solved, p.seconds, p.frames, p.ms, p.longest)
    if here.solved then lines[#lines + 1] = line(here.solved, here.rows, here.result, ", yours") end
    local zones = {}
    for zone in pairs(others) do zones[#zones + 1] = zone end
    table.sort(zones)
    for _, zone in ipairs(zones) do lines[#lines + 1] = line(zone, others[zone].rows, others[zone].result) end
    return lines
end

-- A map's size in yards from the game's world transforms, width (west to east) first.
local function worldSize(id)
    local _, a = C_Map.GetWorldPosFromMapPos(id, CreateVector2D(0, 0))
    local inst, b = C_Map.GetWorldPosFromMapPos(id, CreateVector2D(0.5, 0.5))
    if not (a and b) then return nil end
    local ax, ay = a:GetXY()
    local bx, by = b:GetXY()
    return math.abs(ay - by) * 2, math.abs(ax - bx) * 2, inst
end

local function size(w, h)
    if not (w and h and w > 0) then return "none" end
    return ("%.0fx%.0f"):format(w, h)
end

local function at(x, y)
    if not (x and y) then return "none" end
    return ("%.1f, %.1f"):format(x * 100, y * 100)
end

-- Chat lines for `/proflost pins`: the map the world map shows and the ProfLost grind pins on
-- it, then for each zone with grind spots its spot 1 on the zone map, on the continent
-- through HereBeDragons, and on the continent through the game's transforms (where the
-- pin goes), with both sizes of the zone. Last, both sizes of each continent.
function RouteMap.PinsReport()
    local HBD = LibStub("HereBeDragons-2.0")
    local lines = {}
    local map = _G.WorldMapFrame
    local shown = map and map:IsShown() and map:GetMapID()
    if shown then
        local n, mine = 0, Pins.worldmapPinRegistry[REF] or {}
        if map.EnumeratePinsByTemplate then
            for pin in map:EnumeratePinsByTemplate("HereBeDragonsPinsTemplate") do
                if pin.icon and mine[pin.icon] and pin.icon.spot then n = n + 1 end
            end
        end
        lines[1] = ("world map shows %s (%d): %d ProfLost grind pins on it"):format(mapName(shown), shown, n)
    else
        lines[1] = "world map closed"
    end
    local list = {}
    if here.zone and here.result then list[1] = { here.zone, here.result } end
    local zones = {}
    for zone, slot in pairs(others) do
        if slot.result and zone ~= here.zone then zones[#zones + 1] = zone end
    end
    table.sort(zones)
    for _, zone in ipairs(zones) do list[#list + 1] = { zone, others[zone].result } end
    local tops, seen = {}, {}
    for _, e in ipairs(list) do
        local zone, spot = e[1], e[2].spots and e[2].spots[1]
        if spot then
            local top, cx, cy = CP.Waypoint.OnContinent(zone, spot.x, spot.y)
            top = top or continentOf(zone)
            local hx, hy
            if top then hx, hy = HBD:TranslateZoneCoordinates(spot.x, spot.y, zone, top) end
            if top and not seen[top] then seen[top], tops[#tops + 1] = true, top end
            local cw, ch = worldSize(zone)
            lines[#lines + 1] = ("%s (%d) spot 1 at %s: HBD %s; C_Map %s on %s (%s); size HBD %s, C_Map %s yd")
                :format(mapName(zone), zone, at(spot.x, spot.y), at(hx, hy), at(cx, cy), mapName(top),
                    tostring(top), size(HBD:GetZoneSize(zone)), size(cw, ch))
        end
    end
    if #lines == 1 then lines[2] = "no grind spots drawn" end
    for _, top in ipairs(tops) do
        local cw, ch, inst = worldSize(top)
        local data = HBD.mapData and HBD.mapData[top]
        lines[#lines + 1] = ("%s (%d): HBD %s yd on instance %s, C_Map %s yd on instance %s"):format(mapName(top), top,
            size(HBD:GetZoneSize(top)), tostring(data and data.instance), size(cw, ch), tostring(inst))
    end
    return lines
end
