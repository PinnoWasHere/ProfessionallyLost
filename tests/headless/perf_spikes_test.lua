-- Work in one frame (PERF-01): after a GatherMate2 import the gathering guide rebuilds
-- over frames, a route redraw registers its pins over frames and reads the skills once,
-- and the Disenchant button is laid out only when it moves. Each test counts work per
-- frame, one T.advance(FRAME, FRAME) being one frame.

local CP = ProfLost
local GG, G, GM, RM = CP.GatherGuide, CP.Gather, CP.GatherMate, CP.RouteMap
local FRAME = 0.05
local SLICE = 0.002   -- above GG.WARM.gap, so the warm job runs one slice per step
local HERB, MINE, SKIN = 182, 186, 393
local DUROTAR = 1411

-- Item 42 ---------------------------------------------------------------------------

T.test("item 42: after a GatherMate2 import the guide's zones build over frames", function()
    MapWorld.begin({ zone = DUROTAR, x = 0.5, y = 0.5, level = 20, side = "Horde" })
    World.set(C_SkillInfo, "GetSkillLineInfoByID", function(id)
        if id == HERB then return { skillID = id, rank = 60, modifier = 0, maxRank = 150 } end
        return nil
    end)
    World.set(G, "UpdateAllNeeds", function() end)
    local asked = 0
    World.set(CP.Waypoint, "MapPosZone", function(z) asked = asked + 1; return z end)
    GG.Forget()
    World.onEnd(function()
        GG.Forget()
        CP.GuideTab.Forget()
        GM.Reset()
        T.advance(1)
    end)

    -- Warm first, as a login does.
    local frames = 0
    repeat
        GG.Warm(HERB)
        T.advance(SLICE, SLICE)
        frames = frames + 1
    until GG.Ready(HERB) and not GG.Warming() or frames > 5000
    T.ok(GG.Ready(HERB), "the herbalism guide is built")

    -- An import: a pack of herb nodes the map never saw, in every zone with herb data.
    local pack, count = {}, 0
    for zone, z in pairs(CP.GatherData.zones) do
        if zone < G.INSTANCE and z.nodes then
            for entry in pairs(z.nodes) do
                local n = CP.GatherData.nodes[entry]
                if n and n[4] == G.HERBALISM then
                    pack[zone] = pack[zone] or {}
                    for i = 1, 40 do
                        pack[zone][(1000 + zone % 1000 * 7 + i * 37) * 1000000 + (2000 + i * 53) * 100] = entry
                        count = count + 1
                    end
                    break
                end
            end
        end
    end
    T.ok(count > GG.WARM.points * 2, "a big import: " .. count .. " nodes")
    local names = {}
    for entry, n in pairs(CP.GatherData.nodes) do names[entry] = n[1] end
    World.set(GM, "Addon", function()
        return {
            GetNodesForZone = function(_, zone, kind)
                return pairs(kind == "Herb Gathering" and pack[zone] or {})
            end,
            GetNameForNode = function(_, _, id) return names[id] end,
        }
    end)
    GM.Reset()

    -- What the Guide tab does each draw: rows when ready, otherwise ask the job to warm.
    -- `caller` counts what the Guide tab's own draw asks the map; the job's slices run
    -- inside T.advance.
    local caller, job, ready = 0, 0, nil
    for frame = 1, 400 do
        asked = 0
        if GG.Ready(HERB) then
            GG.PlayerRows(HERB, 60, 150)
            ready = ready or frame
        else
            GG.Warm(HERB)
        end
        caller = math.max(caller, asked)
        asked = 0
        T.advance(SLICE, SLICE)
        job = job + asked
        if ready and not GG.Warming() and frame > ready + 2 then break end
    end
    print(("PERF-01 item 42: map lookups in the Guide tab's own draw, most in one frame %d; in the warm job %d; cap %d")
        :format(caller, job, GG.WARM.points))
    T.ok(caller <= GG.WARM.points, "the draw asks the map no more than the job's cap: " .. caller)
    T.ok(job > GG.WARM.points, "the warm job rebuilds the imported nodes: " .. job)
end)

