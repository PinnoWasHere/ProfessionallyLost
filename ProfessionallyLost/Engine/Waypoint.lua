local _, CP = ...
if CP.stopped then return end

-- Map waypoints to the trainer or vendor for an unlearned recipe. NPC spawns are
-- server world coordinates (continent, x, y) from the guide data.

local Waypoint = {}
CP.Waypoint = Waypoint

local SIDE = { Alliance = "A", Horde = "H" }

-- The map API's world vector may order its axes differently from server
-- coordinates. UnitPosition reports server order, so compare the two for the
-- player and remember whether to swap.
local swapAxes

-- UnitPosition's answer in server order, for a spot the map calls can't place.
local function unitWorld()
    local ux, uy, _, instance = UnitPosition("player")
    if not (ux and uy and instance) then return nil end
    return instance, ux, uy
end

local function playerWorld()
    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID then return unitWorld() end
    local pos = C_Map.GetPlayerMapPosition(mapID, "player")
    if not pos then return unitWorld() end
    local continent, world = C_Map.GetWorldPosFromMapPos(mapID, pos)
    if not continent or not world then return unitWorld() end
    local wx, wy = world:GetXY()
    if not wx or not wy then return unitWorld() end

    if swapAxes == nil then
        local ux, uy = UnitPosition("player")
        if ux and uy then
            local direct = math.abs(wx - ux) + math.abs(wy - uy)
            local swapped = math.abs(wx - uy) + math.abs(wy - ux)
            swapAxes = swapped < direct
        end
    end
    if swapAxes then wx, wy = wy, wx end
    return continent, wx, wy
end

local function toVector(x, y)
    if swapAxes then return CreateVector2D(y, x) end
    return CreateVector2D(x, y)
end

-- Nearest friendly spawn among `entries` (creature ids) in `npcs` (guide.npcs).
-- Returns { name, continent, x, y, roams } or nil; `roams` names the zone a roaming
-- vendor wanders, whose spawn is only the zone's middle.
function Waypoint.Nearest(entries, npcs, side, continent, px, py)
    local best, bestDist
    for _, entry in ipairs(entries or {}) do
        local npc = npcs[entry]
        if npc and (npc[2] == "N" or npc[2] == side) then
            for _, at in ipairs(npc[3]) do
                local d
                if continent and at[1] == continent and px then
                    d = (at[2] - px) ^ 2 + (at[3] - py) ^ 2
                else
                    d = 1e18 + (at[1] == continent and 0 or 1)
                end
                if not bestDist or d < bestDist then
                    best, bestDist = { name = npc[1], continent = at[1], x = at[2], y = at[3], roams = npc[4], entry = entry }, d
                end
            end
        end
    end
    return best
end

-- The zone map under a continent position, with the position on it. Falls back to
-- the continent map when no zone contains the point.
local function zonePos(continent, world, mapID, pos)
    local px, py = pos:GetXY()
    if not px or not py then return mapID, pos end
    local info = C_Map.GetMapInfoAtPosition(mapID, px, py)
    if info and info.mapType == Enum.UIMapType.Zone then
        local zoneID, zp = C_Map.GetMapPosFromWorldPos(continent, world, info.mapID)
        if zoneID and zp then
            local x, y = zp:GetXY()
            if x >= 0 and x <= 1 and y >= 0 and y <= 1 then return zoneID, zp end
        end
    end
    return mapID, pos
end

-- Where a target lands on the map: uiMapID, position, "Zone (x, y)". Nil when it can't be placed.
local function locate(target)
    local world = toVector(target.x, target.y)
    local mapID, pos = C_Map.GetMapPosFromWorldPos(target.continent, world)
    if not mapID or not pos then return nil end
    mapID, pos = zonePos(target.continent, world, mapID, pos)
    local info = C_Map.GetMapInfo(mapID)
    local x, y = pos:GetXY()
    if not x or not y then return nil end
    return mapID, pos, ("%s (%.1f, %.1f)"):format(info and info.name or "?", x * 100, y * 100)
