-- "Other zones": with the setting on, every other zone on the player's continent
-- is solved after the player's zone and drawn dimmed, on its zone map and the continent
-- map, never on the minimap. What is solved never follows the map the world map shows.
-- The pin rings take the player's accent. Continent pins: continentpins_test.

local CP = ProfLost
local RM = CP.RouteMap
local KALIMDOR = 1414

-- The world map's providers see `id` as the shown map, the way a map addon flips it.
local function showMap(id)
    World.set(WorldMapFrame, "GetMapID", function() return id end)
    World.set(WorldMapFrame, "IsShown", function() return true end)
    for provider in pairs(WorldMapFrame.dataProviders or {}) do
        if type(provider) == "table" and provider.OnMapChanged then provider:OnMapChanged() end
    end
end

-- Scene: the player stands in Durotar (1411), level 20 Horde (or `spec.zone` and `spec.side`), with
-- skinning and mining needs. `act(seen)` runs with the pin calls recorded in `seen`.
local function scene(act, spec)
    spec = spec or {}
    MapWorld.begin({ zone = spec.zone or 1411, x = 0.5, y = 0.5, level = 20, side = spec.side or "Horde",
                     shareSolves = true })
    local was = { CP.db.otherZones, CP.db.route }
    CP.db.route = true
    CP.charDB.gatherNeeds = { [165] = { [2318] = 200 }, [164] = { [2771] = 100 } }
    World.set(C_SkillInfo, "GetSkillLineInfoByID", function(id)
        if id == 393 or id == 186 then return { skillID = id, rank = 120, modifier = 0 } end
        return nil
    end)
    World.patch("C_Item.GetItemCount", function() return 0 end)
    local mapPos, replan = CP.Waypoint.MapPosZone, CP.Gather.UpdateAllNeeds
    CP.Gather.UpdateAllNeeds = function() end
    CP.Waypoint.MapPosZone = function(z) return z end
    CP.Gather.ResetClusters()
    local pins = LibStub("HereBeDragons-Pins-2.0")
    local seen = { world = {}, mini = {} }
    local addW, addM = pins.AddWorldMapIconMap, pins.AddMinimapIconMap
    pins.AddWorldMapIconMap = function(self, ref, icon, z, x, y, flag, ...)
        seen.world[#seen.world + 1] = { zone = z, owner = icon.zone or z, dimmed = icon.dimmed,
            alpha = icon.alpha, flag = flag, grind = icon.spot ~= nil }
        return addW(self, ref, icon, z, x, y, flag, ...)
    end
    pins.AddMinimapIconMap = function(self, ref, icon, z, ...)
        seen.mini[z] = (seen.mini[z] or 0) + 1
        return addM(self, ref, icon, z, ...)
    end
    function seen.reset() seen.world, seen.mini = {}, {} end
    function seen.zones()
        local out = {}
        for _, p in ipairs(seen.world) do out[p.zone] = (out[p.zone] or 0) + 1 end
        return out
    end
    local ok, err = pcall(act, seen)
    CP.db.otherZones, CP.db.route = false, false
    RM.Update(false, {})
    T.advance(1)
    pins.AddWorldMapIconMap, pins.AddMinimapIconMap = addW, addM
    CP.Waypoint.MapPosZone, CP.Gather.UpdateAllNeeds = mapPos, replan
    CP.Gather.ResetClusters()
    -- Set back last: a redraw with the route on under this scene's map answers would cache them.
    CP.db.otherZones, CP.db.route = was[1], was[2]
    T.ok(ok, err)
end

-- How many Kalimdor zones an "Other zones" pass looks at for `side` standing in `here`: every
-- zone with a size but theirs and the other faction's territory.
local function lookable(side, here)
    local n = 0
    for _, z in ipairs(RM.ContinentZones(KALIMDOR)) do
        if z ~= here and CP.Gather.ZoneSize(z) and not CP.Gather.EnemyGround(z, side) then n = n + 1 end
    end
    return n
end

-- The player's zone loop, as the gathering panel asks for it.
local function update()
    CP.GatherList.RouteOnly()
    T.advance(5)
end