-- Item 43 ---------------------------------------------------------------------------

-- Scene as otherzones_test: Durotar, level 20 Horde, needs from two guides, Mining and
-- Herbalism at 120, other zones on. Counts pin registrations and Gather.Skills calls.
local function routeScene(act)
    MapWorld.begin({ zone = DUROTAR, x = 0.5, y = 0.5, level = 20, side = "Horde", shareSolves = true })
    local was = { CP.db.otherZones, CP.db.route }
    CP.db.route = true
    CP.db.otherZones = true
    CP.charDB.gatherNeeds = { [165] = { [2318] = 200 }, [164] = { [2771] = 100, [2772] = 100 }, [171] = { [2447] = 100 } }
    local rank = 120
    World.set(C_SkillInfo, "GetSkillLineInfoByID", function(id)
        if id == SKIN or id == MINE or id == HERB then return { skillID = id, rank = rank, modifier = 0 } end
        return nil
    end)
    World.patch("C_Item.GetItemCount", function() return 0 end)
    local mapPos, replan = CP.Waypoint.MapPosZone, G.UpdateAllNeeds
    G.UpdateAllNeeds = function() end
    CP.Waypoint.MapPosZone = function(z) return z end
    G.ResetClusters()
    local pins = LibStub("HereBeDragons-Pins-2.0")
    local c = { world = 0, mini = 0, skills = 0 }
    local addW, addM, skills = pins.AddWorldMapIconMap, pins.AddMinimapIconMap, G.Skills
    c.live = {}
    local clear = pins.RemoveAllWorldMapIcons
    pins.AddWorldMapIconMap = function(self, ref, icon, zone, x, y, ...)
        c.world = c.world + 1
        c.live[icon] = ("%s %.4f %.4f"):format(zone, x, y)
        return addW(self, ref, icon, zone, x, y, ...)
    end
    pins.RemoveAllWorldMapIcons = function(self, ...) c.live = {}; return clear(self, ...) end
    pins.AddMinimapIconMap = function(self, ...) c.mini = c.mini + 1; return addM(self, ...) end
    G.Skills = function(...) c.skills = c.skills + 1; return skills(...) end
    function c.reset() c.world, c.mini, c.skills = 0, 0, 0 end
    function c.raise() rank = rank + 1 end
    local ok, err = pcall(act, c)
    CP.db.otherZones, CP.db.route = false, false
    RM.Update(false, {})
    T.advance(1)
    pins.AddWorldMapIconMap, pins.AddMinimapIconMap, G.Skills = addW, addM, skills
    pins.RemoveAllWorldMapIcons = clear
    CP.Waypoint.MapPosZone, G.UpdateAllNeeds = mapPos, replan
    G.ResetClusters()
    CP.db.otherZones, CP.db.route = was[1], was[2]
    T.ok(ok, err)
end

