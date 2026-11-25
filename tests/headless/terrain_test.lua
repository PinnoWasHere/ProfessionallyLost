-- Terrain: walking paths round ground nothing spawns on.

local CP = ProfLost
local TR = CP.Terrain

-- A 10 x 10 grid of 50 yd cells (500 yd square) with a wall three columns wide,
-- open only along the bottom row: the U-shaped ground a valley path takes.
local function walled()
    local g = { cols = 10, rows = 10, cell = 50, w = 500, h = 500, open = {} }
    for r = 0, 9 do
        for c = 0, 9 do
            if c < 4 or c > 6 or r == 9 then g.open[r * 10 + c] = true end
        end
    end
    return g
end

T.test("a path goes round the wall, not over it", function()
    local g = walled()
    local a, b = { x = 0.15, y = 0.15 }, { x = 0.85, y = 0.15 }
    local d = TR.Distances(g, { a, b })
    T.ok(d[a][b] > 900, ("round the wall: %.0f yd, the straight line is 350"):format(d[a][b]))
    local path = TR.Path(g, a, b)
    local low = 0
    for _, p in ipairs(path) do low = math.max(low, p.y) end
    T.ok(low > 0.85, "the path dips to the open bottom row")
    T.eq(path[#path].x, b.x)
end)

T.test("open ground keeps the straight line", function()
    local g = { cols = 10, rows = 10, cell = 50, w = 500, h = 500, open = {} }
    for i = 0, 99 do g.open[i] = true end
    local a, b = { x = 0.15, y = 0.15 }, { x = 0.85, y = 0.85 }
    local path = TR.Path(g, a, b)
    T.eq(#path, 1, "no corners")
    local d = TR.Distances(g, { a, b })
    T.ok(math.abs(d[a][b] - 350 * 1.4142) < 60, ("about the straight distance: %.0f"):format(d[a][b]))
end)

T.test("a solved loop follows the walking paths", function()
    local g = walled()
    local pts = { { x = 0.2, y = 0.2, value = 1 }, { x = 0.8, y = 0.2, value = 1 },
                  { x = 0.8, y = 0.5, value = 1 }, { x = 0.2, y = 0.5, value = 1 } }
    local r = CP.Route.Solve(pts, 500, 500, nil, false, g)
    T.eq(#r.loop, 4)
    T.ok(#r.path > #r.loop, "corners added where the wall is")
    for _, p in ipairs(r.path) do
        local c, row = math.floor(p.x * 10), math.floor(p.y * 10)
        T.ok(g.open[row * 10 + c], ("path point %.2f,%.2f on open ground"):format(p.x, p.y))
    end
end)

-- Yards along `path` from `a` to its end, and the straight line from `a` to the end.
local function walked(g, a, path)
    local total, at = 0, a
    for _, p in ipairs(path) do
        total = total + math.sqrt(((p.x - at.x) * g.w) ^ 2 + ((p.y - at.y) * g.h) ^ 2)
        at = p
    end
    local b = path[#path]
    return total, math.sqrt(((b.x - a.x) * g.w) ^ 2 + ((b.y - a.y) * g.h) ^ 2)
end

-- A 20 x 10 grid, open, with a band of cells near stronger creatures across columns 8-11,
-- rows 0-7: the straight line crosses it, the open rows 8-9 go round it.
local function dangerBand()
    local g = { cols = 20, rows = 10, cell = 50, w = 1000, h = 500, open = {}, cost = {}, danger = {} }
    for r = 0, 9 do
        for c = 0, 19 do
            local i = r * 20 + c
            if c >= 8 and c <= 11 and r <= 7 then g.cost[i], g.danger[i] = TR.DANGER, true else g.open[i] = true end
        end
    end
    return g
end

T.test("a path past stronger creatures stays near the straight line", function()
    local g = dangerBand()
    local a, b = { x = 0.2, y = 0.3 }, { x = 0.8, y = 0.3 }
    local len, straight = walked(g, a, TR.Path(g, a, b))
    T.ok(len <= straight * 1.3, ("walked %.0f yd for a %.0f yd straight line"):format(len, straight))
end)

T.test("a line through ground near stronger creatures is drawn straight, not in grid steps", function()
    local g = { cols = 20, rows = 20, cell = 50, w = 1000, h = 1000, open = {}, cost = {}, danger = {} }
    for i = 0, 399 do g.cost[i], g.danger[i] = TR.DANGER, true end
    local a, b = { x = 0.12, y = 0.13 }, { x = 0.83, y = 0.41 }
    local path = TR.Path(g, a, b)
    T.eq(#path, 1, "no corners")
end)

T.test("water still turns a path to its crossing", function()
    -- A river across columns 7-12 but for a ford at row 9.
    local g = { cols = 20, rows = 10, cell = 50, w = 1000, h = 500, open = {}, cost = {}, danger = {} }
    for r = 0, 9 do
        for c = 0, 19 do
            local i = r * 20 + c
            if c >= 7 and c <= 12 and r < 9 then g.cost[i] = TR.WATER else g.open[i] = true end
        end
    end
    local a, b = { x = 0.2, y = 0.1 }, { x = 0.8, y = 0.1 }
    local path = TR.Path(g, a, b)
    local low = 0
    for _, p in ipairs(path) do low = math.max(low, p.y) end
    T.ok(low > 0.85, "the path goes by the ford")
end)

T.test("stops gather spawns within the cluster radius of their lead", function()
    local pts = {}
    for i = 0, 19 do
        pts[#pts + 1] = { x = 0.1 + (i % 5) * 0.03, y = 0.1 + math.floor(i / 5) * 0.03, value = 1 + i % 3 }
    end
    local stops = CP.Route.Merge(pts, 1000, 1000, 30)
    T.ok(#stops > 1 and #stops < #pts, ("%d spawns into %d stops"):format(#pts, #stops))
    local total = 0
    for _, s in ipairs(stops) do total = total + s.value end
    T.eq(total, 39, "no spawn lost or counted twice")
end)

T.test("smoothing rounds corners on open ground and keeps stops", function()
    local g = { cols = 10, rows = 10, cell = 50, w = 500, h = 500, open = {} }
    for i = 0, 99 do g.open[i] = true end
    local stop = { x = 0.1, y = 0.1, value = 1 }
    local path = { stop, { x = 0.9, y = 0.1 }, { x = 0.9, y = 0.9 }, { x = 0.1, y = 0.9 } }
    local out = TR.Smooth(g, path)
    T.ok(#out > #path, "corners cut")
    local kept = false
    for _, p in ipairs(out) do kept = kept or p == stop end
    T.ok(kept, "the stop stays")
end)

T.test("a terrain solve yields inside a coroutine, as the route runner drives it", function()
    local g = walled()
    local pts = {}
    for i = 0, 7 do pts[#pts + 1] = { x = 0.1 + (i % 4) * 0.25, y = 0.2 + math.floor(i / 4) * 0.4, value = 1 } end
    local co = coroutine.create(function()
        return CP.Route.Solve(pts, 500, 500, function() coroutine.yield() end, false, g)
    end)
    local ok, res, yields = true, nil, 0
    while coroutine.status(co) ~= "dead" do
        ok, res = coroutine.resume(co)
        if not ok then break end
        yields = yields + 1
    end
    T.ok(ok, tostring(res))
    T.ok(yields > 1, "it yielded")
    T.ok(res and #res.path >= #res.loop, "and finished with a path")
end)

T.test("a Horde route keeps out of an Alliance town", function()
    local orig, origMap = CP.Waypoint.SpawnPos, CP.Waypoint.MapPosZone
    CP.Waypoint.MapPosZone = function(zone) return zone end
    CP.Gather.ResetClusters()
    TR.Reset()
    local HILLSBRAD = 1424
    -- Every Alliance trainer or vendor stands at the zone's middle in this test.
    CP.Waypoint.SpawnPos = function() return HILLSBRAD, 0.5, 0.5 end
    local ok, err = pcall(function()
        local z = CP.GatherData.zones[HILLSBRAD]
        local horde = TR.Grid(HILLSBRAD, z.w, z.h, { side = "Horde", level = 30 })
        local none = TR.Grid(HILLSBRAD, z.w, z.h, { level = 30 })
        T.ok(horde and none, "Hillsbrad has enough spawn data")
        local mid = math.floor(0.5 * z.h / 50) * horde.cols + math.floor(0.5 * z.w / 50)
        T.eq(horde.cost[mid], TR.TOWN, "the town costs the Horde")
        T.ok((none.cost[mid] or 1) < TR.TOWN, "no faction, no town")
    end)
    CP.Waypoint.SpawnPos, CP.Waypoint.MapPosZone = orig, origMap
    CP.Gather.ResetClusters()
    TR.Reset()
    T.ok(ok, err)
end)

T.test("fishing pools mark water, not open ground", function()
    local origMap = CP.Waypoint.MapPosZone
    CP.Waypoint.MapPosZone = function(zone) return zone end
    CP.Gather.ResetClusters()
    TR.Reset()
    local ok, err = pcall(function()
        local found
        for zone, z in pairs(CP.GatherData.zones) do
            for entry in pairs(z.nodes or {}) do
                local n = CP.GatherData.nodes[entry]
                if n and n[4] == CP.Gather.FISHING and z.w then found = { zone, entry, z } break end
            end
            if found then break end
        end
        T.ok(found, "some zone has a pool")
        local zone, entry, z = found[1], found[2], found[3]
        local g = TR.Grid(zone, z.w, z.h, {})
        if g then
            local c = CP.Gather.Clusters(zone, "nodes", entry)[1]
            local i = math.floor(c[2] * z.h / 50) * g.cols + math.floor(c[1] * z.w / 50)
            T.eq(g.cost[i], TR.WATER)
            T.ok(not g.open[i], "a pool's cell is not open ground")
        end
    end)
    CP.Waypoint.MapPosZone = origMap
    CP.Gather.ResetClusters()
    TR.Reset()
    T.ok(ok, err)
end)

T.test("a capped loop centres near the player", function()
    local pts = {}
    -- Two equal patches 3000 yd apart on a 4000 yd map.
    for i = 0, 8 do
        pts[#pts + 1] = { x = 0.1 + (i % 3) * 0.01, y = 0.1 + math.floor(i / 3) * 0.01, value = 1 }
        pts[#pts + 1] = { x = 0.85 + (i % 3) * 0.01, y = 0.85 + math.floor(i / 3) * 0.01, value = 1 }
    end
    local r = CP.Route.Solve(pts, 4000, 4000, nil, 1000, nil, { x = 0.9, y = 0.9 })
    for _, p in ipairs(r.loop) do T.ok(p.x > 0.5, "the loop is the patch by the player") end
    T.ok(CP.Route.FARM_YD > CP.Route.MAX_YD, "farming loops run longer")
end)

T.test("the terrain pass never walks farther than the straight order it starts from", function()
    local origMap = CP.Waypoint.MapPosZone
    CP.Waypoint.MapPosZone = function(zone) return zone end
    CP.Gather.ResetClusters()
    TR.Reset()
    local ok, err = pcall(function()
        local HILLSBRAD = 1424
        local w, h = CP.Gather.ZoneSize(HILLSBRAD)
        local pts = {}
        for entry in pairs(CP.GatherData.zones[HILLSBRAD].nodes) do
            local n = CP.GatherData.nodes[entry]
            if n[1] == "Copper Vein" or n[1] == "Tin Vein" then
                for _, c in ipairs(CP.Gather.Clusters(HILLSBRAD, "nodes", entry)) do
                    pts[#pts + 1] = { x = c[1], y = c[2], value = 1 }
                end
            end
        end
        local stops = CP.Route.Merge(pts, w, h)
        local g = TR.Grid(HILLSBRAD, w, h, { side = "Horde", level = 30 })
        T.ok(g, "Hillsbrad has a grid")
        local straight = CP.Route.Solve(stops, w, h, nil, false)
        local walking = CP.Route.Solve(stops, w, h, nil, false, g)
        local d = TR.Distances(g, straight.loop)
        local before = 0
        for i = 1, #straight.loop do before = before + d[straight.loop[i]][straight.loop[i % #straight.loop + 1]] end
        T.ok(walking.length <= before + 1, ("walking %.0f yd, the straight order walks %.0f"):format(walking.length, before))
    end)
    CP.Waypoint.MapPosZone = origMap
    CP.Gather.ResetClusters()
    TR.Reset()
    T.ok(ok, err)
end)

T.test("footprints: walked cells become ground, swum cells water", function()
    local origMap = CP.Waypoint.MapPosZone
    CP.Waypoint.MapPosZone = function(zone) return zone end
    CP.Gather.ResetClusters()
    TR.Reset()
    local saved = CP.db.footprints
    CP.db.footprints = nil
    local ok, err = pcall(function()
        local HILLSBRAD = 1424
        local w, h = CP.Gather.ZoneSize(HILLSBRAD)
        local g = TR.Grid(HILLSBRAD, w, h, {})
        -- A cell nothing spawns near, and one that is open.
        local rough, open
        for i = 0, g.cols * g.rows - 1 do
            if not g.open[i] and not g.cost[i] then rough = rough or i end
            if g.open[i] then open = open or i end
        end
        local function center(i)
            return ((i % g.cols) + 0.5) * 50 / w, (math.floor(i / g.cols) + 0.5) * 50 / h
        end
        local rx, ry = center(rough)
        local ox, oy = center(open)
        T.ok(TR.Learn(HILLSBRAD, rx, ry, false, w, h), "a new walked cell")
        T.ok(not TR.Learn(HILLSBRAD, rx, ry, false, w, h), "learned once")
        T.ok(TR.Learn(HILLSBRAD, ox, oy, true, w, h), "a new swum cell")
        TR.Reset()
        g = TR.Grid(HILLSBRAD, w, h, {})
        T.ok(g.open[rough], "walked: ground")
        T.eq(g.cost[open], TR.WATER, "swum: water")
        T.ok(not g.open[open])
        T.ok(TR.Learn(HILLSBRAD, ox, oy, false, w, h), "walking it later")
        TR.Reset()
        g = TR.Grid(HILLSBRAD, w, h, {})
        T.ok(g.open[open] and not g.cost[open], "shallows walked are ground")
    end)
    CP.db.footprints = saved
    CP.Waypoint.MapPosZone = origMap
    CP.Gather.ResetClusters()
    TR.Reset()
    T.ok(ok, err)
end)
