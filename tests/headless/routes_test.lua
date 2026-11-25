-- Route nodes and length (review items 7, 9, 25):
-- nodes known only from GatherMate2, finds or peers get skill-up and Farm rows; the
-- terrain prune cuts by walked yards; the loop length is walked yards.

local CP = ProfLost
local G, GM = CP.Gather, CP.GatherMate
local DUROTAR, HERB = 1411, 182
local GRAVE_MOSS_NODE = 1628

local function fake(db, names)
    return {
        GetNodesForZone = function(_, zone, nodeType) return pairs(db[nodeType] and db[nodeType][zone] or {}) end,
        GetNameForNode = function(_, nodeType, id) return names[nodeType] and names[nodeType][id] end,
    }
end

-- Runs fn with a stand-in GatherMate2 holding `count` Grave Moss spots in Durotar.
local function withGraveMoss(count, fn)
    local db = { ["Herb Gathering"] = { [DUROTAR] = {} } }
    for i = 1, count do db["Herb Gathering"][DUROTAR][(2000 + i * 300) * 1000000 + (3000 + i * 200) * 100] = 7 end
    local addon = fake(db, { ["Herb Gathering"] = { [7] = "Grave Moss" } })
    local mapPos, orig = CP.Waypoint.MapPosZone, GM.Addon
    CP.Waypoint.MapPosZone = function(zone) return zone end
    GM.Addon = function() return addon end
    GM.Reset()
    local ok, err = pcall(fn)
    CP.Waypoint.MapPosZone = mapPos
    GM.Addon = orig
    GM.Reset()
    T.ok(ok, err)
end

local function hasName(rows, name)
    for _, r in ipairs(rows) do
        for _, s in ipairs(r.sources) do if s.name == name then return true end end
    end
    return false
end

T.test("the data holds no Grave Moss in Durotar, so only recorded finds can route it", function()
    T.ok(CP.GatherData.nodes[GRAVE_MOSS_NODE] and CP.GatherData.nodes[GRAVE_MOSS_NODE][1] == "Grave Moss")
    T.ok(not CP.GatherData.zones[DUROTAR].nodes[GRAVE_MOSS_NODE], "not in Durotar's data")
end)

T.test("a herb known only from GatherMate2 gets a skill-up row and a Farm row", function()
    withGraveMoss(10, function()
        local listed = false
        for _, n in ipairs(G.RouteNodes(HERB, DUROTAR)) do if n.name == "Grave Moss" then listed = true end end
        T.ok(listed, "the route menu lists it")
        T.ok(hasName(G.SkillRows(DUROTAR, { [HERB] = 130 }), "Grave Moss"), "levelling row at 130")
        local farm = CP.db.routeMode
        CP.db.routeMode = "farm"
        local rows = G.SkillRows(DUROTAR, { [HERB] = 130 })
        CP.db.routeMode = farm
        T.ok(hasName(rows, "Grave Moss"), "Farm row")
    end)
end)

T.test("a herb with too few recorded spots still gets no row", function()
    withGraveMoss(G.MIN_NODE_SPAWNS - 1, function()
        T.ok(not hasName(G.SkillRows(DUROTAR, { [HERB] = 130 }), "Grave Moss"))
    end)
end)

-- A 2000 x 500 yd zone of 50 yd cells, open but for columns 18 to 21 (a 200 yd gap), with
-- 14 stops in a row on each side of the gap: 28 stops, a 3600 yd loop, 6400 with the gap
-- weighted at 8 a yard.
local function gapZone()
    local g = { cols = 40, rows = 10, cell = 50, w = 2000, h = 500, open = {} }
    for r = 0, 9 do
        for c = 0, 39 do
            if c < 18 or c > 21 then g.open[r * 40 + c] = true end
        end
    end
    local pts = {}
    for i = 0, 13 do
        pts[#pts + 1] = { x = (100 + i * 60) / 2000, y = 0.5, value = 1 }
        pts[#pts + 1] = { x = (1120 + i * 60) / 2000, y = 0.5, value = 1 }
    end
    return g, pts
end

T.test("a loop across a gap keeps its stops while the walk is under the cap", function()
    local g, pts = gapZone()
    local r = CP.Route.Solve(pts, 2000, 500, nil, nil, g)
    T.eq(#r.loop, 28, "all stops stay")
    T.eq(r.dropped, 0)
end)

T.test("the loop length is walked yards, not terrain cost", function()
    local g, pts = gapZone()
    local r = CP.Route.Solve(pts, 2000, 500, nil, nil, g)
    T.ok(math.abs(r.length - 3600) < 150, ("%.0f yd, the walk is about 3600"):format(r.length))
end)

T.test("a terrain loop is still cut to the cap in walked yards", function()
    local g, pts = gapZone()
    local r = CP.Route.Solve(pts, 2000, 500, nil, 2500, g)
    T.ok(r.length <= 2500 + 1, ("%.0f yd under a 2500 yd cap"):format(r.length))
    T.ok(#r.loop < 28 and #r.loop >= 3, ("%d stops"):format(#r.loop))
end)