end

-- "Zone (x, y)" for a target, or "an unknown spot"; " · 1m 40s" after it when Mapzeroth
-- timed the trip.
function Waypoint.Describe(target)
    if target.roams then return "roams " .. target.roams end
    local _, _, where = locate(target)
    where = where or "an unknown spot"
    if target.seconds then where = where .. " · " .. CP.Mapz.TimeText(target.seconds) end
    return where
end

-- Sets the waypoint. Returns true when placed. `quiet` skips the chat line, for callers
-- that confirm in their own popup. A player's pin (not quiet) routes through Mapzeroth
-- while it is loaded, and falls back to the game's waypoint when it can't. Mapzeroth's
-- own panel shows its route, so a routed pin prints no waypoint line.

local function place(target, quiet)
    local mapID, pos = locate(target)
    if not mapID or not pos then
        CP:Print(("Couldn't place a waypoint for %s."):format(target.name))
        return
    end
    local x, y = pos:GetXY()
    local routed = not quiet and CP.Mapz.Route(mapID, x, y, target.name)
    if not routed then
        if not C_Map.CanSetUserWaypointOnMap(mapID) then
            CP:Print(("%s is on a map that can't hold a waypoint."):format(target.name))
            return
        end
        C_Map.SetUserWaypoint({ uiMapID = mapID, position = CreateVector2D(x, y) })
        C_SuperTrack.SetSuperTrackedUserWaypoint(true)
    end
    local info = C_Map.GetMapInfo(mapID)
    if quiet then return true end
    if not routed then
        CP:Print(("Waypoint set: %s, %s (%.1f, %.1f)."):format(target.name, info and info.name or "?", x * 100, y * 100))
    end
    if target.roams then
        CP:Print(("%s roams %s. The waypoint marks the zone's middle; look along the roads."):format(target.name, target.roams))
    end
    return true
end

-- Climb from a map to the zone that holds it (subzones, caves and micro maps sit below zones).
-- Cached per map while GetMapInfo stays the same.
local zoneAbove, zoneInfoFn = {}, nil

local function zoneOf(mapID)
    if not mapID then return nil end
    if C_Map.GetMapInfo ~= zoneInfoFn then zoneAbove, zoneInfoFn = {}, C_Map.GetMapInfo end
    local zone = zoneAbove[mapID]
    if zone == nil then
        local info = C_Map.GetMapInfo(mapID)
        while info and info.mapType and info.mapType > Enum.UIMapType.Zone
            and info.parentMapID and info.parentMapID > 0 do
            info = C_Map.GetMapInfo(info.parentMapID)
        end
        zone = info and info.mapType == Enum.UIMapType.Zone and info.mapID or false
        zoneAbove[mapID] = zone
    end
    return zone or nil
end

-- The first zone map at or above `mapID` that `accept(zone)` takes (any zone without it).
-- Nil once the climb reaches a continent.
local function climb(mapID, accept)
    local info = mapID and C_Map.GetMapInfo(mapID)
    while info and info.mapType and info.mapType >= Enum.UIMapType.Zone do
        if info.mapType == Enum.UIMapType.Zone and (not accept or accept(info.mapID)) then return info.mapID end
        if not (info.parentMapID and info.parentMapID > 0) then return nil end
        info = C_Map.GetMapInfo(info.parentMapID)
    end
    return nil
end

local continentMap

-- The zone under the player's world spot, for a best map that climbs to no zone: the
-- continent map's own lookup first (the world map's), then the best map for the spot.
local function spotZone(best, continent, wx, wy, accept)
    local top = best and continentMap(best)
    local pos = top and C_Map.GetPlayerMapPosition(top, "player")
    local px, py
    if pos then px, py = pos:GetXY() end
    local info = px and py and C_Map.GetMapInfoAtPosition(top, px, py)
    local zone = info and climb(info.mapID, accept)
    if zone then return zone end
    local world = toVector(wx, wy)
    local mapID, at = C_Map.GetMapPosFromWorldPos(continent, world)
    if not mapID or not at then return nil end
    return climb((zonePos(continent, world, mapID, at)), accept)
