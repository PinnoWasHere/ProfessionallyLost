-- Review items 49 and 51 of the 2026-11 addon pass: side crafts that tie are picked in a fixed
-- order, and footprints learned mid-session re-key the drawn route.

local CP = ProfLost

-- A guide of orange side-craft candidates that all tie at chance 1, each needing one rare item.
local function sideGuide()
    local recipes, items = {}, {}
    local function add(id)
        recipes[id] = { name = "side" .. id, yellow = 150, grey = 200, reagents = { { id + 5000, 1 } } }
        items[id + 5000] = { 1, 1, 1, 1, true }
    end
    recipes[1000] = { name = "main", yellow = 150, grey = 200, reagents = {} }
    for _, id in ipairs({ 2005, 2002, 2009, 2001, 2007 }) do add(id) end
    return { recipes = recipes, items = items }
end

-- Replaces the global pairs with a walk over the keys in ascending or descending order.
local function walkKeys(desc)
    World.set(_G, "pairs", function(t)
        local keys = {}
        for k in next, t do keys[#keys + 1] = k end
        table.sort(keys, function(a, b)
            if desc then return a > b end
            return a < b
        end)
        local i = 0
        return function()
            i = i + 1
            local k = keys[i]
            if k ~= nil then return k, t[k] end
        end, t
    end)
end

local function winner(desc)
    local guide = sideGuide()
    local learned, held = {}, {}
    for id in next, guide.recipes do
        learned[id] = true
        held[id + 5000] = 5
    end
    World.set(CP.db, "collect", true)
    local steps = { { from = 100, to = 120, spell = 1000 } }
    walkKeys(desc)
    local out = CP.Plan.Sides(guide, steps, learned, held)
    return out[1] and out[1].spell
end

T.test("tied side crafts are picked by lowest spell id under either key order", function()
    local asc, desc = winner(false), winner(true)
    T.eq(asc, desc, "the same side craft wins under ascending and descending key order")
    T.eq(asc, 2001, "the lowest spell id wins a tie")
end)

T.test("footprints learned in a batch change the route key while the rows stay the same", function()
    local T_ = CP.Terrain
    local zone = 1411
    World.set(CP.db, "footprints", {})
    World.set(CP.db, "route", true)
    local n = 0
    local was = CP.Terrain.batches and CP.Terrain.batches[zone]
    World.onEnd(function() if CP.Terrain.batches then CP.Terrain.batches[zone] = was end end)
    if CP.Terrain.batches then CP.Terrain.batches[zone] = nil end
    World.set(_G, "UnitOnTaxi", function() return false end)
    World.set(_G, "IsFlying", function() return false end)
    World.set(_G, "IsSwimming", function() return false end)
    World.set(CP.Waypoint, "PlayerZone", function() return zone end)
    World.set(CP.Gather, "IsInstance", function() return false end)
    World.set(CP.Gather, "ZoneSize", function() return 4000, 4000 end)
    World.set(C_Map, "GetPlayerMapPosition", function()
        n = n + 1
        return { GetXY = function() return (n % 50) / 50, math.floor(n / 50) / 50 end }
    end)
    local rows = {}
    local before = CP.RouteMap.KeyOf(zone, rows)
    -- Other tests may leave part of a batch counted, so step until the batch lands.
    local steps = 0
    while steps < T_.LEARN_BATCH do
        steps = steps + 1
        T_.Step()
        if CP.RouteMap.KeyOf(zone, rows) ~= before then break end
    end
    T.ok(CP.RouteMap.KeyOf(zone, rows) ~= before, "a full batch of new cells re-keys the route")
    T.eq((CP.Terrain.batches or {})[zone], 1, "one full batch counted for the zone")
    T.eq((CP.Terrain.batches or {})[zone + 1], nil, "other zones are untouched")
end)
