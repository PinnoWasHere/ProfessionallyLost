-- A spot the game maps to no zone with data: the outer area of Gnomeregan, where the best
-- map is the continent (or a map with no zone above it), and instances with no data of
-- their own. Everything keyed off the player's zone falls to the zone under the spot, or
-- the zone the instance's entrance stands in. The gathering panel's header has two lines:
-- the zone used, then a dim note with the real place and the route's state.
-- Also Eastern Kingdoms end to end: Elwynn, Dun Morogh and Loch Modan lists, and Farm's
-- continent pass there for both factions (Follow the guide with other zones on; Farm solves
-- none).

local CP = ProfLost
local G, GL, RM = CP.Gather, CP.GatherList, CP.RouteMap
local SKIN, MINE, HERB, FISH = 393, 186, 182, 356
local LW, BS, ALCH = 165, 164, 171
local LIGHT, COPPER, PEACEBLOOM, SILVERLEAF = 2318, 2770, 2447, 765
local EK, DUN_MOROGH, ELWYNN, LOCH_MODAN, TIRISFAL = 1415, 1426, 1429, 1432, 1420
local GNOMEREGAN_MAP = 90
local DOOR = { x = 0.244, y = 0.398 }   -- Gnomeregan's entrance on Dun Morogh's map

-- Scene: `spec` goes to MapWorld.begin (Alliance, level 20 by default), with Skinning,
-- Mining, Herbalism and Fishing at `spec.skill` (default 60) and needs for leather, ore
-- and herbs. `spec.mode` and `spec.others` set the route. `act(updates)` runs with every
-- RouteMap.Update zone recorded in `updates`.
local function scene(spec, act)
    spec.side = spec.side or "Alliance"
    spec.level = spec.level or 20
    spec.shareSolves = true
    MapWorld.begin(spec)
    local keys = { "route", "otherZones", "routeMode", "gatherClosed" }
    local was = {}
    for _, k in ipairs(keys) do was[k] = CP.db[k] end
    World.set(CP.db, "route", spec.route ~= false)
    World.set(CP.db, "otherZones", spec.others or false)
    World.set(CP.db, "routeMode", spec.mode)
    World.set(CP.db, "gatherClosed", nil)
    World.set(CP.charDB, "gatherNeeds", {
        [LW] = { [LIGHT] = 200 }, [BS] = { [COPPER] = 100 }, [ALCH] = { [PEACEBLOOM] = 40, [SILVERLEAF] = 40 },
    })
    local skill = spec.skill or 60
    World.set(C_SkillInfo, "GetSkillLineInfoByID", function(id)
        if id == SKIN or id == MINE or id == HERB or id == FISH then
            return { skillID = id, rank = skill, modifier = 0, maxRank = 150 }
        end
        return nil
    end)
    World.patch("C_Item.GetItemCount", function() return 0 end)
    World.set(G, "UpdateAllNeeds", function() end)
    G.ResetClusters()
    local updates = {}
    local update = RM.Update
    World.set(RM, "Update", function(zone, rows, done)
        updates[#updates + 1] = zone or false
        return update(zone, rows, done)
    end)
    World.onEnd(function()
        RM.Update(false, {})
        T.advance(1)
        -- The checklist redraws on the settings it started with, so its lines and scroll
        -- bar do not carry this scene's long farm list into the next test.
        for _, k in ipairs(keys) do CP.db[k] = was[k] end
        GL.Refresh()
    end)
    act(updates)
end

-- The sections the list shows, by profession key.
local function sections()
    local out = {}
    for _, l in ipairs((GL.Drawn())) do
        if l.kind == "section" then out[l.key] = l.text end
    end
    return out
end

local function title() return GL.head.title:GetText() end
local function note() return GL.head.status:GetText() end

-- Every zone a solve was asked for, without the clears.
local function routed(updates)
    local out = {}
    for _, z in ipairs(updates) do if z then out[z] = true end end
    return out
end

-- The panel for a spot with no zone of its own ---------------------------------------

T.test("outside Gnomeregan, with the continent as the best map, the panel lists Dun Morogh", function()
    scene({ zone = DUN_MOROGH, x = DOOR.x, y = DOOR.y, best = EK, realZone = "Gnomeregan" }, function(updates)
        T.eq(G.PlayerZone(), DUN_MOROGH, "the zone under the spot")
        T.ok(GL.Refresh(), "the list has rows")
        local zone, place = G.PlayerSpot()
        T.eq(zone, DUN_MOROGH)
        T.eq(place, "Gnomeregan", "and where the player really is")
        local s = sections()
        T.ok(s[SKIN] and s[MINE] and s[HERB], "Skinning, Mining and Herbalism sections")
        T.ok(s[FISH] ~= nil, "and Fishing")
        T.eq(title(), "Dun Morogh", "line 1: the zone used")
        T.ok(note():find("^in Gnomeregan · ") ~= nil, "line 2: the real place first: " .. note())
        T.ok(routed(updates)[DUN_MOROGH], "the route solves for Dun Morogh")
        T.ok(GL.head.route:IsShown() and GL.head.filter:IsShown(), "route and filter icons")
    end)
end)

T.test("a best map with no zone above it falls to the zone under the spot", function()
    local maps = { [990001] = { "Gnomeregan", EK, 5 } }
    scene({ zone = DUN_MOROGH, x = DOOR.x, y = DOOR.y, best = 990001, maps = maps, realZone = "Gnomeregan" },
        function()
            T.eq(G.PlayerZone(), DUN_MOROGH)
            T.ok(GL.Refresh())
            T.eq(title(), "Dun Morogh")
            T.ok(note():find("^in Gnomeregan") ~= nil, note())
        end)
end)

T.test("no best map at all: the player's world spot still finds Dun Morogh", function()
    scene({ zone = DUN_MOROGH, x = DOOR.x, y = DOOR.y, best = false, realZone = "Gnomeregan" }, function()
        T.eq(G.PlayerZone(), DUN_MOROGH)
        local continent = CP.Waypoint.PlayerWorld()
        T.eq(continent, 0, "UnitPosition gives the spot")
        T.ok(GL.Refresh())
        T.eq(title(), "Dun Morogh")
    end)
end)

T.test("the best map's own zone keeps its plain header, the subzone in the note", function()
    scene({ zone = DUN_MOROGH, x = 0.5, y = 0.5, subZone = "Kharanos" }, function()
        local zone, place = G.PlayerSpot()
        T.eq(zone, DUN_MOROGH)
        T.eq(place, "Kharanos")
        GL.Refresh()
        T.eq(title(), "Dun Morogh")
        T.ok(note():find("^in Kharanos · ") ~= nil, note())
    end)
end)

-- Instances ---------------------------------------------------------------------------

T.test("inside Gnomeregan (no data of its own) the panel lists Dun Morogh, routes on its map", function()
    scene({ zone = DUN_MOROGH, instance = GNOMEREGAN_MAP, instanceName = "Gnomeregan" }, function(updates)
        local zone, place = G.PlayerSpot()
        T.eq(zone, DUN_MOROGH, "the entrance's zone")
        T.eq(place, "Gnomeregan")
        T.ok(not G.IsInstance(zone))
        T.ok(GL.Refresh(), "the list has rows")
        T.ok(sections()[SKIN] ~= nil, "Dun Morogh's leather")
        T.eq(title(), "Dun Morogh")
        T.ok(note():find("^in Gnomeregan · ") ~= nil, note())
        T.ok(routed(updates)[DUN_MOROGH], "the route is Dun Morogh's, on the outside map")
        local pinned = false
        for _, l in ipairs((GL.Drawn())) do if l.pin then pinned = true end end
        T.ok(pinned, "waypoints point at the outside map")
    end)
end)

T.test("an instance with no table entry lists the last outdoor zone", function()
    scene({ zone = LOCH_MODAN }, function()
        T.eq(G.PlayerZone(), LOCH_MODAN)
        MapWorld.state.instance, MapWorld.state.instanceName = 9999, "Somewhere Deep"
        local zone, place = G.PlayerSpot()
        T.eq(zone, LOCH_MODAN)
        T.eq(place, "Somewhere Deep")
    end)
end)

T.test("an instance with data of its own keeps its own list, the note says there's no route", function()
    scene({ zone = 1413, side = "Horde", instance = 47, instanceName = "Razorfen Kraul", skill = 150 }, function()
        local zone, place = G.PlayerSpot()
        T.eq(zone, G.INSTANCE + 47)
        T.eq(place, nil)
        GL.Refresh()
        T.eq(title(), "Razorfen Kraul")
        T.eq(note(), GL.ROUTE_NOTES.inside)
    end)
end)

-- The header ----------------------------------------------------------------------------

T.test("the header is two lines at a fixed height, with or without a place", function()
    local function firstRowTop()
        local _, rows = GL.Drawn()
        local _, _, _, _, y = rows[1]:GetPoint(1)
        return y
    end
    local plain, placed = {}, {}
    scene({ zone = ELWYNN, x = 0.42, y = 0.65 }, function()
        GL.Refresh()
        T.eq(G.PlayerSpot(), ELWYNN)
        T.ok(note() ~= nil and note() ~= "", "line 2 always shows: " .. tostring(note()))
        T.ok(not note():find("^in "), "no place when the player is where the zone says")
        plain = { GL.HeadHeight(), GL.NeedHeight() - #(GL.Drawn()) * 20, firstRowTop() }
    end)
    scene({ zone = ELWYNN, x = 0.42, y = 0.65, subZone = "Goldshire" }, function()
        GL.Refresh()
        T.ok(note():find("^in Goldshire · ") ~= nil, note())
        placed = { GL.HeadHeight(), GL.NeedHeight() - #(GL.Drawn()) * 20, firstRowTop() }
    end)
    T.eq(placed, plain, "the same height, the rows start at the same spot")
    T.eq(plain[1], CP.Style.HEADER.height - GL.headInset.up, "the two lines and their padding, from the list's top")
end)

T.test("line 2 names the route's state: off, solving, its spots, nothing to route", function()
    scene({ zone = ELWYNN, x = 0.42, y = 0.65, subZone = "Goldshire" }, function()
        GL.Refresh()
        T.ok(note():find("Finding a route", 1, true) or note():find("grind spot", 1, true), note())
        T.advance(30)
        T.ok(RM.Status() ~= nil, "solved")
        T.eq(note(), "in Goldshire · " .. RM.Status())
        CP.db.route = false
        GL.Refresh()
        T.eq(note(), "in Goldshire · Route is off")
        CP.db.route = true
        RM.Forget()
        GL.Refresh()
        T.eq(note(), "in Goldshire · Finding a route", "rows to route, the solve running")
        RM.Update(false, {})
        GL.FitNote()
        T.eq(note(), "in Goldshire · No route here", "nothing to route")
    end)
end)

T.test("a narrow header drops the loop length, then the route, then the place, never cutting text short", function()
    scene({ zone = ELWYNN, x = 0.42, y = 0.65, subZone = "Goldshire" }, function()
        GL.Refresh()
        T.advance(30)
        local status = RM.Status()
        T.ok(status and status:find(" · ") ~= nil, "a loop and its spots: " .. tostring(status))
        local texts = GL.NoteTexts()
        T.eq(texts[1], "in Goldshire · " .. status)
        T.ok(texts[2]:find("^in Goldshire · %d+ grind spot") ~= nil, texts[2])
        T.eq(texts[3], "in Goldshire", "then the place alone")
        T.ok(texts[#texts]:find("^%d+ grind spot") ~= nil, texts[#texts])
        -- Each fallback alone fits the room left of the icons, so each is taken in turn.
        local insets = GL.headInset
        local room = GL.width - insets.left - insets.right - GL.headRoom - GL.HEAD_ICONS
        for i, text in ipairs(texts) do
            World.set(GL, "Measure", function(t) return t == text and room or room + 1 end)
            GL.FitNote()
            T.eq(note(), text, "fallback " .. i)
        end
    end)
end)

-- The guide window never depends on the zone -----------------------------------------------

for _, case in ipairs({
    { "outside Gnomeregan", { zone = DUN_MOROGH, x = DOOR.x, y = DOOR.y, best = EK, realZone = "Gnomeregan" } },
    { "with no map at all", { zone = DUN_MOROGH, x = DOOR.x, y = DOOR.y, best = false } },
    { "inside Gnomeregan", { zone = DUN_MOROGH, instance = GNOMEREGAN_MAP, instanceName = "Gnomeregan" } },
    { "inside an unknown instance", { zone = DUN_MOROGH, instance = 9999 } },
}) do
    T.test("the guide window shows its steps " .. case[1], function()
        case[2].side, case[2].level = "Alliance", 20
        MapWorld.begin(case[2])
        CraftWorld.begin({ professions = { [LW] = 100, [SKIN] = 100 } })
        MapWorld.SettleGuides({ SKIN })
        World.set(CP.db, "hideInCombat", false)
        World.set(CP.db, "windowClosed", nil)
        World.onEnd(function()
            CP.Window.opened = false
            CP.Window.Update()
        end)
        World.set(CP.charDB, "guideMode", "one")
        for _, prof in ipairs({ LW, SKIN }) do
            CP.Window.Pick(prof)
            CP.Panel.tabs.guide.button:GetScript("OnClick")()
            local ui = CP.GuideTab.ui
            T.ok(#ui.rows > 0, prof .. ": steps listed")
            T.ok(not ui.empty:IsShown(), prof .. ": no empty text")
        end
    end)
end

-- Eastern Kingdoms end to end ---------------------------------------------------------------

for _, case in ipairs({
    { "Elwynn Forest", ELWYNN, 10, 30 },
    { "Dun Morogh", DUN_MOROGH, 10, 30 },
    { "Loch Modan", LOCH_MODAN, 18, 70 },
}) do
    T.test(case[1] .. " lists leather, ore, herbs and fishing, and solves a route", function()
        scene({ zone = case[2], level = case[3], skill = case[4] }, function(updates)
            T.eq(G.PlayerZone(), case[2])
            T.ok(GL.Refresh(), "rows")
            local s = sections()
            for _, prof in ipairs({ SKIN, MINE, HERB, FISH }) do
                T.ok(s[prof] ~= nil, ("%s: section %d"):format(case[1], prof))
            end
            T.eq(title(), case[1])
            T.ok(routed(updates)[case[2]], "a route for the zone")
            T.advance(30)
            T.ok(RM.Status() ~= nil, "solved: " .. tostring(RM.Status()))
            local plan = CP.Fishing.Plan({ skill = case[4], maxRank = 150, level = case[3], zone = case[2],
                side = "Alliance", cook = false, needs = {}, have = function() return 0 end })
            T.ok(plan ~= nil, "a fishing plan")
        end)
    end)
end

-- Farm across Eastern Kingdoms, both factions ---------------------------------------------------

local function solveAll()
    GL.RouteOnly()
    T.advance(5)
    for _ = 1, 80 do
        if not RM.ZonesReport()[1]:find("running", 1, true) then break end
        T.advance(1)
    end
end

for _, case in ipairs({ { "Alliance", ELWYNN, "Horde" }, { "Horde", TIRISFAL, "Alliance" } }) do
    local side, home = case[1], case[2]
    T.test(side .. " farming in Eastern Kingdoms: no other zone, no enemy home", function()
        scene({ zone = home, side = side, level = 30, skill = 200, mode = "farm", others = false },
            function()
                solveAll()
                T.eq(#RM.Others(), 0, "Farm solves no other zone")

                -- What names a zone to go to skips the enemy's home zones.
                local skills = G.Skills()
                for _, item in ipairs({ LIGHT, COPPER, PEACEBLOOM }) do
                    local best = CP.Farm.Best(item, { level = 30, side = side, skills = skills, continent = 0 })
                    T.ok(best ~= nil, side .. ": a best zone for " .. item)
                    T.ok(best and not G.EnemyHome(best.zone, side), side .. ": Farm.Best avoids enemy homes")
                end
                for _, c in ipairs(CP.Fishing.Candidates(100, 30, side)) do
                    T.ok(not G.EnemyHome(c.zone, side), side .. ": fishing sends to " .. c.zone)
                end
                GL.Refresh()
                for _, mat in ipairs(GL.FarmLeathers(home, G.Skills())) do
                    for _, z in ipairs(mat.zones) do
                        T.eq(z, home, side .. ": the farm filter names only this zone")
                    end
                end
            end)
    end)
end

T.test("Follow the guide's continent pass runs from outside Gnomeregan too", function()
    scene({ zone = DUN_MOROGH, x = DOOR.x, y = DOOR.y, best = EK, realZone = "Gnomeregan", level = 30, skill = 200,
            others = true }, function()
        solveAll()
        local count = 0
        for _, zone in ipairs(RM.Others()) do
            count = count + 1
            T.eq(CP.GatherData.zones[zone].map, 0, "an Eastern Kingdoms zone: " .. zone)
        end
        T.ok(count > 0, "other Eastern Kingdoms zones are solved")
    end)
end)
