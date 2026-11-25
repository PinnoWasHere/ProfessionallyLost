-- Mapzeroth: with its API loaded, waypoint pins route through it and the nearest trainer
-- or vendor is the quickest to reach. A fake MapzerothAPI stands in, as its API.lua
-- describes it: RouteTo(points, name, options) and TimeTo(points). Without it nothing changes.

local CP = ProfLost

local function lw() return CP.Guides[165] end
local VEST = 2160   -- Embossed Leather Vest: taught by many trainers, several of them Horde

-- A fake MapzerothAPI for the test's length. `spec.times(points)` answers TimeTo (no
-- TimeTo without it); `spec.refuse` makes RouteTo return false.
local function fake(spec)
    spec = spec or {}
    local f = { routes = {}, timeCalls = 0 }
    function f.RouteTo(points, name, options)
        f.routes[#f.routes + 1] = { points = points, name = name, options = options }
        if spec.refuse then return false, "bad point 1" end
        return true
    end
    if spec.times then
        function f.TimeTo(points)
            f.timeCalls = f.timeCalls + 1
            f.points = points
            return spec.times(points)
        end
    end
    World.set(_G, "MapzerothAPI", f)
    return f
end

-- The last point is the quickest; every other one is a long way round.
local function lastQuickest(points)
    local out = {}
    for i = 1, #points do out[i] = i == #points and 100 or 5000 end
    return out
end

local function waypointPatches()
    local placed = {}
    World.patch("C_Map.CanSetUserWaypointOnMap", function() return true end)
    World.patch("C_Map.SetUserWaypoint", function(p) placed[#placed + 1] = p end)
    World.patch("C_SuperTrack.SetSuperTrackedUserWaypoint", function() end)
    return placed
end

local function where(target)
    local mapID, pos = CP.Waypoint.Locate(target)
    local x, y = pos:GetXY()
    return mapID, x, y
end

local function near(a, b) return math.abs(a - b) < 1e-6 end

T.test("without Mapzeroth a pin sets the game's waypoint and the nearest is by distance", function()
    World.set(_G, "MapzerothAPI", nil)
    MapWorld.begin({ zone = 1454, x = 0.5, y = 0.5, side = "Horde" })
    local placed = waypointPatches()
    local guide, r = lw(), lw().recipes[VEST]
    local continent, px, py = CP.Waypoint.PlayerWorld()
    local byDistance = CP.Waypoint.Nearest(r.npcs, guide.npcs, "H", continent, px, py)
    local npc = CP.Waypoint.NearestFor(guide, r)
    T.eq(npc.name, byDistance.name)
    T.eq(npc.x, byDistance.x)
    T.eq(npc.seconds, nil)
    T.ok(not CP.Waypoint.Describe(npc):find("·", 1, true), "no travel time without Mapzeroth")
    CP.Waypoint.ToRecipe(guide, r)
    T.eq(#placed, 1, "the game's waypoint")
end)

T.test("a step card pin routes through Mapzeroth and starts the trip", function()
    local f = fake()
    MapWorld.begin({ zone = 1454, x = 0.5, y = 0.5, side = "Horde" })
    local placed = waypointPatches()
    local guide, r = lw(), lw().recipes[VEST]
    local npc = CP.Waypoint.NearestFor(guide, r)
    CP.Waypoint.ToRecipe(guide, r)
    T.eq(#f.routes, 1, "one route")
    T.eq(#placed, 0, "no game waypoint beside it")
    local route = f.routes[1]
    T.eq(route.name, npc.name)
    T.eq(route.options.start, true)
    local mapID, x, y = where(npc)
    T.eq(route.points.mapID, mapID)
    T.ok(near(route.points.x, x) and near(route.points.y, y), "routes to the NPC's spot")
    T.eq(route.points.name, npc.name)
end)

T.test("a gathering panel pin routes through Mapzeroth", function()
    local f = fake()
    MapWorld.begin({ zone = 1411, side = "Horde" })
    local placed = waypointPatches()
    CP.Waypoint.PlaceOnMap(1411, 0.4, 0.6, "Grind spot: Dire Mottled Boar")
    T.eq(#f.routes, 1)
    T.eq(#placed, 0)
    T.eq(f.routes[1].points.mapID, 1411)
    T.eq(f.routes[1].points.x, 0.4)
    T.eq(f.routes[1].points.y, 0.6)
    T.eq(f.routes[1].name, "Grind spot: Dire Mottled Boar")
end)

T.test("a route Mapzeroth refuses falls back to the game's waypoint", function()
    local f = fake({ refuse = true })
    MapWorld.begin({ zone = 1411, side = "Horde" })
    local placed = waypointPatches()
    CP.Waypoint.PlaceOnMap(1411, 0.4, 0.6, "Fishing pool")
    T.eq(#f.routes, 1, "asked")
    T.eq(#placed, 1, "then the game's waypoint")
end)

T.test("Route with Mapzeroth off keeps the game's waypoint", function()
    local f = fake()
    MapWorld.begin({ zone = 1411, side = "Horde" })
    local placed = waypointPatches()
    World.set(CP.db, "mapzRoute", false)
    CP.Waypoint.PlaceOnMap(1411, 0.4, 0.6, "Fishing pool")
    CP.Waypoint.ToRecipe(lw(), lw().recipes[VEST])
    T.eq(#f.routes, 0)
    T.eq(#placed, 2)
end)

T.test("a quiet waypoint (the vendor watch's own) never starts a Mapzeroth trip", function()
    local f = fake()
    MapWorld.begin({ zone = 1454, side = "Horde" })
    local placed = waypointPatches()
    CP.Waypoint.Place(CP.Waypoint.NearestFor(lw(), lw().recipes[VEST]), true)
    T.eq(#f.routes, 0)
    T.eq(#placed, 1)
end)

T.test("the setting always shows, greyed while Mapzeroth is not loaded", function()
    local s = CP.Settings.Find("mapzRoute")
    T.ok(s ~= nil, "a setting")
    T.eq(s.kind, "toggle")
    T.eq(s.label, "Route with Mapzeroth")
    T.eq(CP.DEFAULTS.mapzRoute, true, "on by default")
    local function row()
        for _, g in ipairs(CP.Plugin.Pages()[1].groups) do
            for _, it in ipairs(g.items) do if it.key == "mapzRoute" then return it end end
        end
    end
    local r = row()
    T.ok(r and r.type == "toggle", "a Daylight UI toggle row")
    World.set(_G, "MapzerothAPI", nil)
    T.eq(r.hidden, nil, "never hidden")
    T.ok(type(r.disabled) == "function", "a disabled test")
    T.ok(r.desc:find("Needs the Mapzeroth addon", 1, true) ~= nil, "the tooltip says it needs Mapzeroth")
    T.eq(r.disabled(function() end), true, "greyed without Mapzeroth")
    fake()
    T.eq(r.disabled(function() end), false, "live with it")
end)

T.test("the nearest trainer is the quickest by Mapzeroth's travel time", function()
    local f = fake({ times = lastQuickest })
    MapWorld.begin({ zone = 1454, x = 0.5, y = 0.5, side = "Horde" })
    local guide, r = lw(), lw().recipes[VEST]
    local continent, px, py = CP.Waypoint.PlayerWorld()
    local byDistance = CP.Waypoint.Nearest(r.npcs, guide.npcs, "H", continent, px, py)
    local npc = CP.Waypoint.NearestFor(guide, r)
    T.eq(f.timeCalls, 1)
    T.ok(#f.points >= 2, "several trainers to rank")
    T.ok(npc.x ~= byDistance.x or npc.y ~= byDistance.y, "the pick moved off the closest")
    local quick = f.points[#f.points]
    local mapID, x, y = where(npc)
    T.eq(mapID, quick.mapID)
    T.ok(near(x, quick.x) and near(y, quick.y), "the quickest, not the closest")
    T.eq(npc.name, quick.name)
    T.eq(npc.seconds, 100)
    T.ok(CP.Waypoint.Describe(npc):find(" · 1m 40s$") ~= nil, CP.Waypoint.Describe(npc))
end)

T.test("travel times are asked once per candidate list and zone, never per refresh", function()
    local f = fake({ times = lastQuickest })
    MapWorld.begin({ zone = 1454, x = 0.5, y = 0.5, side = "Horde" })
    local guide, r = lw(), lw().recipes[VEST]
    for _ = 1, 5 do CP.Waypoint.NearestFor(guide, r) end
    T.eq(f.timeCalls, 1, "five refreshes, one search")
    MapWorld.Move(1454, 0.3, 0.3)
    CP.Waypoint.NearestFor(guide, r)
    T.eq(f.timeCalls, 1, "a step inside the zone asks nothing")
    CP.Guide.NearestSeller(guide, { r.npcs[1], r.npcs[2] })
    T.eq(f.timeCalls, 2, "another list asks once")
    CP.Guide.NearestSeller(guide, { r.npcs[1], r.npcs[2] })
    T.eq(f.timeCalls, 2)
    MapWorld.Move(1411, 0.5, 0.5)
    CP.Waypoint.NearestFor(guide, r)
    T.eq(f.timeCalls, 3, "a new zone asks again")
end)

T.test("unreachable candidates fall back to distance", function()
    local f = fake({ times = function() return {} end })
    MapWorld.begin({ zone = 1454, x = 0.5, y = 0.5, side = "Horde" })
    local guide, r = lw(), lw().recipes[VEST]
    local continent, px, py = CP.Waypoint.PlayerWorld()
    local byDistance = CP.Waypoint.Nearest(r.npcs, guide.npcs, "H", continent, px, py)
    local npc = CP.Waypoint.NearestFor(guide, r)
    T.eq(f.timeCalls, 1)
    T.eq(npc.x, byDistance.x)
    T.eq(npc.y, byDistance.y)
    T.eq(npc.seconds, nil)
end)

T.test("no answer from TimeTo (in an instance) falls back to distance", function()
    local f = fake({ times = function() return nil, "no position" end })
    MapWorld.begin({ zone = 1454, x = 0.5, y = 0.5, side = "Horde" })
    local guide, r = lw(), lw().recipes[VEST]
    local continent, px, py = CP.Waypoint.PlayerWorld()
    local byDistance = CP.Waypoint.Nearest(r.npcs, guide.npcs, "H", continent, px, py)
    T.eq(CP.Waypoint.NearestFor(guide, r).x, byDistance.x)
    CP.Waypoint.NearestFor(guide, r)
    T.eq(f.timeCalls, 1, "the failure is kept for the zone too")
end)

T.test("travel times read as minutes and seconds", function()
    T.eq(CP.Mapz.TimeText(45), "45s")
    T.eq(CP.Mapz.TimeText(100), "1m 40s")
    T.eq(CP.Mapz.TimeText(120), "2m")
    T.eq(CP.Mapz.TimeText(3725), "1h 2m")
end)

-- Greyed toggles draw off and keep the saved choice (the first page build, no tab switch).
local function pageRow(key)
    for _, g in ipairs(CP.Plugin.Pages()[1].groups) do
        for _, it in ipairs(g.items) do if it.key == key then return it end end
    end
end

T.test("Route with Mapzeroth: without Mapzeroth the first page build is greyed and draws off", function()
    World.set(_G, "MapzerothAPI", nil)
    World.set(CP.db, "mapzRoute", true)
    local r = pageRow("mapzRoute")
    T.eq(r.disabled(function() end), true, "greyed")
    T.ok(type(r.get) == "function", "the switch draws a separate value")
    T.eq(r.get(), false, "draws off while greyed")
    T.eq(CP.db.mapzRoute, true, "the saved choice stays")
end)

T.test("Route with Mapzeroth: with Mapzeroth it is live and draws the saved value", function()
    fake()
    World.set(CP.db, "mapzRoute", true)
    local r = pageRow("mapzRoute")
    T.eq(r.disabled(function() end), false)
    T.eq(r.get(), true)
    World.set(CP.db, "mapzRoute", false)
    T.eq(pageRow("mapzRoute").get(), false, "an off choice draws off")
    World.set(CP.db, "mapzRoute", true)
    World.set(_G, "MapzerothAPI", nil)
    T.eq(pageRow("mapzRoute").get(), false, "greyed again: off")
    T.eq(CP.db.mapzRoute, true, "saved value kept, back on when Mapzeroth returns")
    fake()
    T.eq(pageRow("mapzRoute").get(), true)
end)

T.test("every greyed toggle draws off through the one shared mechanism", function()
    World.set(CP.db, "mapIcons", false)
    World.set(CP.db, "otherZones", true)
    local r = pageRow("otherZones")
    T.eq(r.disabled(function(k) return CP.db[k] end), true)
    T.eq(r.get(), false, "other zones draws off while icons are off")
    T.eq(CP.db.otherZones, true)
    World.set(CP.db, "collect", false)
    World.set(CP.db, "fishCook", true)
    T.eq(pageRow("fishCook").get(), false, "fish for cooking draws off while gathering is off")
    World.set(CP.db, "collect", true)
    T.eq(pageRow("fishCook").get(), true)
end)
