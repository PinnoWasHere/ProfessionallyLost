local _, CP = ...
if CP.stopped then return end

-- Mapzeroth, while it is loaded. Waypoint pins route through it, and the nearest trainer or
-- vendor is the quickest to reach by its travel times. Without it nothing changes.
-- Its API (Mapzeroth/API.lua): RouteTo(points, name, options) and TimeTo(points). Each TimeTo
-- call is a full route search, so answers are kept per candidate list and player zone.

local Mapz = {}
CP.Mapz = Mapz

local GLOBAL = "MapzerothAPI"   -- Mapzeroth's global; an optional addon, not a game API
local MAX_POINTS = 50           -- TimeTo's limit when the API doesn't name one

local function api()
    local a = _G[GLOBAL]
    return type(a) == "table" and a or nil
end

-- True when Mapzeroth's RouteTo is there.
function Mapz.Loaded()
    local a = api()
    return a ~= nil and type(a.RouteTo) == "function"
end

-- True when pins route through Mapzeroth: it is loaded and "Route with Mapzeroth" is on.
function Mapz.Routing()
    return Mapz.Loaded() and not (CP.db and CP.db.mapzRoute == false)
end

-- Routes to a point of a zone map and starts the trip. True when Mapzeroth took it; false
-- sends the caller to the game's waypoint.
function Mapz.Route(mapID, x, y, name)
    if not Mapz.Routing() then return false end

    -- TRIP-01's tour would pass every stop here, with options.onArrive to move to the next.
    local ok, routed = pcall(api().RouteTo, { mapID = mapID, x = x, y = y, name = name }, name, { start = true })
    return ok and routed == true
end

-- "45s", "1m 40s", "2m", "1h 2m".
function Mapz.TimeText(seconds)
    local s = math.floor(seconds + 0.5)
    if s < 60 then return s .. "s" end
    if s < 3600 then
        local m, r = math.floor(s / 60), s % 60
        return r > 0 and ("%dm %ds"):format(m, r) or ("%dm"):format(m)
    end
    local h, m = math.floor(s / 3600), math.floor(s % 3600 / 60)
    return m > 0 and ("%dh %dm"):format(h, m) or ("%dh"):format(h)
end

-- Picks by candidate key, for one API, one TimeTo and one player zone. False is a list
-- Mapzeroth gave no time for; the caller then falls back to distance.
local cache = { picks = {} }

local function playerZone()
    local best = C_Map.GetBestMapForUnit("player")
    return best and (CP.Waypoint.ZoneOf(best) or best) or false
end

-- Friendly spawns of `entries` that land on a zone map, each with its distance to the
-- player (Waypoint.Nearest's measure). Past `limit`, only the closest are kept.
local function candidates(entries, npcs, side, limit)
    local continent, px, py = CP.Waypoint.PlayerWorld()   -- also learns the axis order
    local list = {}
    for _, entry in ipairs(entries) do
        local npc = npcs[entry]
        if npc and (npc[2] == "N" or npc[2] == side) then
            for _, at in ipairs(npc[3]) do
                local zone, x, y = CP.Waypoint.SpawnPos(at)
                if zone and x >= 0 and x <= 1 and y >= 0 and y <= 1 then
                    local d
                    if continent and at[1] == continent and px then
                        d = (at[2] - px) ^ 2 + (at[3] - py) ^ 2
                    else
                        d = 1e18 + (at[1] == continent and 0 or 1)
                    end
                    list[#list + 1] = {
                        d = d, i = #list + 1,
                        point = { mapID = zone, x = x, y = y, name = npc[1] },
                        target = { name = npc[1], continent = at[1], x = at[2], y = at[3], roams = npc[4], entry = entry },
                    }
                end
            end
        end
    end
    if #list > limit then
        table.sort(list, function(a, b) if a.d ~= b.d then return a.d < b.d end return a.i < b.i end)
        for i = #list, limit + 1, -1 do list[i] = nil end
    end
    return list
end

-- The quickest candidate by one TimeTo search, with its `seconds`, or nil.
local function rank(a, entries, npcs, side)
    local list = candidates(entries, npcs, side, tonumber(a.MAX_POINTS) or MAX_POINTS)
    if #list == 0 then return nil end
    local points = {}
    for i, c in ipairs(list) do points[i] = c.point end
    local ok, times = pcall(a.TimeTo, points)
    if not ok or type(times) ~= "table" then return nil end
    local best, bestTime
    for i, c in ipairs(list) do
        local t = tonumber(times[i])
        if t and (not bestTime or t < bestTime) then best, bestTime = c, t end
    end
    if not best then return nil end
    best.target.seconds = bestTime
    return best.target
end

-- The friendly spawn of `entries` (creature ids in `npcs`) quickest to reach by
-- Mapzeroth: { name, continent, x, y, roams, entry, seconds }, or nil when Mapzeroth has no
-- TimeTo or gives no time. One search per list until the player's zone changes.
function Mapz.Nearest(entries, npcs, side)
    local a = api()
    if not (a and type(a.TimeTo) == "function" and entries and entries[1]) then return nil end
    local zone = playerZone()
    if cache.api ~= a or cache.fn ~= a.TimeTo or cache.zone ~= zone then
        cache = { api = a, fn = a.TimeTo, zone = zone, picks = {} }
    end
    local key = tostring(side) .. ":" .. table.concat(entries, ",")
    local pick = cache.picks[key]
    if pick == nil then
        pick = rank(a, entries, npcs, side) or false
        cache.picks[key] = pick
    end
    if not pick then return nil end
    local out = {}
    for k, v in pairs(pick) do out[k] = v end
    return out
end