T.test("the continent's zones are its outdoor zones with gathering data", function()
    MapWorld.begin({ zone = 1411 })
    local zones = RM.ContinentZones(KALIMDOR)
    T.ok(#zones >= 20, "Kalimdor zones: " .. #zones)
    for _, z in ipairs(zones) do
        T.ok(z < CP.Gather.INSTANCE, "no instance")
        T.eq(C_Map.GetMapInfo(z).mapType, 3, "a zone map")
    end
    local has = {}
    for _, z in ipairs(zones) do has[z] = true end
    T.ok(has[1411] and has[1413] and has[1440], "Durotar, the Barrens, Ashenvale")
    T.ok(not has[1429], "no Eastern Kingdoms zone")
end)

T.test("by default only the player's zone is drawn, on its zone map and the continent", function()
    scene(function(seen)
        CP.db.otherZones = false
        update()
        local zones = seen.zones()
        T.ok((zones[1411] or 0) > 0, "the player's zone is drawn")
        for z in pairs(zones) do T.ok(z == 1411 or z == KALIMDOR, "and nothing else: " .. z) end
        T.eq(#RM.Others(), 0)
        local grind = 0
        for _, p in ipairs(seen.world) do
            T.ok(not p.dimmed and p.alpha == 1, "full")
            if p.grind then
                grind = grind + 1
                T.eq(p.flag, nil, "a grind pin shows only on its own map")
            end
        end
        T.ok(grind > 0, "grind spots drawn")
        T.ok((seen.mini[1411] or 0) > 0, "on the minimap")
    end)
end)

T.test("with other zones on, every continent zone with needs is solved, dimmed and off the minimap", function()
    scene(function(seen)
        CP.db.otherZones = true
        update()
        local others = RM.Others()
        T.ok(#others >= 5, "zones solved: " .. table.concat(others, ","))
        local zones = seen.zones()
        for _, z in ipairs(others) do
            T.ok(z ~= 1411, "the player's zone isn't an other zone")
            T.ok((zones[z] or 0) > 0, "zone " .. z .. " drawn")
            T.eq(seen.mini[z], nil, "zone " .. z .. " not on the minimap")
        end
        local otherGrind = 0
        for _, p in ipairs(seen.world) do
            if p.owner == 1411 then
                T.ok(not p.dimmed and p.alpha == 1, "the player's zone stays full")
            else
                T.ok(p.dimmed, "dimmed")
                T.eq(p.alpha, RM.DIM)
            end
            if p.grind then
                T.eq(p.flag, nil, "every grind pin shows only on its own map")
                if p.zone ~= 1411 and p.zone ~= KALIMDOR then otherGrind = otherGrind + 1 end
            end
        end
        T.eq(RM.DIM, 0.7)
        T.ok(otherGrind > 0, "other zones' grind spots drawn")
        T.eq(RM.lastPass.zones, lookable("Horde", 1411), "zones looked at: the continent's, less Alliance ground")
    end)
end)

-- Owner, 2026-11-27: "Enemy territory: there's always an alternative spot" (Gather.EnemyGround).
T.test("other zones leave out the other faction's territory", function()
    local horde = { [1411] = true, [1412] = true, [1413] = true, [1454] = true, [1456] = true }
    scene(function()
        CP.db.otherZones = true
        update()
        local others = RM.Others()
        T.ok(#others >= 5, "zones solved: " .. table.concat(others, ","))
        for _, z in ipairs(others) do T.ok(not horde[z], "an Alliance character's other zone is Horde ground: " .. z) end
    end, { zone = 1440, side = "Alliance" })
end)

T.test("the shown map id changes nothing: zone map, continent map, another zone", function()
    scene(function(seen)
        CP.db.otherZones = true
        update()
        local others = table.concat(RM.Others(), ",")
        local pass = RM.lastPass
        local drawn = #seen.world
        seen.reset()
        for _, id in ipairs({ 1413, KALIMDOR, 1440, 1411 }) do
            showMap(id)
            T.advance(2)
        end
        T.eq(#seen.world, 0, "no pin registered again")
        T.eq(table.concat(RM.Others(), ","), others)
        T.ok(RM.lastPass == pass, "no new pass")
        T.ok(drawn > 0)
        T.eq(CP.RouteLines.onWorldMap, nil, "no map hook")
        T.eq(RM.View, nil)
    end)
end)

T.test("the other zones are kept until what they depend on changes", function()
    scene(function()
        CP.db.otherZones = true
        update()
        local first = RM.lastPass
        T.ok(first.solved >= 5, "first pass solves: " .. first.solved)
        update()
        T.ok(RM.lastPass == first, "same needs, skills and level: no pass")
        -- A bag change that leaves every need short starts no pass either.
        World.patch("C_Item.GetItemCount", function() return 3 end)
        update()
        T.ok(RM.lastPass == first, "still short: no pass")
        MapWorld.SetLevel(21)
        update()
        T.ok(RM.lastPass ~= first, "a new level starts a pass")
        T.ok(RM.lastPass.solved > 0)
    end)
end)

T.test("switching other zones off clears them at once, on solves them again", function()
    scene(function(seen)
        CP.db.otherZones = true
        update()
        T.ok(#RM.Others() > 0)
        CP.db.otherZones = false
        seen.reset()
        RM.Refresh()
        T.eq(#RM.Others(), 0, "cleared at once")
        T.ok(not CP.RouteLines.Has(1413))
        CP.db.otherZones = true
        RM.Refresh()
        T.advance(5)
        T.ok(#RM.Others() > 0, "solved and drawn again")
    end)
end)

T.test("other zones solve a slice a frame, after the player's zone", function()
    scene(function()
        -- Each look at the clock costs 1 ms here.
        local ms = 0
        World.set(_G, "debugprofilestop", function()
            ms = ms + 1
            return ms
        end)
        CP.db.otherZones = true
        CP.GatherList.RouteOnly()
        T.ok(#RM.Others() == 0, "nothing solved in the call itself")
        for _ = 1, 2000 do
            if select(2, RM.Spots()) == 1411 then break end
            T.advance(0.02)
        end
        T.eq(select(2, RM.Spots()), 1411, "the player's zone is drawn")
        T.eq(#RM.Others(), 0, "other zones still waiting")
        local seconds = 0
        while #RM.Others() == 0 and seconds < 1200 do
            T.advance(1)
            seconds = seconds + 1
        end
        local pass = RM.lastPass
        T.ok(#RM.Others() > 0, "solved in the end, after " .. seconds .. " s")
        T.ok(pass.zones == lookable("Horde", 1411) and pass.frames > pass.solved,
            ("%d zones, %d solved, %d frames"):format(pass.zones, pass.solved, pass.frames))
        -- A slice ends at the first look past FRAME_MS (5 ms), give or take the few looks
        -- between ticks.
        T.ok(pass.longest < 10, ("longest slice %d looks"):format(pass.longest))
    end)
end)

T.test("route lines show on their zone map and on the continent map", function()
    scene(function()
        CP.db.otherZones = true
        update()
        T.ok(CP.RouteLines.Has(1411) and CP.RouteLines.Has(1413), "loops kept")
        showMap(1413)
        local zoneLines = CP.RouteLines.Counts()
        T.ok(zoneLines > 0, "the Barrens' map has lines")
        showMap(KALIMDOR)
        local continentLines = CP.RouteLines.Counts()
        T.ok(continentLines > zoneLines, ("continent %d lines, Barrens %d"):format(continentLines, zoneLines))
        showMap(1429)
        T.eq((CP.RouteLines.Counts()), 0, "Elwynn has none")
    end)
end)

T.test("the pin rings take the accent and follow it when the style changes", function()
    local painted = {}
    local saved = rawget(_G, "DaylightUI")
    World.set(_G, "DaylightUI", { API = { major = 1, Colors = function() return {} end,
        Accent = function() return 0.2, 0.4, 0.9 end },
        Style = { PaintAccent = function(t) painted[t] = (painted[t] or 0) + 1 end } })
    local ok, err = pcall(function()
        local grind = RM.TestPin({ x = 0.3, y = 0.4, rank = 1, name = "Wolves", items = {}, parts = {} }, 1421)
        local stop = RM.TestStop()
        -- Pins come from pools, so a ring may predate the stub: a style change repaints it.
        CP.Style.Repaint()
        T.eq(painted[grind.border], 1, "the grind ring is painted with the accent")
        T.eq(painted[stop.rim], 1, "the stop ring is painted with the accent")
        CP.Style.Repaint()
        T.eq(painted[grind.border], 2, "and again on the next style change")
        T.eq(painted[stop.rim], 2)
    end)
    World.set(_G, "DaylightUI", saved)
    T.ok(ok, err)
end)
