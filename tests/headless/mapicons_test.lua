-- "Icons on the map": off removes every ProfLost pin and route line from the world map and
-- minimap at once and keeps them off after a reload; on draws them again. A waypoint the
-- player asked for is left alone. Scene as in otherzones_test.

local CP = ProfLost
local RM = CP.RouteMap
local Pins = LibStub("HereBeDragons-Pins-2.0")

-- Live pins by owner, kept by wrapping the library's add and remove calls.
local live = { world = {}, mini = {} }

local function track()
    live.world, live.mini = {}, {}
    local saved = {}
    for _, name in ipairs({ "AddWorldMapIconMap", "AddMinimapIconMap", "RemoveAllWorldMapIcons",
                            "RemoveAllMinimapIcons", "RemoveWorldMapIcon", "RemoveMinimapIcon" }) do
        saved[name] = Pins[name]
    end
    local function add(kind, name)
        Pins[name] = function(self, ref, icon, ...)
            live[kind][ref] = live[kind][ref] or {}
            live[kind][ref][icon] = true
            return saved[name](self, ref, icon, ...)
        end
    end
    local function removeAll(kind, name)
        Pins[name] = function(self, ref, ...)
            live[kind][ref] = {}
            return saved[name](self, ref, ...)
        end
    end
    local function removeOne(kind, name)
        Pins[name] = function(self, ref, icon, ...)
            if live[kind][ref] then live[kind][ref][icon] = nil end
            return saved[name](self, ref, icon, ...)
        end
    end
    add("world", "AddWorldMapIconMap")
    add("mini", "AddMinimapIconMap")
    removeAll("world", "RemoveAllWorldMapIcons")
    removeAll("mini", "RemoveAllMinimapIcons")
    removeOne("world", "RemoveWorldMapIcon")
    removeOne("mini", "RemoveMinimapIcon")
    World.onEnd(function()
        for name, fn in pairs(saved) do Pins[name] = fn end
    end)
end

local function count(kind, ref)
    local n = 0
    for _ in pairs(live[kind][ref] or {}) do n = n + 1 end
    return n
end

local function mapPins()
    return count("world", "ProfLost_Route"), count("mini", "ProfLost_Route")
end

local function scene(act)
    MapWorld.begin({ zone = 1411, x = 0.5, y = 0.5, level = 20, side = "Horde", shareSolves = true })
    track()
    local was = { CP.db.otherZones, CP.db.route, CP.db.mapIcons }
    CP.db.route = true
    CP.db.mapIcons = true
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
    local ok, err = pcall(act)
    CP.db.otherZones, CP.db.route, CP.db.mapIcons = false, false, true
    RM.Update(false, {})
    T.advance(1)
    CP.Waypoint.MapPosZone, CP.Gather.UpdateAllNeeds = mapPos, replan
    CP.Gather.ResetClusters()
    CP.db.otherZones, CP.db.route, CP.db.mapIcons = was[1], was[2], was[3]
    T.ok(ok, err)
end

local function update()
    CP.GatherList.RouteOnly()
    T.advance(5)
end

T.test("the setting is on by default and sits in the Gathering window group", function()
    T.eq(CP.DEFAULTS.mapIcons, true)
    local s = CP.Settings.Find("mapIcons")
    T.ok(s and s.group == "Gathering window" and s.kind == "toggle")
end)

T.test("off removes the route pins and lines at once, on draws them again", function()
    scene(function()
        update()
        local world, mini = mapPins()
        T.ok(world > 0 and mini > 0, "drawn: " .. world .. " world, " .. mini .. " mini")
        T.ok(CP.RouteLines.Has(1411), "a route line")

        CP.Settings.Save("mapIcons", false)
        world, mini = mapPins()
        T.eq(world, 0, "world map pins gone")
        T.eq(mini, 0, "minimap pins gone")
        T.ok(not CP.RouteLines.Has(1411), "route line gone")

        CP.Settings.Save("mapIcons", true)
        T.advance(5)
        world, mini = mapPins()
        T.ok(world > 0 and mini > 0, "back: " .. world .. " world, " .. mini .. " mini")
        T.ok(CP.RouteLines.Has(1411), "route line back")
    end)
end)