end

-- The player's zone and whether their spot decided it. The best map climbs to the first
-- zone `accept` takes. A best map with none above it (the continent, or a map the game
-- gives a cave or an entrance) falls to the zone under the player's spot.
function Waypoint.PlayerSpot(accept)
    local continent, wx, wy = playerWorld()  -- also learns the axis order
    local best = C_Map.GetBestMapForUnit("player")
    local zone = climb(best, accept)
    if zone then return zone, false end
    if not continent then return nil, false end
    zone = spotZone(best, continent, wx, wy, accept)
    return zone, zone ~= nil
end

-- Waypoint.PlayerSpot under the name most callers use.
function Waypoint.PlayerZone(accept)
    return Waypoint.PlayerSpot(accept)
end

-- The continent map above a map, cached per map while GetMapInfo stays the same.
local continentOf, infoFn = {}, nil

function continentMap(mapID)
    if C_Map.GetMapInfo ~= infoFn then continentOf, infoFn = {}, C_Map.GetMapInfo end
    if continentOf[mapID] == nil then
        local info = C_Map.GetMapInfo(mapID)
        while info and info.mapType and info.mapType > Enum.UIMapType.Continent
            and info.parentMapID and info.parentMapID > 0 do
            info = C_Map.GetMapInfo(info.parentMapID)
        end
        continentOf[mapID] = info and info.mapType == Enum.UIMapType.Continent and info.mapID or false
    end
    return continentOf[mapID] or nil
end

