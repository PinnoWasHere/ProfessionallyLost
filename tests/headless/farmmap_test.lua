-- Farm is zone-specific on the map too. The zone map, the continent map and the minimap show
-- only the player's zone's grind spots and route, whatever "Other zones" says, and
-- no pass solves the other zones. Follow the guide's map still draws the other zones when the
-- setting is on. The switched-off Nearby zones code is gone.

local CP = ProfLost
local RM, W, GL = CP.RouteMap, CP.Waypoint, CP.GatherList
local KALIMDOR, DUROTAR = 1414, 1411

-- Scene: Durotar, level 20 Horde, skinning and mining needs, route mode `mode`, other zones
-- `others`. `act(seen)` runs with every pin and route line registration in `seen`.
local function scene(mode, others, act)
    MapWorld.begin({ zone = DUROTAR, x = 0.5, y = 0.5, level = 20, side = "Horde", shareSolves = true })
    World.set(CP.db, "route", true)
    World.set(CP.db, "otherZones", others)
    World.set(CP.db, "routeMode", mode)
    World.set(CP.charDB, "gatherNeeds", { [165] = { [2318] = 200 }, [164] = { [2771] = 100 } })
    World.set(C_SkillInfo, "GetSkillLineInfoByID", function(id)
        if id == 393 or id == 186 then return { skillID = id, rank = 120, modifier = 0 } end
        return nil
    end)
    World.patch("C_Item.GetItemCount", function() return 0 end)
    World.set(CP.Gather, "UpdateAllNeeds", function() end)
    World.set(W, "MapPosZone", function(z) return z end)
    CP.Gather.ResetClusters()
    local pins = LibStub("HereBeDragons-Pins-2.0")
    local seen = { world = {}, mini = {}, lines = {} }
    local addW, addM, setLine = pins.AddWorldMapIconMap, pins.AddMinimapIconMap, CP.RouteLines.Set
    World.set(pins, "AddWorldMapIconMap", function(self, ref, icon, z, x, y, ...)
        -- Pool frames are reused by the next redraw, so the owner zone is read now.
        seen.world[#seen.world + 1] = { zone = icon.zone, map = z, spot = icon.spot ~= nil }
        return addW(self, ref, icon, z, x, y, ...)
    end)
    World.set(pins, "AddMinimapIconMap", function(self, ref, icon, z, ...)
        seen.mini[#seen.mini + 1] = { zone = z }
        return addM(self, ref, icon, z, ...)
    end)
    World.set(CP.RouteLines, "Set", function(zone, ...)
        seen.lines[#seen.lines + 1] = zone
        return setLine(zone, ...)
    end)
    -- Every draw clears the map first, so `seen` holds the last draw.
    local clear = RM.Clear
    World.set(RM, "Clear", function(...)
        seen.world, seen.mini, seen.lines = {}, {}, {}
        return clear(...)
    end)
    World.onEnd(function()
        RM.Update(false, {})
        T.advance(1)
    end)
    RM.Forget()
    act(seen)
end

local function draw()
    GL.RouteOnly()
    T.advance(5)
    for _ = 1, 400 do
        if not (RM.Solving() or RM.Passing()) then break end
        T.advance(0.05, 0.05)
    end
end

for _, others in ipairs({ true, false }) do
    T.test("Farm's map draws only this zone, other zones on the map " .. (others and "on" or "off"), function()
        scene("farm", others, function(seen)
            draw()
            T.ok(CP.Gather.RouteFarming(), "the scene is in Farm")
            T.eq(#RM.Others(), 0, "no other zone is solved")
            local spots = 0
            for _, p in ipairs(seen.world) do
                if p.spot then
                    spots = spots + 1
                    T.eq(p.zone, DUROTAR, "a grind pin belongs to the player's zone")
                    T.ok(p.map == DUROTAR or p.map == KALIMDOR, "on its own map or the continent, not " .. tostring(p.map))
                else
                    T.eq(p.map, DUROTAR, "a route stop sits on the player's zone map")
                end
            end
            T.ok(spots > 0, "the player's zone has grind spots drawn")
            T.ok(#seen.mini > 0, "the minimap draws the zone")
            for _, p in ipairs(seen.mini) do T.eq(p.zone, DUROTAR, "a minimap pin is this zone's") end
            for _, zone in ipairs(seen.lines) do T.eq(zone, DUROTAR, "a route line is this zone's") end
        end)
    end)
end

T.test("Follow the guide's map still draws the other zones when the setting is on", function()
    scene(nil, true, function(seen)
        draw()
        T.ok(not CP.Gather.RouteFarming(), "the scene follows the guide")
        T.ok(#RM.Others() >= 3, "other zones solved: " .. table.concat(RM.Others(), ","))
        local away = false
        for _, p in ipairs(seen.world) do
            if p.spot and p.zone ~= DUROTAR then away = true end
        end
        T.ok(away, "another zone's grind spots are on the map")
    end)
end)

-- Pins on each map in Follow the guide with other zones on. Every map holds at least that many,
-- and no other map holds any. Taken 2026-11-24, when nodes above the player's skill left the map.
local FOLLOW_FLOORS = {
    [1411] = 7, [1412] = 15, [1413] = 17, [1414] = 46, [1438] = 3, [1439] = 12, [1440] = 25, [1441] = 22,
    [1442] = 16, [1443] = 14, [1444] = 3, [1445] = 22, [1448] = 19, [1452] = 10, [1454] = 3, [1456] = 3,
    [2652] = 3
}

T.test("Follow the guide's map holds what it held before Farm went zone-only", function()
    scene(nil, true, function(seen)
        draw()
        local count = {}
        for _, p in ipairs(seen.world) do count[p.map] = (count[p.map] or 0) + 1 end
        local maps = {}
        for map, n in pairs(count) do maps[#maps + 1] = map .. "=" .. n end
        table.sort(maps)
        local bad = {}
        for map, least in pairs(FOLLOW_FLOORS) do
            if (count[map] or 0) < least then bad[#bad + 1] = ("map %d has %d pins, under %d"):format(map, count[map] or 0, least) end
        end
        for map in pairs(count) do
            if not FOLLOW_FLOORS[map] then bad[#bad + 1] = "pins on unexpected map " .. map end
        end
        table.sort(bad)
        T.eq(table.concat(bad, "; "), "", "now: " .. table.concat(maps, ","))
    end)
end)

T.test("the Nearby zones code is gone", function()
    T.eq(GL.NearbyZones, nil, "NearbyZones")
    T.eq(GL.NearbyLines, nil, "NearbyLines")
    T.eq(GL.NearbyTick, nil, "NearbyTick")
    T.eq(GL.NearbyZoneOpen, nil, "NearbyZoneOpen")
    T.eq(GL.SHOW_NEARBY, nil, "SHOW_NEARBY")
    T.eq(RM.SkinSpots, nil, "SkinSpots")
end)