T.test("item 43: a route redraw registers its pins over frames and reads the skills once", function()
    routeScene(function(c)
        CP.GatherList.RouteOnly()
        T.advance(5)
        T.ok(#RM.Others() >= 5, "other zones are solved: " .. #RM.Others())
        -- A small frame budget, so the redraw spreads over several frames.
        World.set(RM, "DRAW_PINS", 50)

        -- A skill-up changes the rings' colours: one redraw of everything.
        c.reset()
        c.raise()
        CP.GatherList.RouteOnly()
        local mostWorld, mostMini, mostSkills, totalWorld = c.world, c.mini, c.skills, c.world
        local first = c.world
        c.reset()
        for _ = 1, 200 do
            T.advance(FRAME, FRAME)
            mostWorld, mostMini, mostSkills = math.max(mostWorld, c.world), math.max(mostMini, c.mini),
                math.max(mostSkills, c.skills)
            totalWorld = totalWorld + c.world
            c.reset()
        end
        print(("PERF-01 item 43: redraw world pins %d in all (%d in the first frame), the most in one frame %d; skills calls %d")
            :format(totalWorld, first, mostWorld, mostSkills))
        T.ok(totalWorld > 500, "the redraw is big: " .. totalWorld)
        -- A zone is never split, and a frame may hold the player's zone, a batch inline and a batch from the runner.
        T.ok(mostWorld <= (RM.DRAW_PINS or 400) * 3, "no frame registers more than a batch of world pins: " .. mostWorld)
        T.ok(mostWorld < totalWorld / 4, "the redraw is spread over frames: " .. mostWorld .. " of " .. totalWorld)
        -- The solve itself reads the skills a few times a frame; one read per pin is thousands.
        T.ok(mostSkills <= 100, "the skills are read once per redraw: " .. mostSkills)
    end)
end)

T.test("item 43: a redraw draws the same pins as before, only later", function()
    routeScene(function(c)
        CP.GatherList.RouteOnly()
        T.advance(5)
        local function spots()
            local list = {}
            for _, where in pairs(c.live) do list[#list + 1] = where end
            table.sort(list)
            return table.concat(list, "|"), #list
        end
        local before, n = spots()
        T.ok(n > 500, "pins registered: " .. n)
        c.raise()
        CP.GatherList.RouteOnly()
        T.advance(5)
        local after, m = spots()
        T.eq(m, n, "as many pins after the redraw")
        T.ok(after == before, "at the same places")
    end)
end)

-- Item 44 ---------------------------------------------------------------------------

T.test("item 44: the Disenchant button is laid out when it moves, not every frame", function()
    CraftWorld.begin({ professions = { [333] = { rank = 50, max = 75 } },
                       bags = { [1] = { itemID = 4307, count = 1 } } })
    World.set(CP.db, "collect", true)
    CraftWorld.Open(333)
    T.advance(1)
    local tab = CP.Panel.tabs.disenchant
    tab.button:GetScript("OnClick")(tab.button)
    T.advance(1)
    local DT = CP.DisenchantTab
    local b = _G.ProfLost_DisenchantButton
    T.ok(b ~= nil, "the secure button exists")
    -- The harness has no layout engine. The slot is the 28-high child of the tab content
    -- that the tab keeps to itself, so the Frame class gives geometry to that frame only.
    local geo = { left = 100, top = 500, w = 200 }
    local class = getmetatable(tab.content).__index
    local function isSlot(f) return f:GetParent() == tab.content and f:GetHeight() == 28 end
    local function place(name, value)
        local orig = class[name]
        World.set(class, name, function(self, ...)
            if isSlot(self) then return value() end
            return orig(self, ...)
        end)
    end
    place("GetLeft", function() return geo.left end)
    place("GetTop", function() return geo.top end)
    place("GetWidth", function() return geo.w end)
    place("IsVisible", function() return true end)

    local c = { SetFrameStrata = 0, SetFrameLevel = 0, ClearAllPoints = 0, SetPoint = 0, SetSize = 0, Show = 0 }
    for name in pairs(c) do
        local orig = b[name]
        World.set(b, name, function(...) c[name] = c[name] + 1; return orig(...) end)
    end
    local function total() local n = 0 for _, v in pairs(c) do n = n + v end return n end

    T.advance(FRAME, FRAME)
    local settle = total()
    for _ = 1, 50 do T.advance(FRAME, FRAME) end
    print(("PERF-01 item 44: layout calls in 51 idle frames %d (SetPoint %d, Show %d)"):format(total(), c.SetPoint, c.Show))
    T.ok(settle > 0, "the button was laid out once")
    T.eq(total(), settle, "nothing moved, nothing laid again")

    geo.left = 140
    T.advance(FRAME, FRAME)
    T.ok(c.SetPoint >= 1 and total() > settle, "a move lays it out again")
    local moved = total()
    for _ = 1, 10 do T.advance(FRAME, FRAME) end
    T.eq(total(), moved, "and only once")
end)
