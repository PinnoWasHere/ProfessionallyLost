-- Gathering loop solver, and the route it builds from the generated zone data.

local CP = ProfLost
local R = CP.Route
local W, H = 1000, 1000   -- a 1000 x 1000 yd zone

local function pt(x, y, value) return { x = x, y = y, value = value or 1 } end

local function grid()
    local out = {}
    for i = 0, 4 do
        for j = 0, 4 do out[#out + 1] = pt(0.3 + i * 0.05, 0.3 + j * 0.05, 3) end
    end
    return out
end

T.test("the loop visits every point once and closes", function()
    local points = grid()
    local r = R.Solve(points, W, H)
    T.eq(#r.loop, #points)
    local seen = {}
    for _, p in ipairs(r.loop) do
        T.ok(not seen[p], "visited twice")
        seen[p] = true
    end
    T.ok(math.abs(r.length - R.Length(r.loop, W, H)) < 1e-6)
end)

T.test("a minimap stop is an open ring the game's tracking blip shows through; the world map keeps its icon", function()
    local stop = { x = 0.5, y = 0.5, value = 1, prof = CP.Gather.MINING, name = "Copper Vein",
                   about = { ["Copper Vein"] = { skill = 1, item = 2770 } } }
    -- The harness reads no texture back, so each pin's ring is watched as it is set again.
    local function ringOf(make)
        local f = make()
        local set, last = f.ring.SetTexture, nil
        f.ring.SetTexture = function(self, path, ...)
            last = path
            return set(self, path, ...)
        end
        make()
        f.ring.SetTexture = set
        return f, tostring(last)
    end
    local mini, ring = ringOf(function() return CP.RouteMap.TestMiniStop(stop) end)
    T.ok(ring:find("StopRing", 1, true) ~= nil, "the ring is the open StopRing: " .. ring)
    T.ok(not mini.icon:IsShown(), "no icon over the middle")
    T.eq(mini.alpha, 1, "the ring itself stays full")
    T.eq(mini:GetWidth(), CP.RouteMap.MINI_STOP)
    T.eq(CP.RouteMap.MINI_STOP, 6, "minimap stops are small so the game's tracking dot stays the main mark")
    T.ok(not mini.rim:IsShown(), "one marker per stop: no accent rim over the ring")
    T.ok(CP.RouteMap.TestStop(stop).rim:IsShown(), "the world map stop keeps its rim")
    local world = CP.RouteMap.TestStop(stop)
    T.ok(world.icon:IsShown(), "the world map stop keeps its icon")
end)

T.test("a 5 x 5 grid is solved to its optimal 50 yd perimeter tour", function()
    local r = R.Solve(grid(), W, H)
    -- 25 points 50 yd apart: an optimal tour is 25 x 50 = 1250 yd, or one diagonal more.
    T.ok(r.length <= 1250 + 71 + 1e-6, ("loop is %.0f yd"):format(r.length))
end)

T.test("improvements never lengthen the nearest-neighbour tour", function()
    local points = {}
    local seed = 7
    for _ = 1, 60 do
        seed = (seed * 1103515245 + 12345) % 2147483648
        local x = (seed % 1000) / 1000
        seed = (seed * 1103515245 + 12345) % 2147483648
        points[#points + 1] = pt(x, (seed % 1000) / 1000, 1)
    end
    local old = R.PRUNE
    R.PRUNE = math.huge   -- no pruning, to compare tour lengths alone
    local solved = R.Solve(points, W, H, nil, false).length
    R.PRUNE = old
    local naive = 0
    for i = 1, #points do
        local a, b = points[i], points[i % #points + 1]
        naive = naive + math.sqrt(((a.x - b.x) * W) ^ 2 + ((a.y - b.y) * H) ^ 2)
    end
    T.ok(solved < naive, ("solved %.0f vs input order %.0f"):format(solved, naive))
end)

T.test("a lone far-off spawn is pruned, the dense patch kept", function()
    local points = grid()
    points[#points + 1] = pt(0.95, 0.95, 1)   -- 900 yd out, worth one spawn
    local r = R.Solve(points, W, H)
    T.eq(r.dropped, 1)
    for _, p in ipairs(r.loop) do T.ok(p.x < 0.9, "outlier still in the loop") end
    T.eq(#r.loop, 25)
end)

T.test("a valuable far-off patch is kept", function()
    local points = grid()
    local far = pt(0.95, 0.95, 200)
    points[#points + 1] = far
    local kept = false
    for _, p in ipairs(R.Solve(points, W, H).loop) do kept = kept or p == far end
    T.ok(kept, "200 spawns 900 yd out are worth the walk")
end)

T.test("dots are spaced along the loop", function()
    local loop = { pt(0, 0), pt(0.4, 0), pt(0.4, 0.4), pt(0, 0.4) }   -- a 400 yd square
    local dots = R.Dots(loop, W, H, 40)
    T.ok(#dots == 39 or #dots == 40, "1600 yd / 40 yd: " .. #dots)
    T.ok(math.abs(dots[1][1] - 0.04) < 1e-9 and dots[1][2] == 0)
end)

T.test("route points come from in-zone clusters of needed items only", function()
    local rows = {
        { itemID = 1, need = 10, done = false, sources = {
            { kind = "mob", entry = 100, name = "Boar", chance = 50, prof = 393 },
            { kind = "water", name = "Water", chance = 30, prof = 356 },
        } },
        { itemID = 2, need = 5, done = true, sources = { { kind = "node", entry = 200, chance = 100, prof = 186 } } },
        { itemID = 3, sources = { { kind = "node", entry = 300, chance = 100, prof = 186 } } },
    }
    local asked = {}
    local points = R.Points(1413, rows, function(kind, entry)
        asked[#asked + 1] = kind .. entry
        return { { 0.5, 0.5, 4 }, { 0.6, 0.5, 2 } }
    end)
    T.eq(#points, 2)
    T.eq(table.concat(asked, ","), "mobs100", "only the needed, unfinished item's creature")
    T.eq(points[1].value, 2, "4 spawns x 50%")
    T.eq(R.Key(1413, rows), "1413:1")
end)

T.test("packed clusters decode to zone-map points", function()
    local zone = CP.GatherData.zones[1429]
    local entry, packed = next(zone.mobs)
    local list = CP.Gather.Decode(packed)
    T.eq(#list, #packed / 5)
    for _, c in ipairs(list) do
        T.ok(c[1] >= 0 and c[1] <= 1 and c[2] >= 0 and c[2] <= 1, "inside the map")
        T.ok(c[3] >= 1, "at least one spawn")
    end
    T.ok(entry ~= nil)
end)

T.test("a Barrens route for Light Leather solves in reasonable size", function()
    local orig = CP.Waypoint.MapPosZone
    CP.Waypoint.MapPosZone = function(zone) return zone end   -- no zone map in the harness
    CP.Gather.ResetClusters()
    local rows = CP.Gather.Rows(1413, { [393] = 100 }, { [2318] = 50 }, function() return 0 end)
    local points = R.Points(1413, rows)
    T.ok(#points > 20, ("%d points"):format(#points))
    local z = CP.GatherData.zones[1413]
    local r = R.Solve(points, z.w, z.h)
    T.ok(#r.loop > 0 and r.length > 0)
    T.ok(r.length <= R.MAX_YD, ("loop %.0f yd"):format(r.length))
    local open = R.Solve(points, z.w, z.h, nil, false)
    T.ok(open.length > R.MAX_YD, "without the cap it spans the zone")
    local function density(res)
        local v = 0
        for _, p in ipairs(res.loop) do v = v + p.value end
        return v / res.length
    end
    T.ok(density(r) > density(open), "the capped loop gets more items per yard")
    CP.Waypoint.MapPosZone = orig
    CP.Gather.ResetClusters()
end)

T.test("with the route on, the Gather tab solves and draws a loop", function()
    local wasRoute = CP.db.route
    CP.db.route = true
    CP.charDB.gatherNeeds = { [165] = { [2318] = 200 }, [164] = { [2771] = 100 } }
    -- Restored when the test ends, so later files don't inherit Skinning and Mining.
    World.set(C_SkillInfo, "GetSkillLineInfoByID", function(id)
        if id == 393 or id == 186 then return { skillID = id, rank = 120, modifier = 0 } end
        return nil
    end)
    World.set(_G, "UnitLevel", function() return 20 end)
    World.patch("C_Item.GetItemCount", function() return 0 end)
    local zone, mapPos, replan = CP.Waypoint.PlayerZone, CP.Waypoint.MapPosZone, CP.Gather.UpdateAllNeeds
    CP.Gather.UpdateAllNeeds = function() end   -- keep the test's needs through timer refreshes
    CP.Waypoint.PlayerZone = function() return 1413 end
    CP.Waypoint.MapPosZone = function(z) return z end
    CP.Gather.ResetClusters()
    local pins = LibStub("HereBeDragons-Pins-2.0")
    local added = 0
    local add = pins.AddMinimapIconMap
    pins.AddMinimapIconMap = function(...) added = added + 1 return add(...) end
    T.ok(CP.GatherList.Refresh())
    T.advance(30)
    T.ok(CP.RouteMap.Status() ~= nil, "status after solving")
    T.ok(CP.RouteMap.Status():find("loop"), CP.RouteMap.Status())
    T.ok(CP.RouteMap.Status():find("3 grind spots"), CP.RouteMap.Status())
    T.ok(added > 10, ("%d minimap pins"):format(added))
    CP.db.route = false
    CP.GatherList.Refresh()
    pins.AddMinimapIconMap = add
    CP.Waypoint.PlayerZone, CP.Waypoint.MapPosZone, CP.Gather.UpdateAllNeeds = zone, mapPos, replan
    CP.Gather.ResetClusters()
    -- Set back last: a refresh with the route on under this test's map answers would cache them.
    CP.db.route = wasRoute
end)

T.test("grind spots take the densest groups of mobs, not overlapping", function()
    local points = {}
    for i = 0, 5 do points[#points + 1] = pt(0.20 + i * 0.01, 0.20, 2) end      -- a tight pack, 12 value
    for i = 0, 2 do points[#points + 1] = pt(0.70 + i * 0.01, 0.70, 2) end      -- a smaller pack
    points[#points + 1] = pt(0.95, 0.05, 1)                                      -- a straggler
    for i, p in ipairs(points) do
        p.name, p.prof = i % 2 == 0 and "Wolf" or "Boar", 393
        p.parts, p.items = { [p.name] = p.value }, { [2318] = p.value }
    end
    local spots = R.GrindSpots(points, W, H, 100, 3)
    T.eq(#spots, 3)
    T.eq(spots[1].value, 12, "the big pack first")
    T.ok(math.abs(spots[1].x - 0.225) < 1e-9, "centred on the pack")
    T.eq(spots[2].value, 6)
    T.eq(spots[3].value, 1)
    T.eq(spots[1].parts.Wolf, 6, "every creature in the spot is listed")
    T.eq(spots[1].parts.Boar, 6)
    T.eq(spots[1].itemID, 2318)
end)

T.test("route points split into creatures and nodes", function()
    local rows = { { itemID = 1, need = 10, sources = {
        { kind = "mob", entry = 100, name = "Boar", chance = 50, prof = 393 },
        { kind = "node", entry = 200, name = "Copper Vein", chance = 100, prof = 186 },
    } } }
    local stub = function(kind) return kind == "mobs" and { { 0.2, 0.2, 2 } } or { { 0.8, 0.8, 1 } } end
    T.eq(#R.Points(1413, rows, stub, "mob"), 1)
    T.eq(R.Points(1413, rows, stub, "mob")[1].kind, "mob")
    T.eq(R.Points(1413, rows, stub, "node")[1].kind, "node")
    T.eq(#R.Points(1413, rows, stub), 2)
end)

T.test("a grind spot's area reaches its farthest mobs", function()
    local points = {}
    for i = 0, 4 do points[#points + 1] = pt(0.40 + i * 0.02, 0.40, 2) end   -- 80 yd across
    local spot = R.GrindSpots(points, W, H, 150, 1)[1]
    T.ok(math.abs(spot.radius - 80) < 1e-6, ("radius %.1f: 40 yd to the edge mob plus 40"):format(spot.radius))
    local lone = R.GrindSpots({ pt(0.5, 0.5, 1) }, W, H, 150, 1)[1]
    T.eq(lone.radius, 60, "a single camp still gets a visible area")
end)

T.test("grind spots carry each creature's levels and drop chances", function()
    local rows = { { itemID = 2319, need = 10, sources = {
        { kind = "mob", entry = 4067, name = "Twilight Runner", minLevel = 23, maxLevel = 24, chance = 48.5, prof = 393 },
    } } }
    local stub = function() return { { 0.5, 0.5, 6 } } end
    local spot = R.GrindSpots(R.Points(1442, rows, stub, "mob"), 4883, 3256, nil, 1)[1]
    local about = spot.about["Twilight Runner"]
    T.eq(about.minLevel, 23)
    T.eq(about.drops[2319], 48.5, "the drop chance, not the spot share")
end)

T.test("grind spots are ranked best first", function()
    local points = {}
    for i = 0, 3 do points[#points + 1] = pt(0.2 + i * 0.01, 0.2, 2) end
    points[#points + 1] = pt(0.8, 0.8, 1)
    for _, p in ipairs(points) do p.parts, p.items = { Wolf = p.value }, { [2319] = p.value } end
    local spots = R.GrindSpots(points, W, H, 100, 3)
    T.eq(spots[1].rank, 1)
    T.eq(spots[2].rank, 2)
    T.eq(spots[1].items[2319], 8, "about 8 per clear at the best spot")
end)

T.test("kill speed: lower mobs count more, higher less, 4+ levels up ranks last", function()
    T.eq(R.KillSpeed(20, 20), 1)
    T.ok(R.KillSpeed(17, 20) > 1.3, "3 below: quicker kills")
    T.eq(R.KillSpeed(5, 20), 1.4, "capped")
    T.ok(math.abs(R.KillSpeed(23, 20) - 0.64) < 1e-9, "3 above: slower")
    T.eq(R.KillSpeed(24, 20), 0.15, "4 above: risky")
    T.eq(R.KillSpeed(nil, 20), 1, "unknown level: no change")
end)

T.test("a bigger pack of mobs 5 levels up loses to a smaller one at the player's level", function()
    local rows = { { itemID = 2319, need = 10, sources = {
        { kind = "mob", entry = 1, name = "Ogre", minLevel = 25, maxLevel = 25, chance = 50, prof = 393 },
        { kind = "mob", entry = 2, name = "Boar", minLevel = 20, maxLevel = 20, chance = 50, prof = 393 },
    } } }
    local stub = function(_, entry)
        if entry == 1 then return { { 0.2, 0.2, 10 } } end
        return { { 0.8, 0.8, 6 } }
    end
    local unweighted = R.GrindSpots(R.Points(1442, rows, stub, "mob"), 4883, 3256, nil, 1)[1]
    T.eq(unweighted.name, "Ogre", "without a level: the bigger pack")
    local spot = R.GrindSpots(R.Points(1442, rows, stub, "mob", 20), 4883, 3256, nil, 1)[1]
    T.eq(spot.name, "Boar", "at level 20: the mobs that die fast")
    T.eq(spot.items[2319], 3, "the shown yield stays the raw count")
end)

-- Pairs of non-adjacent segments of a closed line that cross.
local function crossings(line, w, h)
    local n, count = #line, 0
    local function at(i) return line[i].x * w, line[i].y * h end
    local function side(ax, ay, bx, by, cx, cy) return (bx - ax) * (cy - ay) - (by - ay) * (cx - ax) end
    for i = 1, n do
        local ax, ay = at(i)
        local bx, by = at(i % n + 1)
        for j = i + 2, n do
            if not (i == 1 and j == n) then
                local cx, cy = at(j)
                local dx, dy = at(j % n + 1)
                local d1, d2 = side(cx, cy, dx, dy, ax, ay), side(cx, cy, dx, dy, bx, by)
                local d3, d4 = side(ax, ay, bx, by, cx, cy), side(ax, ay, bx, by, dx, dy)
                if d1 * d2 < 0 and d3 * d4 < 0 then count = count + 1 end
            end
        end
    end
    return count
end

-- Hillsbrad's herb and Copper/Tin node clusters, merged into route stops.
local function hillsbradStops(herbs, ore)
    local HILLSBRAD = 1424
    local w, h = CP.Gather.ZoneSize(HILLSBRAD)
    local pts = {}
    for entry in pairs(CP.GatherData.zones[HILLSBRAD].nodes) do
        local n = CP.GatherData.nodes[entry]
        if (herbs and n[4] == CP.Gather.HERBALISM) or (ore and (n[1] == "Copper Vein" or n[1] == "Tin Vein")) then
            for _, c in ipairs(CP.Gather.Clusters(HILLSBRAD, "nodes", entry)) do
                pts[#pts + 1] = { x = c[1], y = c[2], value = c[3] }
            end
        end
    end
    return R.Merge(pts, w, h), w, h
end

T.test("self-overlap: a square is clean, an out-and-back runs alongside itself", function()
    local square = { pt(0.1, 0.1), pt(0.6, 0.1), pt(0.6, 0.6), pt(0.1, 0.6) }
    T.eq(R.SelfOverlap(square, W, H, 150, 400), 0)
    local hairpin = { pt(0.1, 0.1), pt(0.8, 0.1), pt(0.8, 0.15), pt(0.1, 0.15) }   -- lanes 50 yd apart
    -- The middle half of the way back is over 400 yd along the loop from the way out.
    local share = R.SelfOverlap(hairpin, W, H, 150, 400)
    T.ok(share > 0.2 and share < 0.25, ("%.3f of the loop runs beside itself"):format(share))
end)

T.test("capped loops over dense ground make one clean circuit, not parallel lanes", function()
    local orig = CP.Waypoint.MapPosZone
    CP.Waypoint.MapPosZone = function(zone) return zone end
    CP.Gather.ResetClusters()
    CP.Terrain.Reset()
    local ok, err = pcall(function()
        local cases = {
            { "herbs, farming, walking", true, false, R.FARM_YD, true },
            { "herbs and ore, farming", true, true, R.FARM_YD, false },
            { "herbs and ore, levelling", true, true, R.MAX_YD, false },
        }
        for _, c in ipairs(cases) do
            local stops, w, h = hillsbradStops(c[2], c[3])
            local g = c[5] and CP.Terrain.Grid(1424, w, h, { side = "Horde", level = 30 }) or nil
            local r = R.Solve(stops, w, h, nil, c[4], g)
            local lanes = R.SelfOverlap(r.path, w, h, 150, 400)
            local retraced = R.SelfOverlap(r.path, w, h, 40, 200)
            T.ok(#r.loop >= 20, ("%s: %d stops"):format(c[1], #r.loop))
            T.ok(lanes <= 0.03, ("%s: %.3f of the loop runs within 150 yd of itself"):format(c[1], lanes))
            T.ok(retraced <= 0.005, ("%s: %.3f retraces itself"):format(c[1], retraced))
            T.eq(crossings(r.path, w, h), 0, c[1] .. ": the loop never crosses itself")
        end
    end)
    CP.Waypoint.MapPosZone = orig
    CP.Gather.ResetClusters()
    CP.Terrain.Reset()
    T.ok(ok, err)
end)

T.test("a nearer spot beats a slightly richer one far away", function()
    local points = {
        pt(0.10, 0.10, 10),   -- richer, far corner
        pt(0.80, 0.80, 8),    -- nearer the player
    }
    for _, p in ipairs(points) do p.parts, p.items = { Wolf = p.value }, { [2319] = p.value } end
    T.eq(R.GrindSpots(points, W, H, 100, 1)[1].value, 10, "no position: the richer")
    local near = R.GrindSpots(points, W, H, 100, 1, { x = 0.82, y = 0.82 })[1]
    T.eq(near.value, 8, "from the player's spot: the nearer")
end)