-- The zone the game puts a point of `zone`'s map in, or nil. Zone rectangles overlap
-- (most of Dustwallow sits inside the Barrens'), so the rectangle can't say. The
-- continent map's own zone lookup can, because the world map uses it to pick the zone
-- under a click. Without a continent answer the point's best map decides.
local function continentZone(zone, continent, world)
    local top = continentMap(zone)
    if not top then return nil end
    local _, onTop = C_Map.GetMapPosFromWorldPos(continent, world, top)
    local cx, cy
    if onTop then cx, cy = onTop:GetXY() end
    local info = cx and cy and C_Map.GetMapInfoAtPosition(top, cx, cy)
    return info and zoneOf(info.mapID) or nil
end

local function bestMapZone(continent, world)
    local mapID, pos = C_Map.GetMapPosFromWorldPos(continent, world)
    if not mapID or not pos then return nil end
    return zoneOf((zonePos(continent, world, mapID, pos)))
end

-- The zone the game puts a point of `zone`'s map in. The continent map's lookup goes
-- through the zone's cached transform, one map call a point; the world position is read
-- only when that lookup can't say.
function Waypoint.MapPosZone(zone, x, y)
    local top, cx, cy = Waypoint.OnContinent(zone, x, y)
    local info = top and C_Map.GetMapInfoAtPosition(top, cx, cy)
    local at = info and zoneOf(info.mapID)
    if at then return at end
    local continent, world = C_Map.GetWorldPosFromMapPos(zone, CreateVector2D(x, y))
    if not continent or not world then return nil end
    if not top then at = continentZone(zone, continent, world) end
    return at or bestMapZone(continent, world)
end

-- Both lookups for a point, for `/proflost border`: the continent map's, the best map's.
function Waypoint.MapPosLookups(zone, x, y)
    local continent, world = C_Map.GetWorldPosFromMapPos(zone, CreateVector2D(x, y))
    if not continent or not world then return nil, nil end
    return continentZone(zone, continent, world), bestMapZone(continent, world)
end

-- The player's continent and world x, y in server order, or nil.
function Waypoint.PlayerWorld()
    return playerWorld()
end

-- A point of a zone map as continent and world x, y in the same order as PlayerWorld.
function Waypoint.MapToWorld(zone, x, y)
    local continent, world = C_Map.GetWorldPosFromMapPos(zone, CreateVector2D(x, y))
    if not continent or not world then return nil end
    local wx, wy = world:GetXY()
    if not wx or not wy then return nil end
    if swapAxes then wx, wy = wy, wx end
    return continent, wx, wy
end

-- Yards from the player to a point of `zone`'s map. A point on another continent is
-- Waypoint.ELSEWHERE yards off. Nil when either position is unknown.
Waypoint.ELSEWHERE = 1e9

function Waypoint.Yards(zone, x, y)
    local continent, px, py = playerWorld()
    local c, wx, wy = Waypoint.MapToWorld(zone, x, y)
    if not continent or not c then return nil end
    if c ~= continent then return Waypoint.ELSEWHERE end
    return math.sqrt((wx - px) ^ 2 + (wy - py) ^ 2)
end

-- The player's spot on `zone`'s map as { x, y }, outside 0 to 1 when they stand beyond it.
-- Nil on another continent or when the map can't say.
function Waypoint.PlayerOn(zone)
    local continent, px, py = playerWorld()
    if not continent then return nil end
    local at, pos = C_Map.GetMapPosFromWorldPos(continent, toVector(px, py), zone)
    if at ~= zone or not pos then return nil end
    local x, y = pos:GetXY()
    if not x or not y then return nil end
    return { x = x, y = y }
end

-- Zone map to continent map, through the game's own world transforms. Both maps are
-- axis-aligned on one continent, so the map from one to the other is a scale and an
-- offset per axis. Each zone's is read once from two points and kept while the map
-- calls stay the same.
local toContinent, toContinentFns = {}, {}
local spawnZones, spawnEpoch = {}, nil

-- Drops the per-map caches: zone climbs, continent maps and transforms. They also start
-- over when a map call is swapped; a stub that keeps the call's identity (the test
-- harness's) needs this.
function Waypoint.ForgetMaps()
    zoneAbove, continentOf, toContinent = {}, {}, {}
    spawnEpoch = nil
end

local function onTop(zone, top, x, y)
    local continent, world = C_Map.GetWorldPosFromMapPos(zone, CreateVector2D(x, y))
    if not continent or not world then return nil end
    local _, pos = C_Map.GetMapPosFromWorldPos(continent, world, top)
    if not pos then return nil end
    return pos:GetXY()
end

-- `zone`'s transform to its continent map: { map, ox, oy, sx, sy }, or nil.
-- 0,0 and 0.5,0.5 are read, as HereBeDragons does, because 1,1 reads badly on some maps.
function Waypoint.ContinentTransform(zone)
    local fns = toContinentFns
    if fns[1] ~= C_Map.GetWorldPosFromMapPos or fns[2] ~= C_Map.GetMapPosFromWorldPos
        or fns[3] ~= C_Map.GetMapInfo or fns[4] ~= CreateVector2D then
        toContinent = {}
        toContinentFns = { C_Map.GetWorldPosFromMapPos, C_Map.GetMapPosFromWorldPos, C_Map.GetMapInfo, CreateVector2D }
    end
    local t = toContinent[zone]
    if t == nil then
        t = false
        local top = zone and continentMap(zone)
        if top and top ~= zone then
            local x0, y0 = onTop(zone, top, 0, 0)
            local x5, y5 = onTop(zone, top, 0.5, 0.5)
            if x0 and y0 and x5 and y5 and x5 ~= x0 and y5 ~= y0 then
                t = { map = top, ox = x0, oy = y0, sx = (x5 - x0) * 2, sy = (y5 - y0) * 2 }
            end
        end
        toContinent[zone] = t
    end
    return t or nil
end

-- A point of `zone`'s map on its continent map: continent map id, x, y, or nil.
function Waypoint.OnContinent(zone, x, y)
    local t = Waypoint.ContinentTransform(zone)
    if not t then return nil end
    return t.map, t.ox + t.sx * x, t.oy + t.sy * y
end

-- Waypoint to a point on a zone map, or a Mapzeroth route there while it is loaded. Only
-- runs from a player's click.
function Waypoint.PlaceOnMap(zone, x, y, name)
    if CP.Mapz.Route(zone, x, y, name) then return end
    if not C_Map.CanSetUserWaypointOnMap(zone) then return end
    C_Map.SetUserWaypoint({ uiMapID = zone, position = CreateVector2D(x, y) })
    C_SuperTrack.SetSuperTrackedUserWaypoint(true)
    local info = C_Map.GetMapInfo(zone)
    CP:Print(("Waypoint set: %s, %s (%.1f, %.1f)."):format(name, info and info.name or "?", x * 100, y * 100))
end

Waypoint.ZoneOf = zoneOf   -- map id -> the zone map at or above it, or nil

-- Zone map id of a spawn { continent, x, y }, or nil.
function Waypoint.SpawnZone(at)
    local world = toVector(at[2], at[3])
    local mapID, pos = C_Map.GetMapPosFromWorldPos(at[1], world)
    if not mapID or not pos then return nil end
    return zoneOf((zonePos(at[1], world, mapID, pos)))
end

-- Zone map id and position of a spawn { continent, x, y }: zone, x, y, or nil.
function Waypoint.SpawnPos(at)
    local world = toVector(at[2], at[3])
    local mapID, pos = C_Map.GetMapPosFromWorldPos(at[1], world)
    if not mapID or not pos then return nil end
    mapID, pos = zonePos(at[1], world, mapID, pos)
    local x, y = pos:GetXY()
    if not x or not y then return nil end
    return zoneOf(mapID), x, y
end

-- Spawn zones InZone has placed (spawnZones, by spawn): NPCs never move, so each spawn
-- asks the map once while the map calls stay the same. A spawn the map can't place yet
-- isn't kept.
local function spawnZone(at)
    local epoch = CP.Gather.MapEpoch()
    if epoch ~= spawnEpoch then spawnZones, spawnEpoch = setmetatable({}, { __mode = "k" }), epoch end
    local zone = spawnZones[at]
    if zone == nil then
        zone = Waypoint.SpawnZone(at)
        spawnZones[at] = zone
    end
    return zone
end

-- First friendly spawn of `entries` inside `zone`: { name, continent, x, y } or nil.
function Waypoint.InZone(entries, npcs, zone)
    local side = SIDE[UnitFactionGroup("player")]
    for _, entry in ipairs(entries or {}) do
        local npc = npcs[entry]
        if npc and (npc[2] == "N" or npc[2] == side) then
            for _, at in ipairs(npc[3]) do
                if spawnZone(at) == zone then
                    return { name = npc[1], continent = at[1], x = at[2], y = at[3], display = npc.display,
                             entry = entry }
                end
            end
        end
    end
    return nil
end

Waypoint.Place = place
Waypoint.Locate = locate  -- target -> zone map id, map position, "Zone (x, y)"

-- The nearest friendly NPC for `recipe` (or any table with `npcs`): { name, continent,
-- x, y }, or nil. With Mapzeroth's travel times it is the quickest to reach, and carries
-- `seconds`; else the closest.
function Waypoint.NearestFor(guide, recipe)
    local side = SIDE[UnitFactionGroup("player")]
    local timed = CP.Mapz.Nearest(recipe.npcs, guide.npcs or {}, side)
    if timed then return timed end
    local continent, px, py = playerWorld()
    return Waypoint.Nearest(recipe.npcs, guide.npcs or {}, side, continent, px, py)
end

-- Set a waypoint to the nearest NPC that teaches or sells `recipe`, replacing any
-- current one: it only runs from the player clicking a waypoint button.
function Waypoint.ToRecipe(guide, recipe)
    local target = Waypoint.NearestFor(guide, recipe)
    if not target then
        CP:Print(("No known trainer or vendor location for %s."):format(recipe.name))
        return
    end
    place(target)
end
