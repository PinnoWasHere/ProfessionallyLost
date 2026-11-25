-- Solves that interleave keep their own terrain metric and walking record (item 35), and
-- the stop rings recolour after a skill-up that changes no route source (item 36).

local CP = ProfLost
local R = CP.Route
local RM = CP.RouteMap
local W, H = 1000, 1000

-- Points on a ring, tagged with the grid that owns them. `ord` is a shuffled walking
-- order: the fake terrain makes stops cheap to reach when their `ord` is close.
local function ring(owner, n, shift)
    local out = {}
    for i = 1, n do
        local a = i * 2 * math.pi / n
        out[i] = { x = 0.5 + 0.3 * math.cos(a), y = 0.5 + 0.3 * math.sin(a), value = 1, owner = owner,
            ord = (i * 5 + shift) % n, id = owner .. i }
    end
    return out
end

-- A fake terrain: each grid prices a pair by the gap in `ord` times its own rate.
local function fakeTerrain(wrong)
    local T_ = CP.Terrain
    World.set(T_, "Distances", function(g, points)
        local out = {}
        for _, a in ipairs(points) do
            local row = {}
            for _, b in ipairs(points) do row[b] = math.abs(a.ord - b.ord) * g.rate + 1 end
            out[a] = row
        end
        return out
    end)
    World.set(T_, "Path", function(g, a, b, tick)
        if a.owner ~= g.name or b.owner ~= g.name then wrong.n = wrong.n + 1 end
        if tick then tick() end
        return { { x = b.x, y = b.y } }
    end)
    World.set(T_, "Smooth", function(g, path) return path end)
end

local function ids(result)
    local out = {}
    for i, p in ipairs(result.loop) do out[i] = p.id end
    return table.concat(out, ",")
end

-- Runs each solve as a coroutine that yields at every tick, round robin, to the end.
local function interleave(solves)
    local jobs, results = {}, {}
    for i, solve in ipairs(solves) do
        jobs[i] = coroutine.create(function() results[i] = solve(function() coroutine.yield() end) end)
    end
    local live = #jobs
    while live > 0 do
        live = 0
        for _, job in ipairs(jobs) do
            if coroutine.status(job) ~= "dead" then
                local ok, err = coroutine.resume(job)
                if not ok then error(err) end
                live = live + 1
            end
        end
    end
    return results
end

T.test("a solve keeps its own metric and walking record when another solve runs between its yields", function()
    local wrong = { n = 0 }
    fakeTerrain(wrong)
    local gridA, gridB = { name = "A", rate = 100 }, { name = "B", rate = 7 }
    local function solveA(tick)
        return R.Solve(ring("A", 12, 0), W, H, tick, 1e9, gridA)
    end
    local function solveB(tick)
        return R.Solve(ring("B", 14, 3), W, H, tick, 1e9, gridB)
    end
    local soloA, soloB = interleave({ solveA })[1], interleave({ solveB })[1]
    T.eq(wrong.n, 0, "a lone solve reads only its own grid")
    local both = interleave({ solveA, solveB })
    T.eq(wrong.n, 0, "an interleaved solve reads only its own grid")
    T.eq(ids(both[1]), ids(soloA), "A's loop is the one it makes alone")
    T.eq(ids(both[2]), ids(soloB), "B's loop is the one it makes alone")
    T.ok(math.abs(both[1].length - soloA.length) < 1e-6, "A's length")
    T.ok(math.abs(both[2].length - soloB.length) < 1e-6, "B's length")
    T.ok(next(both[1]) and #both[1].path > 0, "a path to draw")
end)

T.test("a solve with no terrain is not measured by another solve's metric", function()
    local wrong = { n = 0 }
    fakeTerrain(wrong)
    local grid = { name = "A", rate = 100 }
    local function terrain(tick) return R.Solve(ring("A", 12, 0), W, H, tick, 1e9, grid) end
    local function straight(tick) return R.Solve(ring("S", 12, 0), W, H, tick, 1e9) end
    local solo = interleave({ straight })[1]
    local both = interleave({ terrain, straight })
    T.eq(ids(both[2]), ids(solo), "the straight-line loop is the one it makes alone")
    T.ok(math.abs(both[2].length - solo.length) < 1e-6, "its length")
end)

-- Item 36 ---------------------------------------------------------------------------

T.test("the stop rings recolour after a skill-up that leaves every route source the same", function()
    MapWorld.begin({ zone = 1411, x = 0.5, y = 0.5, level = 20, side = "Horde", shareSolves = true })
    local was = { CP.db.otherZones, CP.db.route }
    CP.db.route, CP.db.otherZones = true, false
    CP.charDB.gatherNeeds = { [164] = { [2771] = 100 } }
    local rank = 20
    World.set(C_SkillInfo, "GetSkillLineInfoByID", function(id)
        if id == CP.Gather.MINING then return { skillID = id, rank = rank, modifier = 0 } end
        return nil
    end)
    World.patch("C_Item.GetItemCount", function() return 0 end)
    local replan = CP.Gather.UpdateAllNeeds
    CP.Gather.UpdateAllNeeds = function() end
    CP.Gather.ResetClusters()

    -- Every texture records the last colour it was given, those pooled by earlier tests too.
    local class = getmetatable(CreateFrame("Frame"):CreateTexture()).__index
    local set = class.SetVertexColor
    World.set(class, "SetVertexColor", function(tex, r, g, b, ...)
        tex.seen = ("%.2f,%.2f,%.2f"):format(r, g, b)
        return set(tex, r, g, b, ...)
    end)
    local pins = LibStub("HereBeDragons-Pins-2.0")
    local addW = pins.AddWorldMapIconMap
    local rings = {}
    pins.AddWorldMapIconMap = function(self, ref, icon, ...)
        if icon.stop and icon.ring then
            rings[#rings + 1] = tostring(icon.ring.seen)
        end
        return addW(self, ref, icon, ...)
    end
    local ok, err = pcall(function()
        CP.GatherList.RouteOnly()
        T.advance(5)
        T.ok(#rings > 0, "stops drawn")
        local before = rings[#rings]
        local key = RM.KeyOf(1411, CP.GatherList.RouteRows(1411, nil, true))
        rings = {}
        rank = 40
        CP.GatherList.RouteOnly()
        T.advance(5)
        T.eq(RM.KeyOf(1411, CP.GatherList.RouteRows(1411, nil, true)), key, "the route key did not move")
        T.ok(#rings > 0, "the stops were drawn again")
        T.ok(rings[#rings] ~= before, "the ring colour changed: " .. before .. " -> " .. tostring(rings[#rings]))
    end)
    CP.db.otherZones, CP.db.route = false, false
    RM.Update(false, {})
    T.advance(1)
    pins.AddWorldMapIconMap = addW
    CP.Gather.UpdateAllNeeds = replan
    CP.Gather.ResetClusters()
    CP.db.otherZones, CP.db.route = was[1], was[2]
    T.ok(ok, err)
end)
