-- The gathering route goes only to herbs, ore and leather the player can gather now: the
-- profession known and the skill reached. Nodes above the skill are not stops, and a crafting
-- section row the player can't gather marks where it grows without starting a route
-- (owner, 2026-11-24: "why are we routing people to herbs and veins that they can't gather").

local CP = ProfLost
local G, GL, RM = CP.Gather, CP.GatherList, CP.RouteMap
local HBD = LibStub("HereBeDragons-2.0")
local HERB, MINE, SKIN = 182, 186, 393
local ALCHEMY, BS = 171, 164
local BARRENS, DUROTAR = 1413, 1411
local PEACEBLOOM, EARTHROOT, SWIFTTHISTLE, BRIARTHORN, MAGEROYAL = 2447, 2449, 2452, 2450, 785
local COPPER_ORE, ROUGH_STONE = 2770, 2835

local ranks = {}

-- The player in `zone` at `level`, Follow the guide, with gathering ranks `skills` and the
-- guides' needs `needs`.
local function scene(zone, level, skills, needs)
    MapWorld.begin({ zone = zone, x = 0.5, y = 0.5, level = level, side = "Horde" })
    World.set(HBD, "GetWorldCoordinatesFromZone", function(_, x, y, z) return x * 1000 + z, y * 1000, 1 end)
    for _, key in ipairs({ "routeMode", "routeSkip", "skinSkip", "gatherClosed", "farmClosed" }) do
        World.set(CP.db, key, nil)
    end
    World.set(CP.db, "route", true)
    World.set(CP.db, "otherZones", false)
    World.set(CP.db, "collect", true)
    World.set(CP.charDB, "gatherNeeds", needs)
    World.set(CP.charDB, "gatherSoon", nil)
    ranks = { [ALCHEMY] = 100, [BS] = 100 }
    for id, rank in pairs(skills) do ranks[id] = rank end
    World.set(C_SkillInfo, "GetSkillLineInfoByID", function(id)
        local rank = ranks[id]
        return rank and { skillID = id, rank = rank, modifier = 0, maxRank = 300 } or nil
    end)
    World.patch("C_Item.GetItemCount", function() return 0 end)
    World.set(G, "UpdateAllNeeds", function() end)
    World.set(CP.Waypoint, "MapPosZone", function(z) return z end)
    G.ResetClusters()
    World.onEnd(function()
        RM.Update(false, {})
        T.advance(1)
        G.ResetClusters()
    end)
end

-- The panel rebuilds and every solve it starts ends.
local function settle()
    GL.Refresh()
    local frames = 0
    repeat
        T.advance(0.05, 0.05)
        frames = frames + 1
    until not (CP.GatherGuide.Warming() or RM.Solving() or RM.Passing()) or frames > 4000
    GL.Refresh()
end

-- The highest skill any node at `stop` needs, and its profession.
local function stopSkill(stop)
    local most = 0
    for _, a in pairs(stop.about or {}) do most = math.max(most, a.skill or 0) end
    return most
end