T.test("off stays off after a reload and while the route is solved again", function()
    scene(function()
        update()
        CP.Settings.Save("mapIcons", false)
        RM.Forget()
        update()
        update()
        local world, mini = mapPins()
        T.eq(world + mini, 0, "nothing drawn after a fresh solve")
        T.ok(not CP.RouteLines.Has(1411))
        T.ok(RM.Spots() ~= nil)
    end)
end)

T.test("off drops other zones and greys their setting; the setting's choice survives", function()
    scene(function()
        CP.db.otherZones = true
        update()
        T.ok(#RM.Others() > 0)
        CP.Settings.Save("mapIcons", false)
        T.eq(#RM.Others(), 0, "other zones dropped")
        T.ok(CP.Settings.Find("otherZones").disabled(function(k) return CP.db[k] end), "greyed")
        T.eq(CP.db.otherZones, true, "choice kept")
        CP.Settings.Save("mapIcons", true)
        T.advance(5)
        T.ok(#RM.Others() > 0, "other zones solved again")
    end)
end)

T.test("vendor pins follow the setting and the waypoint stays", function()
    local W, VW, saved = CP.Waypoint, CP.VendorWatch, {}
    local function vec(x, y) return { GetXY = function() return x, y end } end
    saved.locate, saved.place, saved.pos, saved.show = W.Locate, W.Place, C_Map.GetPlayerMapPosition, StaticPopup_Show
    saved.clear, saved.icons = C_Map.ClearUserWaypoint, CP.db.mapIcons
    track()
    local placed, cleared = 0, 0
    W.Locate = function() return 1413, vec(0.5, 0.5) end
    W.Place = function() placed = placed + 1; return true end
    C_Map.GetPlayerMapPosition = function() return vec(0.5, 0.5) end
    C_Map.ClearUserWaypoint = function() cleared = cleared + 1 end
    StaticPopup_Show = function() end
    local ok, err = pcall(function()
        CP.db.mapIcons = true
        VW.MarkAll({ { buy = { name = "a", skill = 1, item = 1 }, target = { name = "A", continent = 1, x = 1, y = 1, entry = 11 } } }, 1413)
        T.eq(count("world", "ProfLost_Vendors"), 1, "world pin")
        T.eq(count("mini", "ProfLost_Vendors"), 1, "mini pin")

        CP.Settings.Save("mapIcons", false)
        T.eq(count("world", "ProfLost_Vendors"), 0, "world pin gone")
        T.eq(count("mini", "ProfLost_Vendors"), 0, "mini pin gone")
        T.eq(#VW.Marked(), 1, "the vendor is still marked")
        T.eq(cleared, 0, "the waypoint is not cleared")

        -- A vendor asked for with icons off still gets its waypoint, without pins.
        local before = placed
        VW.MarkAll({ { buy = { name = "a", skill = 1, item = 1 }, target = { name = "A", continent = 1, x = 1, y = 1, entry = 11 } } }, 1413)
        T.ok(placed > before, "waypoint placed")
        T.eq(count("world", "ProfLost_Vendors"), 0, "no pin drawn")

        CP.Settings.Save("mapIcons", true)
        T.eq(count("world", "ProfLost_Vendors"), 1, "world pin back")
        T.eq(count("mini", "ProfLost_Vendors"), 1, "mini pin back")
    end)
    W.Locate, W.Place, C_Map.GetPlayerMapPosition, StaticPopup_Show = saved.locate, saved.place, saved.pos, saved.show
    C_Map.ClearUserWaypoint = saved.clear
    VW.ClearPins()
    CP.db.mapIcons = saved.icons
    T.ok(ok, err)
end)
