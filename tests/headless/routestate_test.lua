-- The gathering header's route state always ends. "Finding a route" shows only while the
-- player's zone is being solved; every solve ends in the loop or "No route here", in a
-- city with nothing to route (Orgrimmar), an open zone (Durotar) and outside Gnomeregan,
-- in Farm and Follow the guide, and when the solve fails.

local CP = ProfLost
local G, GL, RM, GG = CP.Gather, CP.GatherList, CP.RouteMap, CP.GatherGuide
local SKIN, FISH, LW = 393, 356, 165
local LIGHT = 2318
local ORGRIMMAR, DUROTAR, DUN_MOROGH, EK = 1454, 1411, 1426, 1415

local FRAME = 0.016       -- one harness frame
local MAX_FRAMES = 300    -- a solve this long is stuck, not slow

local SOLVING = GL.ROUTE_NOTES.solving
local NONE = GL.ROUTE_NOTES.none

-- Scene: `spec` goes to MapWorld.begin, with Skinning, Fishing and Leatherworking at 60,
-- leather needed, the route on and `mode` its mode.
local function scene(spec, mode, act)
    MapWorld.begin(spec)
    World.set(CP.db, "route", true)
    World.set(CP.db, "otherZones", false)
    World.set(CP.db, "routeMode", mode)
    World.set(CP.charDB, "gatherNeeds", { [LW] = { [LIGHT] = 200 } })
    World.set(C_SkillInfo, "GetSkillLineInfoByID", function(id)
        if id == SKIN or id == FISH or id == LW then
            return { skillID = id, rank = 60, modifier = 0, maxRank = 150 }
        end
        return nil
    end)
    World.patch("C_Item.GetItemCount", function() return 0 end)
    World.set(G, "UpdateAllNeeds", function() end)
    G.ResetClusters()
    local update = RM.Update
    World.onEnd(function()
        update(false, {})
        T.advance(1)
    end)
    act()
end

local function note() return GL.head.status:GetText() or "" end

-- Builds the panel once, then no more rebuilds or solves: only the solve's own end may
-- redraw the note, as when nothing else changes in game.
local function refresh()
    GL.Refresh()
    local none = function() end
    World.set(RM, "Update", none)
    World.set(GL, "Refresh", none)
    World.set(GL, "Changed", none)
end

-- Frames until the note leaves "Finding a route", or nil past MAX_FRAMES.
local function settle()
    for frame = 0, MAX_FRAMES do
        if not note():find(SOLVING, 1, true) then return frame end
        T.advance(FRAME)
    end
    return nil
end

-- The note's route part is final: the drawn loop's status, or "No route here".
local function final(place)
    local status = RM.Status()
    local want = status and ("in %s · %s"):format(place, status) or ("in %s · %s"):format(place, NONE)
    T.ok(not RM.Solving(), "no solve running")
    T.eq(note(), want)
    return status
end

-- Runs until the guides' zones and every route job are done, then checks the note again.
local function stays(place)
    for _ = 1, MAX_FRAMES do
        if not (GG.Warming() or RM.Solving()) then break end
        T.advance(FRAME)
    end
    T.advance(1)
    return final(place)
end

local MODES = { { "farm", "Farm" }, { "level", "Follow the guide" } }

for _, m in ipairs(MODES) do
    local mode, label = m[1], m[2]

    T.test("Orgrimmar, " .. label .. ": the note ends at No route here", function()
        scene({ zone = ORGRIMMAR, x = 0.7, y = 0.3, side = "Horde", level = 20, subZone = "Valley of Honor" }, mode,
            function()
                refresh()
                -- Follow the guide routes the city's fishing rows; Farm routes no checklist row.
                if mode == "level" then T.ok(#GL.RouteRows(ORGRIMMAR, nil, true) > 0, "Orgrimmar has rows to route") end
                local frames = settle()
                T.ok(frames ~= nil, "still '" .. note() .. "' after " .. MAX_FRAMES .. " frames")
                T.eq(final("Valley of Honor"), nil, "nothing to draw in the city")
                T.eq(note(), "in Valley of Honor · " .. NONE)
                stays("Valley of Honor")
            end)
    end)

    T.test("Durotar, " .. label .. ": the note ends at the loop", function()
        scene({ zone = DUROTAR, x = 0.52, y = 0.44, side = "Horde", level = 20, subZone = "Razor Hill" }, mode,
            function()
                refresh()
                local frames = settle()
                T.ok(frames ~= nil, "still '" .. note() .. "' after " .. MAX_FRAMES .. " frames")
                T.ok(final("Razor Hill") ~= nil, "Durotar draws a route: " .. note())
                stays("Razor Hill")
            end)
    end)

    T.test("outside Gnomeregan, " .. label .. ": the note ends", function()
        scene({ zone = DUN_MOROGH, x = 0.244, y = 0.398, best = EK, realZone = "Gnomeregan", side = "Alliance",
            level = 20 }, mode, function()
            refresh()
            local frames = settle()
            T.ok(frames ~= nil, "still '" .. note() .. "' after " .. MAX_FRAMES .. " frames")
            final("Gnomeregan")
            stays("Gnomeregan")
        end)
    end)
end

T.test("a solve that fails ends at No route here", function()
    scene({ zone = DUROTAR, x = 0.52, y = 0.44, side = "Horde", level = 20, subZone = "Razor Hill" }, "level",
        function()
            World.set(CP.Route, "GrindSpots", function() error("boom") end)
            refresh()
            T.eq(note(), "in Razor Hill · " .. SOLVING, "the solve starts")
            local frames = settle()
            T.ok(frames ~= nil, "still '" .. note() .. "' after " .. MAX_FRAMES .. " frames")
            T.eq(note(), "in Razor Hill · " .. NONE)
            T.ok(not RM.Solving())
        end)
end)

T.test("Finding a route shows only while the solve runs", function()
    scene({ zone = DUROTAR, x = 0.52, y = 0.44, side = "Horde", level = 20, subZone = "Razor Hill" }, "level",
        function()
            RM.Forget()
            refresh()
            T.ok(RM.Solving(), "a solve started")
            T.eq(note(), "in Razor Hill · " .. SOLVING)
            T.ok(settle() ~= nil)
            T.ok(not RM.Solving())
            T.ok(not note():find(SOLVING, 1, true), note())
        end)
end)