-- Every point the map draws for the player's zone: loop stops and any other node marks.
local function drawnStops()
    local out = {}
    local loop, other = RM.Stops()
    for _, p in ipairs(loop or {}) do out[#out + 1] = p end
    for _, p in ipairs(other or {}) do out[#out + 1] = p end
    return out, loop or {}
end

-- Mapzeroth's route calls and the plain map pins set while `fn` runs.
local function clicks(fn)
    local routed, marked = {}, {}
    World.set(CP.Mapz, "Route", function(zone, x, y, name)
        routed[#routed + 1] = { zone = zone, x = x, y = y, name = name }
        return true
    end)
    World.patch("C_Map.CanSetUserWaypointOnMap", function() return true end)
    World.patch("C_Map.SetUserWaypoint", function(point) marked[#marked + 1] = point end)
    fn()
    return routed, marked
end

T.test("a Herbalism 50 player's route has no stop needing more than 50", function()
    scene(BARRENS, 30, { [HERB] = 50 }, { [ALCHEMY] = { [SWIFTTHISTLE] = 20, [BRIARTHORN] = 20, [MAGEROYAL] = 20 } })
    settle()
    for _, r in ipairs(GL.RouteRows(BARRENS, nil, true)) do
        for _, src in ipairs(r.sources) do
            if src.kind == "node" then
                T.ok((src.skill or 0) <= 50, ("route row source %s needs %s"):format(src.name, tostring(src.skill)))
            end
        end
    end
    local all, loop = drawnStops()
    T.ok(#loop > 0, "the Barrens loop has stops")
    for _, p in ipairs(all) do
        T.ok(stopSkill(p) <= 50, ("drawn stop %s needs %d"):format(tostring(p.name), stopSkill(p)))
    end
end)

T.test("a player without Mining gets no ore stops", function()
    scene(BARRENS, 30, { [HERB] = 50 }, { [BS] = { [COPPER_ORE] = 20, [ROUGH_STONE] = 20 },
        [ALCHEMY] = { [MAGEROYAL] = 20 } })
    World.set(CP.db, "otherZones", true)
    settle()
    for _, r in ipairs(GL.RouteRows(BARRENS, nil, true)) do
        for _, src in ipairs(r.sources) do
            T.ok(src.prof ~= MINE, "no Mining source in the route rows: " .. tostring(src.name))
        end
    end
    local all, loop = drawnStops()
    T.ok(#loop > 0, "the herb loop still has stops")
    for _, p in ipairs(all) do T.ok(p.prof ~= MINE, "no ore stop: " .. tostring(p.name)) end
end)

T.test("a crafting row the player can't gather marks where it grows and adds no route stops", function()
    -- No Herbalism: Peacebloom lists as "no Herbalism".
    scene(DUROTAR, 20, {}, { [ALCHEMY] = { [PEACEBLOOM] = 20 } })
    World.set(CP.Window, "Professions", function() return { { id = ALCHEMY, name = "Alchemy" } } end)
    World.set(CP.charDB, "panelProf", ALCHEMY)
    settle()
    local line
    for _, l in ipairs((GL.Drawn())) do
        if l.kind == "item" and l.row.itemID == PEACEBLOOM then line = l end
    end
    T.ok(line and line.row.lacks == "Herbalism", "a Peacebloom row that says no Herbalism")
    if not line then return end
    T.ok(line.pin ~= nil, "it keeps a pin to show where it grows")
    local routed, marked = clicks(line.pin)
    T.eq(#routed, 0, "the pin starts no Mapzeroth route")
    T.eq(#marked, 1, "the pin marks one spot on the map")
    for _, p in ipairs((drawnStops())) do T.ok(p.prof ~= HERB, "no herb stop: " .. tostring(p.name)) end
end)

T.test("a crafting row above the player's skill marks where it grows without a route", function()
    scene(DUROTAR, 20, { [HERB] = 5 }, { [ALCHEMY] = { [EARTHROOT] = 10 } })
    World.set(CP.Window, "Professions", function() return { { id = ALCHEMY, name = "Alchemy" } } end)
    World.set(CP.charDB, "panelProf", ALCHEMY)
    settle()
    local line
    for _, l in ipairs((GL.Drawn())) do
        if l.kind == "item" and l.row.itemID == EARTHROOT then line = l end
    end
    T.ok(line and (line.row.short or 0) > 5, "an Earthroot row with the rank it needs")
    if not line then return end
    local routed, marked = clicks(line.pin)
    T.eq(#routed, 0, "the pin starts no Mapzeroth route")
    T.eq(#marked, 1, "the pin marks one spot on the map")
    for _, p in ipairs((drawnStops())) do
        T.ok(stopSkill(p) <= 5, ("drawn stop %s needs %d"):format(tostring(p.name), stopSkill(p)))
    end
end)

T.test("a source line above the player's skill marks where it grows; one in reach routes", function()
    scene(BARRENS, 30, { [HERB] = 60 }, { [ALCHEMY] = { [SWIFTTHISTLE] = 20 } })
    settle()
    local row
    for _, r in ipairs(G.ForZone(BARRENS, { [HERB] = 300 }, GL.OTHER_OPTS)) do
        if r.itemID == SWIFTTHISTLE then row = setmetatable({ need = 20, have = 0 }, { __index = r }) end
    end
    T.ok(row ~= nil, "Swiftthistle grows in the Barrens")
    if not row then return end
    local seen = {}
    for _, l in ipairs(GL.SourceLines(row, BARRENS)) do
        if l.pin and l.src.kind == "node" then
            local routed, marked = clicks(l.pin)
            local reach = l.src.skill <= 60
            seen[reach] = true
            T.eq(#routed, reach and 1 or 0, l.src.name .. (reach and " routes" or " starts no route"))
            T.eq(#marked, reach and 0 or 1, l.src.name .. (reach and " leaves the map to the route" or " marks the map"))
        end
    end
    T.ok(seen[true] and seen[false], "one source in reach (Mageroyal) and one above (Briarthorn)")
end)

T.test("the gathering guide's waypoint goes to a target the player can gather now", function()
    -- Earthroot (15) is the one herb in reach; Mageroyal, Briarthorn and the rest are above it.
    scene(BARRENS, 30, { [HERB] = 15 }, {})
    local D, targets, reach = CP.GatherData, {}, {}
    for entry, n in pairs(D.nodes) do
        if n[4] == HERB and n[2] and n[2] >= 15 and (D.zones[BARRENS].nodes or {})[entry] then
            targets[#targets + 1] = { kind = "nodes", entry = entry, name = n[1], req = n[2] }
            if n[2] <= 15 then reach[n[1]] = true end
        end
    end
    T.ok(next(reach) ~= nil and #targets > 2, "Barrens herbs in reach at 15 and above it")
    local spot = CP.GatherGuide.Spot(BARRENS, targets)
    T.ok(spot and reach[spot.name], "the spot is a herb in reach: " .. tostring(spot and spot.name))
end)

T.test("a mark sets a map pin with no tracked arrow and says where", function()
    scene(DUROTAR, 20, {}, {})
    local lines, tracked = {}, nil
    World.set(CP, "Print", function(_, msg) lines[#lines + 1] = msg end)
    World.patch("C_SuperTrack.SetSuperTrackedUserWaypoint", function(on) tracked = on end)
    local routed, marked = clicks(function() CP.GatherList.MarkOnMap(DUROTAR, 0.25, 0.75, "Peacebloom") end)
    T.eq(#routed, 0, "no Mapzeroth route")
    T.eq(#marked, 1, "one map pin")
    T.eq(tracked, false, "the pin is not tracked")
    T.eq(lines[1], "Marked on the map: Peacebloom, " .. C_Map.GetMapInfo(DUROTAR).name .. " (25.0, 75.0).")
end)
