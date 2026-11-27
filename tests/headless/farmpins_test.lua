-- "Other zones" with a picked zone. The picked zone takes the player's slot, drawn at full
-- strength, and the rest of the player's continent shows dimmed, the player's own zone
-- included. Farm follows the setting as the guide does: on, the other zones show; off, only
-- the listed zone does.

local CP = ProfLost
local RM, W, GL = CP.RouteMap, CP.Waypoint, CP.GatherList
local DUROTAR, BARRENS = 1411, 1413

-- Scene: Durotar, level 20 Horde, skinning and mining needs, route mode `mode`, other zones
-- `others`. `act(seen)` runs with every grind pin's owner zone in `seen`.
local function scene(mode, others, act)
    MapWorld.begin({ zone = DUROTAR, x = 0.5, y = 0.5, level = 20, side = "Horde", shareSolves = true })
    for _, key in ipairs({ "routeSkip", "skinSkip", "gatherClosed", "farmClosed", "routeOnMap" }) do
        World.set(CP.db, key, nil)
    end
    World.set(CP.db, "route", true)
    World.set(CP.db, "mapIcons", true)
    World.set(CP.db, "otherZones", others)
    World.set(CP.db, "routeMode", mode)
    World.set(CP.charDB, "panelProf", nil)
    World.set(CP.charDB, "gatherZone", nil)
    World.set(CP.charDB, "gatherNeeds", { [165] = { [2318] = 200 }, [164] = { [2771] = 100 } })
    World.set(C_SkillInfo, "GetSkillLineInfoByID", function(id)
        if id == 393 or id == 186 then return { skillID = id, rank = 120, modifier = 0 } end
        return nil
    end)
    World.patch("C_Item.GetItemCount", function() return 0 end)
    World.set(CP.Gather, "UpdateAllNeeds", function() end)
    World.set(W, "MapPosZone", function(z) return z end)
    World.set(GL, "away", false)
    World.set(GL, "here", nil)
    World.set(GL, "hereName", nil)
    CP.Gather.ResetClusters()
    local pins = LibStub("HereBeDragons-Pins-2.0")
    local seen = { spots = {} }
    local addW = pins.AddWorldMapIconMap
    World.set(pins, "AddWorldMapIconMap", function(self, ref, icon, z, x, y, ...)
        -- Pool frames are reused by the next redraw, so the owner zone is read now.
        if icon.spot and icon.zone then seen.spots[icon.zone] = (seen.spots[icon.zone] or 0) + 1 end
        return addW(self, ref, icon, z, x, y, ...)
    end)
    local clear = RM.Clear
    World.set(RM, "Clear", function(...)
        seen.spots = {}
        return clear(...)
    end)
    World.onEnd(function()
        CP.db.route = false
        RM.Update(false, {})
        T.advance(1)
        CP.Gather.ResetClusters()
    end)
    RM.Forget()
    act(seen)
end

local function settle()
    T.advance(5)
    for _ = 1, 400 do
        if not (RM.Solving() or RM.Passing()) then break end
        T.advance(0.05, 0.05)
    end
end

local function has(list, zone)
    for _, z in ipairs(list) do
        if z == zone then return true end
    end
    return false
end

for _, mode in ipairs({ "level", "farm" }) do
    local name = mode == "farm" and "Farm" or "Follow the guide"
    T.test(name .. ", another zone picked, Other zones on: the player's own zone and the rest stay on the map", function()
        scene(mode ~= "level" and mode or nil, true, function(seen)
            GL.SetZone(BARRENS)
            settle()
            T.eq(CP.Gather.RouteFarming(), mode == "farm", "the scene's mode")
            T.ok(RM.Away(), "the picked Barrens are drawn from afar")
            T.ok((seen.spots[BARRENS] or 0) > 0, "the picked zone's grind spots are drawn")
            local others = RM.Others()
            T.ok(has(others, DUROTAR), "the player's zone is solved: " .. table.concat(others, ","))
            T.ok(not has(others, BARRENS), "the picked zone is not solved twice")
            T.ok((seen.spots[DUROTAR] or 0) > 0, "the player's zone's grind spots are drawn")
            local away = 0
            for zone in pairs(seen.spots) do
                if zone ~= DUROTAR and zone ~= BARRENS then away = away + 1 end
            end
            T.ok(away >= 2, "zones past the two drawn: " .. away)
        end)
    end)
end

T.test("Farm, another zone picked, Other zones off: only the picked zone is drawn", function()
    scene("farm", false, function(seen)
        GL.SetZone(BARRENS)
        settle()
        T.eq(#RM.Others(), 0, "no other zone is solved")
        T.ok((seen.spots[BARRENS] or 0) > 0, "the picked zone's grind spots are drawn")
        for zone in pairs(seen.spots) do T.eq(zone, BARRENS, "a grind pin is the picked zone's") end
    end)
end)

T.test("Follow the guide, no pick, Other zones on: the player's zone is not an other zone", function()
    scene(nil, true, function()
        GL.Refresh()
        settle()
        T.ok(not RM.Away(), "the player's own zone")
        T.ok(#RM.Others() >= 3, "other zones solved")
        T.ok(not has(RM.Others(), DUROTAR), "the player's zone is drawn once")
    end)
end)
