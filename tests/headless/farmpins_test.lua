-- A picked zone, with "Other zones" on or off. The picked zone takes the player's slot and the
-- player's own zone keeps one of its own: both draw at full strength, and the player's zone
-- stays on the minimap. With Other zones on, the rest of the player's continent shows dimmed;
-- off, nothing else shows. Farm follows the setting as the guide does.

local CP = ProfLost
local RM, W, GL = CP.RouteMap, CP.Waypoint, CP.GatherList
local DUROTAR, BARRENS = 1411, 1413

-- Scene: Durotar, level 20 Horde, skinning and mining needs, route mode `mode`, other zones
-- `others`. `act(seen)` runs with each owner zone's grind pins in `seen.spots`, its world map
-- pin alphas in `seen.alpha` and its minimap pins in `seen.mini`.
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
    local seen = { spots = {}, alpha = {}, mini = {} }
    local addW, addM = pins.AddWorldMapIconMap, pins.AddMinimapIconMap
    World.set(pins, "AddWorldMapIconMap", function(self, ref, icon, z, x, y, ...)
        -- Pool frames are reused by the next redraw, so the owner zone is read now.
        local owner = icon.zone or z
        if icon.spot and icon.zone then seen.spots[icon.zone] = (seen.spots[icon.zone] or 0) + 1 end
        seen.alpha[owner] = seen.alpha[owner] or {}
        seen.alpha[owner][icon.alpha] = true
        return addW(self, ref, icon, z, x, y, ...)
    end)
    World.set(pins, "AddMinimapIconMap", function(self, ref, icon, z, ...)
        seen.mini[z] = (seen.mini[z] or 0) + 1
        return addM(self, ref, icon, z, ...)
    end)
    local clear = RM.Clear
    World.set(RM, "Clear", function(...)
        seen.spots, seen.alpha, seen.mini = {}, {}, {}
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

-- Checks that every world map pin of `zone`, on its zone map and the continent, has `alpha`.
local function only(seen, zone, alpha)
    local got = {}
    for a in pairs(seen.alpha[zone] or {}) do got[#got + 1] = tostring(a) end
    table.sort(got)
    T.eq(table.concat(got, ","), tostring(alpha), "zone " .. zone .. "'s pin alphas")
end

-- The player's zone shows as with nothing picked: full strength, its pins and its loop on the
-- minimap. The picked zone shows full strength and stays off the minimap until the player is there.
local function homeShows(seen)
    T.ok((seen.spots[DUROTAR] or 0) > 0, "the player's zone's grind spots are drawn")
    only(seen, DUROTAR, 1)
    only(seen, BARRENS, 1)
    T.ok((seen.mini[DUROTAR] or 0) > 0, "the player's zone's pins are on the minimap")
    T.ok(CP.RouteLines.OnMinimap(DUROTAR), "the player's zone's loop is on the minimap")
    T.eq(seen.mini[BARRENS], nil, "the picked zone is not on the minimap")
end

for _, mode in ipairs({ "level", "farm" }) do
    local name = mode == "farm" and "Farm" or "Follow the guide"
    T.test(name .. ", another zone picked, Other zones on: your zone and the picked one full, the rest dimmed", function()
        scene(mode ~= "level" and mode or nil, true, function(seen)
            GL.SetZone(BARRENS)
            settle()
            T.eq(CP.Gather.RouteFarming(), mode == "farm", "the scene's mode")
            T.ok(RM.Away(), "the picked Barrens are drawn from afar")
            T.ok((seen.spots[BARRENS] or 0) > 0, "the picked zone's grind spots are drawn")
            T.eq(RM.Home(), DUROTAR, "the player's zone has its own slot")
            local others = RM.Others()
            T.ok(not has(others, DUROTAR), "the player's zone is not an other zone")
            T.ok(not has(others, BARRENS), "the picked zone is not solved twice")
            homeShows(seen)
            local away = 0
            for zone in pairs(seen.spots) do
                if zone ~= DUROTAR and zone ~= BARRENS then
                    away = away + 1
                    only(seen, zone, RM.DIM)
                    T.eq(seen.mini[zone], nil, "zone " .. zone .. " is not on the minimap")
                end
            end
            T.ok(away >= 2, "zones past the two drawn: " .. away)
        end)
    end)

    T.test(name .. ", another zone picked, Other zones off: only your zone and the picked one, both full", function()
        scene(mode ~= "level" and mode or nil, false, function(seen)
            GL.SetZone(BARRENS)
            settle()
            T.eq(#RM.Others(), 0, "no other zone is solved")
            T.eq(RM.Home(), DUROTAR, "the player's zone has its own slot")
            T.ok((seen.spots[BARRENS] or 0) > 0, "the picked zone's grind spots are drawn")
            for zone in pairs(seen.spots) do
                T.ok(zone == BARRENS or zone == DUROTAR, "a grind pin is the picked zone's or yours: " .. zone)
            end
            homeShows(seen)
        end)
    end)
end

T.test("walking into the picked zone drops the player's old zone", function()
    scene(nil, false, function(seen)
        GL.SetZone(BARRENS)
        settle()
        T.eq(RM.Home(), DUROTAR)
        MapWorld.Move(BARRENS, 0.5, 0.5)
        GL.Refresh()
        settle()
        T.ok(not RM.Away(), "the player is in the picked zone")
        T.eq(RM.Home(), nil, "no second slot")
        T.eq(seen.spots[DUROTAR], nil, "the old zone is gone")
        T.ok((seen.mini[BARRENS] or 0) > 0, "the picked zone is on the minimap now")
    end)
end)

T.test("Follow the guide, no pick, Other zones on: the player's zone is not an other zone", function()
    scene(nil, true, function()
        GL.Refresh()
        settle()
        T.ok(not RM.Away(), "the player's own zone")
        T.eq(RM.Home(), nil, "no second slot")
        T.ok(#RM.Others() >= 3, "other zones solved")
        T.ok(not has(RM.Others(), DUROTAR), "the player's zone is drawn once")
    end)
end)
