-- The cost of the gathering panel's rebuild outside Gnomeregan, where the game gives no
-- best map. The list there has rows, so Next up asks every gathering guide where to go,
-- and each guide places its profession's spawns in every zone it knows. That build asks
-- the map about every spawn on every continent, so it runs as a background job, a slice
-- a frame. A rebuild inside an event handler stays within GatherGuide.WARM's bounds.
-- mapworld counts C_Map calls here, with its shared MapPosZone answers off.

local CP = ProfLost
local G, GG, GL, W = CP.Gather, CP.GatherGuide, CP.GatherList, CP.Waypoint
local SKIN, MINE, HERB, FISH = 393, 186, 182, 356
local DUN_MOROGH, ELWYNN = 1426, 1429
local DOOR = { x = 0.244, y = 0.398 }   -- Gnomeregan's entrance on Dun Morogh's map

-- C_Map calls one handler may make: the player's own zone and its neighbours' spots.
local EVENT_BOUND = 5000

-- Counts Waypoint calls by name, beside mapworld's C_Map counts.
local function countWaypoint(counts)
    for _, name in ipairs({ "MapPosZone", "PlayerSpot", "PlayerZone" }) do
        local fn = W[name]
        World.set(W, name, function(...)
            counts[name] = (counts[name] or 0) + 1
            return fn(...)
        end)
    end
end

-- Outside Gnomeregan with no best map by default; `spec` replaces it.
local GNOMEREGAN = { zone = DUN_MOROGH, x = DOOR.x, y = DOOR.y, best = false, realZone = "Gnomeregan",
                     subZone = "Launch Bay" }

local function scene(act, spec)
    spec = spec or GNOMEREGAN
    MapWorld.begin({ zone = spec.zone, x = spec.x, y = spec.y, best = spec.best, side = "Alliance", level = 20,
                     realZone = spec.realZone, subZone = spec.subZone, count = true })
    World.set(CP.db, "route", true)
    World.set(CP.db, "otherZones", false)
    World.set(CP.charDB, "gatherNeeds", { [165] = { [2318] = 200 }, [164] = { [2770] = 100 } })
    World.set(C_SkillInfo, "GetSkillLineInfoByID", function(id)
        if id == SKIN or id == MINE or id == HERB or id == FISH then
            return { skillID = id, rank = 60, modifier = 0, maxRank = 150 }
        end
        return nil
    end)
    World.patch("C_Item.GetItemCount", function() return 0 end)
    World.set(G, "UpdateAllNeeds", function() end)
    G.ResetClusters()
    GG.Forget()
    World.onEnd(function()
        GG.Forget()
        CP.RouteMap.Update(false, {})
        T.advance(1)
    end)
    local counts = {}
    countWaypoint(counts)
    act(counts)
end

local function report(label, counts)
    print(("  %s: C_Map %d (%s), MapPosZone %d, PlayerSpot %d"):format(label, MapWorld.CallCount(),
        (function()
            local parts = {}
            for name, n in pairs(MapWorld.calls) do parts[#parts + 1] = name .. " " .. n end
            table.sort(parts)
            return table.concat(parts, ", ")
        end)(), counts.MapPosZone or 0, counts.PlayerSpot or 0))
end

T.test("outside Gnomeregan with no best map, one panel rebuild stays within its bound", function()
    scene(function(counts)
        T.eq(C_Map.GetBestMapForUnit("player"), nil, "no best map, as the game gives there")
        MapWorld.calls = {}
        T.fire("ZONE_CHANGED_NEW_AREA")
        T.ok(GL.Refresh(), "the list has rows")
        report("rebuild", counts)
        T.ok(MapWorld.CallCount() <= EVENT_BOUND,
            ("C_Map calls in one rebuild: %d, bound %d"):format(MapWorld.CallCount(), EVENT_BOUND))
        T.ok((counts.PlayerSpot or 0) <= 20, "the player's spot is asked a few times, not per spawn: "
            .. tostring(counts.PlayerSpot))
    end)
end)

T.test("Next up names the guides' zones once the background job is done, a slice a frame", function()
    scene(function(counts)
        GL.nextOpen = true
        World.onEnd(function() GL.nextOpen = false end)
        T.advance(0)   -- the scene's own pending redraws, before the job's first slice
        local before = CP.Launcher.GatherLines()
        T.eq(#before, 4, "four gathering skills")
        for _, g in ipairs(before) do
            if g.name == "Fishing" then
                T.ok(g.right ~= GG.WARM.waiting, "Fishing needs no zones built")
            else
                T.eq(g.right, GG.WARM.waiting, g.left .. " waits for the job")
            end
        end
        T.ok(GG.Warming(), "the job runs")

        -- A frame holds one slice of the job and whatever timers fall due beside it.
        local frames, worst = 0, 0
        while GG.Warming() and frames < 100000 do
            MapWorld.calls = {}
            T.advance(0.02, 0.02)
            frames = frames + 1
            worst = math.max(worst, MapWorld.CallCount())
        end
        local stats = GG.lastWarm
        print(("  job: %d frames, %d steps, at most %d steps a frame; worst frame %d C_Map calls; MapPosZone %d in all")
            :format(stats.frames, stats.steps, stats.most, worst, counts.MapPosZone or 0))
        T.ok(not GG.Warming(), "the job finishes")
        T.ok(stats.frames > 1, "the job runs over several frames")
        T.ok(stats.most <= GG.WARM.points, ("at most WARM.points steps a frame: %d"):format(stats.most))
        T.ok(worst <= EVENT_BOUND, ("worst frame %d C_Map calls"):format(worst))
        local after = CP.Launcher.GatherLines()
        for _, g in ipairs(after) do
            T.ok(g.right ~= GG.WARM.waiting, g.left .. " has its step: " .. g.right)
        end
        local rows = GG.PlayerRows(MINE, 60, 150)
        local nextUp = GG.Next(rows, 60, 150)
        -- The player's own zone reads "gather", any other its name.
        local here = nextUp.zone == CP.Gather.PlayerZone()
        T.eq(after[2].right, here and "gather" or C_Map.GetMapInfo(nextUp.zone).name, "Mining names its guide's zone")
        MapWorld.calls = {}
        for k in pairs(counts) do counts[k] = nil end
        T.ok(GL.Refresh())
        report("warm rebuild", counts)
        T.ok(MapWorld.CallCount() <= EVENT_BOUND)
    end)
end)

T.test("in Elwynn with a best map, one panel rebuild stays within the same bound", function()
    scene(function(counts)
        T.eq(C_Map.GetBestMapForUnit("player"), ELWYNN)
        MapWorld.calls = {}
        T.fire("ZONE_CHANGED_NEW_AREA")
        T.ok(GL.Refresh(), "the list has rows")
        report("Elwynn rebuild", counts)
        T.ok(MapWorld.CallCount() <= EVENT_BOUND,
            ("C_Map calls in one rebuild: %d, bound %d"):format(MapWorld.CallCount(), EVENT_BOUND))
    end, { zone = ELWYNN, x = 0.42, y = 0.65 })
end)
