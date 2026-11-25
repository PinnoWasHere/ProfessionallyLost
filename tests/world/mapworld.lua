-- mapworld: where the player stands, their level and faction.
--
-- Modelled on what the game shows:
--   * [docs] C_Map.GetBestMapForUnit("player") is the zone the player stands in, and
--     GetPlayerMapPosition gives their spot on that zone's map, or on any other map
--     whose rectangle holds it (the continent), 0 to 1 from the top left.
--   * [db2] Maps sit on their continent by Forever's UiMapAssignment rectangles
--     (tests/fixtures/maps.lua): map x runs west to east, y north to south.
--   * [db2] GetMapInfo names maps from Forever's UiMap; zones are mapType 3.
--   * [docs] GetWorldPosFromMapPos and GetMapPosFromWorldPos with a map id go through those
--     rectangles both ways, so a zone point lands on its continent map where the two
--     rectangles put it (Waypoint.OnContinent, continentpins_test).
--   * [docs] Moving to another zone fires ZONE_CHANGED_NEW_AREA; within one, ZONE_CHANGED.
--     A new level fires PLAYER_LEVEL_UP.
--   * [docs] CreateVector2D (Blizzard's Lua) makes a vector with GetXY.
-- Guesses:
--   * [guess] World vectors and UnitPosition both give server x first, so ProfLost's axis
--     check finds nothing to swap.
--   * [guess] GetMapPosFromWorldPos without a map names the zone holding the point, not the
--     continent; where zone rectangles overlap, the lowest map id wins. A zone map's
--     GetMapInfoAtPosition answers the same way.
--   * [guess] A continent map's GetMapInfoAtPosition (the world map's click lookup) knows the
--     zones' real shapes. The fixture has rectangles only, so where they overlap the
--     point goes to the zone it sits deepest in, each rectangle scaled to 0 to 1
--     (the Barrens' east edge inside Dustwallow's rectangle is Dustwallow).
--   * [guess] Inside an instance (begin{ instance = mapID }) the map calls give nothing and
--     GetInstanceInfo's eighth value is the map id; its name is begin's instanceName.
--   * [guess] begin{ best = id } makes GetBestMapForUnit name `id` while the player stands at
--     zone x, y (best = false: no map at all), as the game does in a cave or an entrance
--     it maps to no zone. begin{ maps = { [id] = { name, parent, type } } } adds maps
--     with no rectangle; GetPlayerMapPosition on one is the zone spot, and it has no
--     world position. UnitPosition still gives the spot.
--   * [guess] GetRealZoneText is begin's realZone, else the zone's name; GetSubZoneText is subZone,
--     else "".
--   * [guess] GetMapPosFromWorldPos with a map id answers outside 0 to 1 too, unclamped.
-- Test controls:
--   * begin{ shareSolves = true } gives the scene the shared Route.Solve answers (solves.lua).
--   * begin{ count = true } counts every C_Map call by name in MapWorld.calls and turns
--     the shared MapPosZone memo off, so a scene pays what the game would.
-- Not modelled: HereBeDragons reads its map data as it loads, before any scene, so it
-- has none here.
--
--   MapWorld.begin({ zone = 1421, x = 0.5, y = 0.5, level = 30, side = "Horde" })
--   MapWorld.Move(zone, x, y) / SetLevel(n)
--   MapWorld.Snapshot(): where the player stands, level and faction, as begin takes them

MapWorld = {}

local CP = ProfLost
local S

local function info(id)
    local m = WorldData.maps[id] or (S and S.maps[id])
    if not m then return nil end
    return { mapID = id, name = m[1], parentMapID = m[2], mapType = m[3] }
end

-- A map point to server world x, y on the map's continent.
local function toWorld(id, x, y)
    local m = WorldData.maps[id]
    if not (m and m[4]) then return nil end
    local minX, minY, maxX, maxY = m[5], m[6], m[7], m[8]
    return m[4], maxX - y * (maxX - minX), maxY - x * (maxY - minY)
end

local function toMap(id, wx, wy)
    local m = WorldData.maps[id]
    local minX, minY, maxX, maxY = m[5], m[6], m[7], m[8]
    return (maxY - wy) / (maxY - minY), (maxX - wx) / (maxX - minX)
end

-- Zone ids per continent, lowest id first.
local zonesOn
local function zones(instance)
    if not zonesOn then
        zonesOn = {}
        for id, m in pairs(WorldData.maps) do
            if m[3] == 3 and m[4] then
                zonesOn[m[4]] = zonesOn[m[4]] or {}
                table.insert(zonesOn[m[4]], id)
            end
        end
        for _, ids in pairs(zonesOn) do table.sort(ids) end
    end
    return zonesOn[instance] or {}
end

-- The zone on continent `instance` that holds world x, y, with the point on its map.
local function zoneAt(instance, wx, wy)
    local maps = WorldData.maps
    for _, id in ipairs(zones(instance)) do
        local m = maps[id]
        local x, y = (m[8] - wy) / (m[8] - m[6]), (m[7] - wx) / (m[7] - m[5])
        if x >= 0 and x <= 1 and y >= 0 and y <= 1 then return id, x, y end
    end
end

-- The zone a continent map's lookup names at world x, y: the rectangle holding the
-- point farthest from its edges, on its own 0 to 1 scale.
local function shapeAt(instance, wx, wy)
    local maps, best, depth = WorldData.maps, nil, nil
    for _, id in ipairs(zones(instance)) do
        local m = maps[id]
        local x, y = (m[8] - wy) / (m[8] - m[6]), (m[7] - wx) / (m[7] - m[5])
        local d = math.min(x, 1 - x, y, 1 - y)
        if d >= 0 and (not depth or d > depth) then best, depth = id, d end
    end
    return best
end

local function inside() return S.instance ~= nil end

-- The game's Vector2D, enough of it for map positions.
local function vec(x, y)
    return { x = x, y = y, GetXY = function(self) return self.x, self.y end }
end

-- C_Map patches count their calls in MapWorld.calls while the scene counts.
local function mapPatch(name, fn)

    -- [docs] Each C_Map call answers as C_Map documents it; the counting is a test control.
    World.patch("C_Map." .. name, function(...)
        if S.count then MapWorld.calls[name] = (MapWorld.calls[name] or 0) + 1 end
        return fn(...)
    end)
end

local function install()

    -- [docs] CreateVector2D (Blizzard's Vector2D.lua) makes a vector with GetXY.
    World.patch("CreateVector2D", vec)

    -- [guess] The player's level and faction are the scene's own.
    World.patch("UnitLevel", function(unit)
        if unit == "player" then return S.level end
        return World.PASS
    end)
    World.patch("UnitFactionGroup", function(unit)
        if unit == "player" then return S.side, S.side end
        return World.PASS
    end)

    -- [docs] IsInInstance and GetInstanceInfo return the documented shapes; the instance name is the scene's.
    World.patch("IsInInstance", function()
        if inside() then return true, "party" end
        return false, "none"
    end)
    World.patch("GetInstanceInfo", function()
        if not inside() then return "", "none", 0, "", 0, 0, false, S.continent end
        return S.instanceName or ("Instance " .. S.instance), "party", 1, "Normal", 5, 0, false, S.instance
    end)

    -- [guess] The zone texts follow the scene's zone, or its realZone and subZone.
    World.patch("GetRealZoneText", function()
        if inside() then return S.instanceName or "" end
        return S.realZone or MapWorld.ZoneName(S.zone)
    end)
    World.patch("GetSubZoneText", function() return S.subZone or "" end)

    -- [guess] UnitPosition gives server x first.
    World.patch("UnitPosition", function(unit)
        if unit ~= "player" or inside() then return nil end
        local instance, wx, wy = toWorld(S.zone, S.x, S.y)
        return wx, wy, 0, instance
    end)
    mapPatch("GetBestMapForUnit", function(unit)
        if unit ~= "player" or inside() then return nil end
        if S.best == false then return nil end
        return S.best or S.zone
    end)
    mapPatch("GetPlayerMapPosition", function(id, unit)
        if unit ~= "player" or inside() then return nil end
        if id == S.zone or S.maps[id] then return vec(S.x, S.y) end
        local instance, wx, wy = toWorld(S.zone, S.x, S.y)
        local m = WorldData.maps[id]
        if not (instance and m and m[4] == instance) then return nil end
        local x, y = toMap(id, wx, wy)
        if x < 0 or x > 1 or y < 0 or y > 1 then return nil end
        return vec(x, y)
    end)
    mapPatch("GetMapInfo", function(id) return info(id) end)
    mapPatch("GetWorldPosFromMapPos", function(id, pos)
        local x, y = pos:GetXY()
        local instance, wx, wy = toWorld(id, x, y)
        if not instance then return nil end
        return instance, vec(wx, wy)
    end)
    mapPatch("GetMapPosFromWorldPos", function(instance, world, override)
        local wx, wy = world:GetXY()
        if override then
            local m = WorldData.maps[override]
            if not (m and m[4] == instance) then return nil end
            return override, vec(toMap(override, wx, wy))
        end
        local id, x, y = zoneAt(instance, wx, wy)
        if not id then return nil end
        return id, vec(x, y)
    end)
    mapPatch("GetMapInfoAtPosition", function(id, x, y)
        local instance, wx, wy = toWorld(id, x, y)
        local m = WorldData.maps[id]
        local zone = instance and (m[3] == 2 and shapeAt(instance, wx, wy) or zoneAt(instance, wx, wy))
        return zone and info(zone) or nil
    end)
end

-- Waypoint.MapPosZone answers from these maps alone, so every scene shares its
-- answers and a scene's cluster rebuild skips the map lookups. The memo answers
-- only while ProfLost's own MapPosZone and this scene's map calls are in place; a
-- test that swaps one of them gets the live call.
local mapPosZone = CP.Waypoint.MapPosZone
local MAP_CALLS = { "GetMapInfo", "GetWorldPosFromMapPos", "GetMapPosFromWorldPos", "GetMapInfoAtPosition" }
local sceneCalls, sceneVector = {}, nil
local memo, NONE = {}, {}

local function sceneMaps()
    if CreateVector2D ~= sceneVector then return false end
    for i, name in ipairs(MAP_CALLS) do
        if C_Map[name] ~= sceneCalls[i] then return false end
    end
    return true
end

local function memoPosZone(zone, x, y)
    if S.count or not sceneMaps() then return mapPosZone(zone, x, y) end
    local byX = memo[zone]
    if not byX then byX = {}; memo[zone] = byX end
    local byY = byX[x]
    if not byY then byY = {}; byX[x] = byY end
    local at = byY[y]
    if at == nil then
        at = mapPosZone(zone, x, y)
        byY[y] = at == nil and NONE or at
        return at
    end
    if at == NONE then return nil end
    return at
end

local function shareMapPosZone()
    for i, name in ipairs(MAP_CALLS) do sceneCalls[i] = C_Map[name] end
    sceneVector = CreateVector2D
    if CP.Waypoint.MapPosZone == mapPosZone then World.set(CP.Waypoint, "MapPosZone", memoPosZone) end
end

-- Starts the scene. Defaults: Durotar's middle, level 60, Horde.
function MapWorld.begin(spec)
    spec = spec or {}
    S = { zone = spec.zone or 1411, x = spec.x or 0.5, y = spec.y or 0.5, level = spec.level or 60,
          side = spec.side or "Horde", instance = spec.instance, instanceName = spec.instanceName,
          best = spec.best, maps = spec.maps or {}, realZone = spec.realZone, subZone = spec.subZone,
          count = spec.count }
    MapWorld.calls = {}
    S.continent = WorldData.maps[S.zone] and WorldData.maps[S.zone][4] or 0
    MapWorld.state = S
    install()
    shareMapPosZone()
    -- Zone clusters are cached by map answers; this map starts them over, and so does the next.
    CP.Gather.ResetClusters()
    World.onEnd(function() CP.Gather.ResetClusters() end)
    World.set(CP.Gather, "lastOutdoor", nil)

    -- Route solves and terrain grids belong to their scene. A grid is cached by zone, side
    -- and level only, and a solve by its rows, so one made under another scene's map
    -- answers or skills would stand in for this one's.
    local function forgetRoutes()
        CP.RouteMap.Forget()
        CP.Terrain.Reset()
    end
    forgetRoutes()
    World.onEnd(forgetRoutes)

    if spec.shareSolves then Solves.share() end

    -- A zone's pattern pulse ends with its scene, so its 20 s redraw never lands in the next.
    local GL = CP.GatherList
    GL.pulseUntil, GL.unseen, GL.patternsOpen = 0, 0, false
    World.onEnd(function() GL.pulseUntil, GL.unseen, GL.patternsOpen = 0, 0, false end)

    -- The vendor patterns the zone's scan finds end with the scene.
    World.set(CP.VendorWatch, "current", CP.VendorWatch.current)
    World.set(CP.VendorWatch, "counted", CP.VendorWatch.counted)
end

-- `place` (optional): { best, realZone, subZone } for the new spot; each kept when absent.
function MapWorld.Move(zone, x, y, place)
    local changed = zone ~= S.zone
    S.zone, S.x, S.y = zone, x or 0.5, y or 0.5
    if place then
        if place.best ~= nil then S.best = place.best end
        S.realZone, S.subZone = place.realZone or S.realZone, place.subZone or S.subZone
    end
    S.continent = WorldData.maps[zone] and WorldData.maps[zone][4] or S.continent
    T.fire(changed and "ZONE_CHANGED_NEW_AREA" or "ZONE_CHANGED")
end

function MapWorld.Snapshot()
    return { zone = S.zone, x = S.x, y = S.y, level = S.level, side = S.side, instance = S.instance,
             instanceName = S.instanceName, best = S.best, realZone = S.realZone, subZone = S.subZone }
end

function MapWorld.SetLevel(n)
    S.level = n
    T.fire("PLAYER_LEVEL_UP", n)
end

-- Builds the gathering guides' zones as the game would, a slice a frame, until the job is
-- done: for `lines` (optional) and the player's gathering skills.
function MapWorld.SettleGuides(lines)
    local GG = CP.GatherGuide
    for _, line in ipairs(lines or { false }) do
        local frames = 0
        repeat
            GG.Warm(line or nil)
            T.advance(0.02, 0.02)
            frames = frames + 1
        until not GG.Warming() and (not line or GG.Ready(line)) or frames > 100000
    end
    T.advance(0)
end

-- C_Map calls counted since `MapWorld.calls` was last emptied, all names together.
function MapWorld.CallCount()
    local n = 0
    for _, c in pairs(MapWorld.calls or {}) do n = n + c end
    return n
end

function MapWorld.ZoneName(zone)
    local m = WorldData.maps[zone]
    return m and m[1] or ("zone " .. tostring(zone))
end
