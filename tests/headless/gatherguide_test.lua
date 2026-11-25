-- Gathering guides (Herbalism, Mining, Skinning, Fishing) and their Guide tab rows.

local CP = ProfLost
local GG = CP.GatherGuide
local HERB, MINE, SKIN, FISH = 182, 186, 393, 356
local DUROTAR, ELWYNN, BARRENS, THUNDER_BLUFF, HYJAL = 1411, 1429, 1413, 1456, 2482

local function none() return 0 end

-- No zone map in the harness: every cluster stays in the zone the data puts it in.
local function flatMap()
    local orig = CP.Waypoint.MapPosZone
    CP.Waypoint.MapPosZone = function(zone) return zone end
    CP.Gather.ResetClusters()
    return function()
        CP.Waypoint.MapPosZone = orig
        CP.Gather.ResetClusters()
        -- The reset restarts the zone build. It runs out here, or its frames and signal land
        -- in whichever test advances the clock next.
        MapWorld.SettleGuides()
    end
end

local function rows(line, skill, max, level, side, zone)
    return GG.Rows({ line = line, skill = skill, max = max, level = level, side = side or "Horde",
                     zone = zone or DUROTAR, needs = {}, have = none })
end

local function gatherRows(list)
    local out = {}
    -- The main stretches; "or" rows (side) are alternatives and have their own test.
    for _, r in ipairs(list) do if r.gather and not r.side then out[#out + 1] = r end end
    return out
end

T.test("skill-up chance and colour follow the req +25/+50/+100 bands", function()
    T.eq(GG.Chance(10, 15), 0, "below the need: can't gather")
    T.eq(GG.Chance(15, 15), 1)
    T.eq(GG.Chance(39, 15), 1, "orange to req+24")
    T.eq(GG.Chance(40, 15), 0.75, "yellow from req+25")
    T.eq(GG.Chance(65, 15), 0.25, "green from req+50")
    T.eq(GG.Chance(115, 15), 0, "grey from req+100")
    T.eq(GG.Difficulty(15, 15), 1)
    T.eq(GG.Difficulty(65, 15), 3)
end)

T.test("rank rows come from the data and name each rank", function()
    for _, line in ipairs({ HERB, MINE, SKIN }) do
        local ranks = GG.Ranks(line, 75)
        T.eq(#ranks, 3, "three ranks to learn from Apprentice")
        T.eq(ranks[1].name, "Journeyman")
        T.eq(ranks[1].at, 50)
        T.eq(ranks[1].level, 10)
        T.eq(ranks[3].name, "Artisan")
        T.eq(ranks[3].level, 35)
        T.ok(#ranks[1].npcs >= 10, "trainers for both factions")
        for _, e in ipairs(ranks[1].npcs) do T.ok(CP.GatherData.rankNpcs[e], "trainer has a spawn") end
    end
    T.eq(#GG.Ranks(HERB, 150), 2, "Journeyman already learned")
    T.eq(#GG.Ranks(HERB, 300), 0)
end)

T.test("every gather row runs to 300 without gaps, ranks before the stretch from their learn skill", function()
    local restore = flatMap()
    for _, line in ipairs({ HERB, MINE, SKIN }) do
        local list = rows(line, 1, 75, 5)
        local g = gatherRows(list)
        T.ok(#g >= 4, "several stretches")
        T.eq(g[1].from, 1)
        T.eq(g[#g].to, 300)
        for i = 2, #g do T.eq(g[i].from, g[i - 1].to, "stretches meet") end
        for i, r in ipairs(list) do
            if r.gatherRank then
                local nextGather
                for j = i + 1, #list do if list[j].gather then nextGather = list[j] break end end
                if nextGather then T.ok(nextGather.from >= r.gatherRank.at, "rank before the stretch from its learn skill") end
            end
        end
        T.ok(g[1].current, "the first stretch is current")
        T.ok(not g[2].current)
    end
    restore()
end)

T.test("the first stretch suits a level 5 Horde player in Durotar", function()
    local restore = flatMap()
    for _, line in ipairs({ HERB, MINE, SKIN }) do
        local g = gatherRows(rows(line, 1, 75, 5, "Horde", DUROTAR))
        T.eq(g[1].gather.zone, DUROTAR, "starts at home")
        for _, r in ipairs(g) do
            T.ok(r.gather.zone ~= ELWYNN, "never the Alliance home zones")
            T.ok(r.gather.zone ~= THUNDER_BLUFF, "never a city")
            T.ok(r.gather.zone ~= HYJAL, "never a Forever zone without data nodes")
        end
    end
    local a = gatherRows(rows(HERB, 1, 75, 5, "Alliance", ELWYNN))
    T.eq(a[1].gather.zone, ELWYNN, "an Alliance player starts in Elwynn")
    for _, r in ipairs(a) do T.ok(r.gather.zone ~= DUROTAR, "never the Horde home zones") end
    restore()
end)

T.test("targets follow the skill: herbs and ore by their need, beasts by level", function()
    local restore = flatMap()
    local function at(line, skill)
        for _, r in ipairs(gatherRows(rows(line, 1, 75, 60))) do
            if r.from <= skill and skill < r.to then return GG.TargetNames(r.gather.targets, skill, 3) end
        end
    end
    local function has(list, name)
        for _, n in ipairs(list) do if n == name then return true end end
    end
    T.ok(has(at(MINE, 10), "Copper Vein"))
    T.ok(has(at(MINE, 160), "Iron Deposit"))
    T.ok(has(at(MINE, 180), "Mithril Deposit"))
    T.ok(has(at(HERB, 10), "Peacebloom") or has(at(HERB, 10), "Silverleaf"))
    -- At level 60 Zephras Isle's Mageroyal (yellow at 80) can win this stretch.
    T.ok(has(at(HERB, 80), "Briarthorn") or has(at(HERB, 80), "Mageroyal"))
    for _, r in ipairs(gatherRows(rows(SKIN, 200, 225, 60))) do
        for _, t in ipairs(r.gather.targets) do
            T.ok(GG.Chance(r.from, t.req) > 0 or GG.Chance(r.to - 1, t.req) > 0, "beast skinnable in its stretch")
        end
    end
    restore()
end)

T.test("a skinning stretch at the player's level keeps beasts within reach", function()
    local restore = flatMap()
    local g = gatherRows(rows(SKIN, 100, 150, 20))
    for _, t in ipairs(g[1].gather.targets) do T.ok(t.level <= 22, "beast level " .. t.level) end
    restore()
end)

T.test("expected gathers: one per point while orange", function()
    local t = { { req = 1 } }
    T.eq(GG.GathersTo(1, 25, t), 24)
    T.eq(GG.GathersTo(26, 30, t), 5, "yellow: 4 points at 75%")
    T.eq(GG.GathersTo(200, 210, t), nil, "grey: no skill")
end)

T.test("feeds list only what the crafting guides still need", function()
    local restore = flatMap()
    local g = gatherRows(rows(HERB, 1, 75, 5))[1]
    local feeds = GG.Feeds(g.gather.targets, { [2447] = 20, [765] = 10, [2589] = 99 },
        function(item) return item == 765 and 10 or 3 end)
    local got = {}
    for _, f in ipairs(feeds) do got[f.item] = f end
    T.ok(got[2447] and got[2447].have == 3 and got[2447].need == 20, "Peacebloom short")
    T.eq(got[765], nil, "Silverleaf covered")
    T.eq(got[2589], nil, "Linen Cloth isn't gathered")
    restore()
end)

T.test("the waypoint goes to the densest cluster of a stretch's targets", function()
    local restore = flatMap()
    local g = gatherRows(rows(MINE, 1, 75, 5))[1]
    local spot = GG.Spot(g.gather.zone, g.gather.targets)
    T.ok(spot and spot.x > 0 and spot.x < 1 and spot.y > 0 and spot.y < 1)
    T.eq(spot.name, "Copper Vein")
    restore()
end)

T.test("fishing rows: a stretch per rank, each rank where it becomes learnable", function()
    local list = rows(FISH, 1, 75, 5)
    local kinds, at = {}, {}
    for _, r in ipairs(list) do
        kinds[#kinds + 1] = r.fish and "fish" or r.fishRank.kind
        if r.fishRank then at[r.fishRank.kind] = r.from end
    end
    -- Horde: Katoom the Angler trains Artisan from 200; the Alliance takes Nat Pagle's quest at 225.
    T.eq(table.concat(kinds, ","), "fish,trainer,fish,fish,book,fish,fish,trainer,fish,fish")
    T.eq(at, { trainer = 200, book = 125 }, "the Expert book at 125, the Artisan trainer at 200")
    local alliance, aat = rows(FISH, 1, 75, 5, "Alliance", 1429), {}
    for _, r in ipairs(alliance) do
        if r.fishRank then aat[r.fishRank.skill] = r.fishRank.kind .. " " .. r.from end
    end
    T.eq(aat, { [75] = "trainer 50", [150] = "book 125", [225] = "quest 225" }, "Alliance: Journeyman at 50, the book at 125, the quest at 225")
    T.eq(list[1].from, 1)
    T.eq(list[1].to, 50)
    T.eq(list[1].gathers, CP.Fishing.CatchesTo(1, 50))
    T.ok(list[1].current)
    local mid = rows(FISH, 130, 150, 25)
    T.eq(mid[1].fishRank and mid[1].fishRank.kind, "book", "at 130 of 150 the book is learnable now: first")
    local later = rows(FISH, 160, 225, 30)
    T.eq(later[1].fish and later[1].from, 160)
    T.eq(later[2].fishRank.kind, "trainer", "Expert done: Horde's Artisan trainer is next")
    local capped = rows(FISH, 75, 75, 10)
    T.eq(capped[1].fishRank and capped[1].fishRank.kind, "trainer", "at 75 of 75: Journeyman first")
    T.eq(capped[2].fish and capped[2].from, 75)
    T.ok(capped[2].current)
end)

-- The Guide tab, with a gathering profession window open. The stubs come off when each test ends.

local function stubGathering(id, name, skill, max)
    World.patch("C_TradeSkillUI.GetBaseProfessionInfo", function()
        return { professionID = id, professionName = name, skillLevel = skill, skillModifier = 0, maxSkillLevel = max }
    end)
    World.patch("C_TradeSkillUI.GetChildProfessionInfo", function() return { professionID = 0 } end)
    World.patch("C_TradeSkillUI.GetAllRecipeIDs", function() return {} end)
    World.patch("C_TradeSkillUI.IsTradeSkillLinked", function() return false end)
    World.patch("C_TradeSkillUI.IsTradeSkillGuild", function() return false end)
    World.patch("C_TradeSkillUI.IsNPCCrafting", function() return false end)
    World.patch("C_Map.GetMapInfo", function(m) return { mapID = m, name = "Zone" .. m, mapType = 3 } end)
    World.patch("UnitLevel", function() return 12 end)
    World.patch("UnitFactionGroup", function() return "Horde" end)
    World.patch("C_Item.GetItemCount", function() return 0 end)
    -- The window opened: TRADE_SKILL_SHOW came.
    World.set(CP.Professions, "tradeSkillOpen", true)
end

for _, case in ipairs({ { HERB, "Herbalism", 60, 75 }, { MINE, "Mining", 1, 75 },
                        { SKIN, "Skinning", 130, 150 }, { FISH, "Fishing", 1, 75 } }) do
    T.test("Guide tab shows the " .. case[2] .. " guide", function()
        local restore = flatMap()
        stubGathering(unpack(case))
        MapWorld.SettleGuides({ case[1] })
        CP.Panel.frame:Show()
        CP.Panel.tabs.guide.button:GetScript("OnClick")()
        CP.Panel:Refresh()
        local ui = CP.GuideTab.ui
        T.ok(#ui.rows > 0, "rows drawn")
        T.eq(ui.line, case[1])
        T.ok(not ui.empty:IsShown(), "no 'No guide' text")
        T.ok(ui.details:IsShown(), "details for the first row")
        T.ok(not ui.details.craftAll:IsShown(), "no craft buttons for gathering")
        T.ok(ui.details.pin:IsShown(), "waypoint on the details")
        CP.Panel.frame:Hide()
        restore()
    end)
end

T.test("Herbalism at 60 of 75 shows Journeyman training first", function()
    local restore = flatMap()
    stubGathering(HERB, "Herbalism", 60, 75)
    MapWorld.SettleGuides({ HERB })
    CP.Panel.frame:Show()
    CP.Panel.tabs.guide.button:GetScript("OnClick")()
    CP.Panel:Refresh()
    local first = CP.GuideTab.ui.rows[1]
    T.ok(first.gatherRank and first.gatherRank.name == "Journeyman", "train now")
    T.eq(first.from, 60)
    CP.Panel.frame:Hide()
    restore()
end)

T.test("fishing never sends a player into the other faction's home waters", function()
    local TELDRASSIL = 1438
    for _, skill in ipairs({ 1, 40, 90 }) do
        for _, c in ipairs(CP.Fishing.Candidates(skill, 10, "Horde")) do
            T.ok(c.zone ~= TELDRASSIL and c.zone ~= ELWYNN, "Horde sent to " .. c.zone)
        end
        for _, c in ipairs(CP.Fishing.Candidates(skill, 10, "Alliance")) do
            T.ok(c.zone ~= DUROTAR, "Alliance sent to Durotar")
        end
    end
    for _, r in ipairs(rows(FISH, 1, 75, 5, "Horde", DUROTAR)) do
        if r.fish then T.ok(not CP.Gather.EnemyHome(r.fish.zone, "Horde"), "fishing row in " .. r.fish.zone) end
    end
    local plan = CP.Fishing.Plan({ skill = 1, maxRank = 75, level = 5, zone = DUROTAR, side = "Alliance",
                                   needs = {}, have = none })
    T.ok(plan.kind ~= "zone" or plan.zone ~= DUROTAR, "an Alliance player in Durotar is sent home")
end)

T.test("back-to-back fishing stretches in the same water are one row", function()
    local restore = flatMap()
    for _, c in ipairs({ { 1, 75, 5, "Horde" }, { 1, 75, 5, "Alliance" }, { 60, 75, 12, "Horde" },
                         { 100, 150, 20, "Horde" }, { 200, 225, 40, "Alliance" } }) do
        local list = GG.Rows({ line = FISH, skill = c[1], max = c[2], level = c[3], side = c[4] })
        for i = 2, #list do
            local a, b = list[i - 1], list[i]
            if a.fish and b.fish then
                T.ok(a.fish.zone ~= b.fish.zone,
                    ("%s %d: %d-%d and %d-%d both in %d"):format(c[4], c[1], a.from, a.to, b.from, b.to, a.fish.zone))
            end
        end
    end
    restore()
end)

T.test("gathering zones stay off the other faction's ground", function()
    local restore = flatMap()
    local ok, err = pcall(function()
        for _, side in ipairs({ "Horde", "Alliance" }) do
            for _, line in ipairs({ HERB, MINE }) do
                for _, level in ipairs({ 5, 60 }) do
                    local start = side == "Horde" and DUROTAR or ELWYNN
                    for _, r in ipairs(gatherRows(rows(line, 1, 75, level, side, start))) do
                        T.ok(CP.Gather.Territory(r.gather.zone, side) ~= "enemy",
                            ("%s %d at level %d: %d-%d in zone %d"):format(side, line, level, r.from, r.to, r.gather.zone))
                    end
                end
            end
        end
        T.eq(CP.Gather.Territory(1433, "Horde"), "enemy", "Redridge is Alliance ground")
        T.eq(CP.Gather.Territory(1413, "Horde"), "own", "the Barrens are Horde ground")
        T.eq(CP.Gather.Territory(1424, "Horde"), "contested", "Hillsbrad is contested")
    end)
    restore()
    T.ok(ok, err)
end)

T.test("the route takes in herbs and ore that still give skill", function()
    local restore = flatMap()
    local ok, err = pcall(function()
        local names = {}
        for _, r in ipairs(CP.Gather.SkillRows(DUROTAR, { [MINE] = 1 })) do
            T.ok(r.itemID < 0 and r.need == 1)
            names[r.sources[1].name] = true
        end
        T.ok(names["Copper Vein"], "Copper at Mining 1")
        T.eq(#CP.Gather.SkillRows(DUROTAR, { [MINE] = 300 }), 0, "nothing at 300")
        T.eq(#CP.Gather.SkillRows(DUROTAR, { [SKIN] = 1 }), 0, "Skinning routes come from its grind spots")

        -- The Hinterlands at Mining 100: its ore is above the player's skill, so none of it routes.
        local HINTERLANDS = 1425
        local wide = CP.Gather.SkillRows(HINTERLANDS, { [MINE] = 100 }, true)
        for _, r in ipairs(wide) do
            local src = r.sources[1]
            T.ok(src.skill and src.item, src.name .. " says its skill and yield")
            T.ok(src.skill <= 100, src.name .. " is in reach at 100")
        end
    end)
    restore()
    T.ok(ok, err)
end)

T.test("the player's level is the game's", function()
    MapWorld.begin({ zone = 1421, level = 40, side = "Horde" })
    T.eq(CP.Gather.PlayerLevel(), 40)
    MapWorld.SetLevel(41)
    T.eq(CP.Gather.PlayerLevel(), 41, "after a level-up")
end)

T.test("the route filter: skipped nodes drop out, farming takes grey ones", function()
    local restore = flatMap()
    local saved = { mode = CP.db.routeMode, skip = CP.db.routeSkip }
    local ok, err = pcall(function()
        local function names(list)
            local out = {}
            for _, r in ipairs(list) do out[r.sources[1].name] = true end
            return out
        end
        CP.db.routeMode, CP.db.routeSkip = nil, nil
        T.ok(not names(CP.Gather.SkillRows(DUROTAR, { [MINE] = 150 }))["Copper Vein"], "levelling at 150: Copper is grey")
        CP.db.routeMode = "farm"
        T.ok(names(CP.Gather.SkillRows(DUROTAR, { [MINE] = 150 }))["Copper Vein"], "farming takes it")
        CP.db.routeSkip = { ["Copper Vein"] = true }
        T.ok(not names(CP.Gather.SkillRows(DUROTAR, { [MINE] = 150 }))["Copper Vein"], "unless it's unticked")
        local sig = CP.Gather.RouteSignature()
        CP.db.routeSkip = nil
        T.ok(sig ~= CP.Gather.RouteSignature(), "a filter change re-solves the route")
        local mining = CP.Gather.RouteNodes(MINE, DUROTAR)
        T.eq(mining[1].name, "Copper Vein", "the menu lists the zone's ore by skill")
    end)
    CP.db.routeMode, CP.db.routeSkip = saved.mode, saved.skip
    restore()
    T.ok(ok, err)
end)

-- A stand-in for Blizzard_Menu's root description, recording what the menu adds.
-- A menu entry as the game's menus hand back: it remembers the response it was given.
local function entry(rec)
    function rec:SetResponse(r) self.response = r end
    return rec
end

local function menuRoot()
    local m = { titles = {}, radios = {}, profs = {}, checks = {}, buttons = {} }
    local root = {}
    function root.CreateTitle(_, text)
        if text ~= CP.GatherList.SHOW_HEADER then m.titles[#m.titles + 1] = text end   -- the panel's own is read apart
    end
    -- The route's radios are keyed by mode name; the panel's profession radios by skill line.
    function root.CreateRadio(_, text, get, set, data)
        local list = type(data) == "string" and m.radios or m.profs
        list[#list + 1] = entry({ text = text, get = get, set = set, data = data })
        return list[#list]
    end
    function root.CreateCheckbox(_, text, get, set, data)
        m.checks[#m.checks + 1] = entry({ text = text, get = get, set = set, data = data })
        return m.checks[#m.checks]
    end
    function root.CreateButton(_, text, fn)
        m.buttons[#m.buttons + 1] = entry({ text = text, fn = fn })
        return m.buttons[#m.buttons]
    end
    return root, m
end

T.test("the route menu stays open after a pick", function()
    local restore = flatMap()
    local saved = { mode = CP.db.routeMode, skip = CP.db.routeSkip }
    local root, m = menuRoot()
    World.patch("MenuUtil.CreateContextMenu", function(owner, gen) gen(owner, root) end)
    World.set(_G, "MenuResponse", { Open = 1, Refresh = 2, Close = 3, CloseAll = 4 })
    local skills, zoneOf = CP.Gather.Skills, CP.Gather.PlayerZone
    CP.Gather.Skills = function() return { [MINE] = 100, [HERB] = 100 } end
    CP.Gather.PlayerZone = function() return DUROTAR end
    CP.db.routeMode = "farm"
    local ok, err = pcall(function()
        CP.GatherList.RouteMenu(UIParent)
        for _, r in ipairs(m.radios) do
            T.eq(r.response, MenuResponse.Refresh, r.text .. ": stays open")
            T.eq(r.set(r.data), MenuResponse.Refresh, r.text .. ": its handler says refresh")
        end
        for _, c in ipairs(m.checks) do T.eq(c.response, MenuResponse.Refresh, c.text .. ": stays open") end
        T.eq(m.buttons[1].response, MenuResponse.Refresh, "the reset stays open")
    end)
    CP.Gather.Skills, CP.Gather.PlayerZone = skills, zoneOf
    CP.db.routeMode, CP.db.routeSkip = saved.mode, saved.skip
    restore()
    T.ok(ok, err)
end)

T.test("the route menu offers both modes and this zone's herbs and ore", function()
    local restore = flatMap()
    local saved = { mode = CP.db.routeMode, skip = CP.db.routeSkip }
    local root, m = menuRoot()
    local radios, checks = m.radios, m.checks
    World.patch("MenuUtil.CreateContextMenu", function(owner, gen) gen(owner, root) end)
    local skills, zoneOf = CP.Gather.Skills, CP.Gather.PlayerZone
    CP.Gather.Skills = function() return { [MINE] = 100, [HERB] = 100 } end
    CP.Gather.PlayerZone = function() return DUROTAR end
    CP.db.routeMode = "farm"
    local ok, err = pcall(function()
        CP.GatherList.RouteMenu(UIParent)
        T.eq(#radios, 2)
        local herbs = {}
        for _, c in ipairs(checks) do herbs[c.data] = true end
        T.ok(herbs["Peacebloom"] and herbs["Silverleaf"], "Durotar's herbs")
        -- No zone maps here, so neighbours' spawns spill in; the game clips them (Gather.Clusters).
        T.ok(not herbs["Dreamfoil"] and not herbs["Thorium Vein"], "nothing from far zones")
        T.ok(herbs["Copper Vein"], "Durotar's ore")
        T.ok(checks[1].get(checks[1].data), "everything ticked to start")
        checks[1].set(checks[1].data)
        T.ok(CP.Gather.RouteSkipped(checks[1].data), "unticking skips it")
        radios[1].set(radios[1].data)
        T.ok(not CP.Gather.RouteFarming())
        T.ok(CP.Gather.NodeUnticked(checks[1].data), "leveling keeps the ticks saved")
        T.ok(not CP.Gather.RouteSkipped(checks[1].data), "and the guide skips nothing")
        radios[2].set(radios[2].data)
        T.ok(CP.Gather.RouteFarming())
        T.ok(CP.Gather.RouteSkipped(checks[1].data), "back in Farm the pick holds")
        T.eq(#m.buttons, 1, "a reset at the end")
        T.eq(m.buttons[1].text, "Show every herb and ore")
        m.buttons[1].fn()
        T.ok(CP.Gather.RouteFarming() and not CP.Gather.RouteSkipped(checks[1].data), "every node back, the mode stays")
    end)
    CP.Gather.Skills, CP.Gather.PlayerZone = skills, zoneOf
    CP.db.routeMode, CP.db.routeSkip = saved.mode, saved.skip
    restore()
    T.ok(ok, err)
end)

-- The route menu as a player with `have` (skill line -> rank) in Durotar builds it.
local function menuFor(have, check)
    local restore = flatMap()
    local saved = { mode = CP.db.routeMode, skip = CP.db.routeSkip }
    local root, m = menuRoot()
    World.patch("MenuUtil.CreateContextMenu", function(owner, gen) gen(owner, root) end)
    local skills, zoneOf = CP.Gather.Skills, CP.Gather.PlayerZone
    CP.Gather.Skills = function() return have end
    CP.Gather.PlayerZone = function() return DUROTAR end
    CP.db.routeMode = "farm"
    local ok, err = pcall(function()
        CP.GatherList.RouteMenu(UIParent)
        local nodes = {}
        for _, c in ipairs(m.checks) do nodes[c.data] = true end
        check(m, nodes, table.concat(m.titles, "|"))
    end)
    CP.Gather.Skills, CP.Gather.PlayerZone = skills, zoneOf
    CP.db.routeMode, CP.db.routeSkip = saved.mode, saved.skip
    restore()
    T.ok(ok, err)
end

T.test("without a gathering profession the route menu lists nothing and says to learn one", function()
    menuFor({ [FISH] = 120 }, function(m, nodes, titles)
        T.eq(#m.radios, 2, "leveling and farming")
        T.eq(#m.checks, 0, "no checkboxes")
        T.ok(titles:find(CP.GatherList.ROUTE_LEARN, 1, true) ~= nil, titles)
        T.ok(not titles:find("not learned", 1, true), titles)
        T.eq(#m.buttons, 0, "no gathering profession: no reset")
    end)
end)

T.test("with Skinning only the route menu lists only skinning materials", function()
    menuFor({ [SKIN] = 120 }, function(m, nodes, titles)
        T.ok(#m.checks > 0, "this zone's leathers")
        for _, c in ipairs(m.checks) do T.eq(type(c.data), "number", c.text .. " is keyed by item") end
        T.ok(not nodes["Copper Vein"] and not nodes["Peacebloom"], "no herbs or ore")
        T.ok(titles:find("Skinning", 1, true) ~= nil and not titles:find("Mining", 1, true), titles)
        T.ok(not titles:find(CP.GatherList.ROUTE_LEARN, 1, true), titles)
        T.eq(m.buttons[1].text, "Show every leather")
    end)
end)

T.test("with Mining only the route menu lists only ores", function()
    menuFor({ [MINE] = 100 }, function(m, nodes, titles)
        T.ok(nodes["Copper Vein"], "Durotar's ore")
        T.ok(not nodes["Peacebloom"] and not nodes["Silverleaf"], "no herbs")
        T.ok(titles:find("Mining", 1, true) ~= nil and not titles:find("Herbalism", 1, true), titles)
        T.ok(not titles:find(CP.GatherList.ROUTE_LEARN, 1, true), titles)
        T.eq(#m.radios, 2)
        T.eq(#m.buttons, 1, "the reset")
        T.eq(m.buttons[1].text, "Show every ore")
    end)
end)

T.test("the header's filter is a menu icon; the route button has no right-click menu", function()
    local L = CP.GatherList
    local f = L.head.filter
    -- Made at load: Daylight UI's icon button with its menu bars when it is loaded, ours here.
    T.eq(f.icon.file, f.daylight and L.FILTER_ICONS.daylight or L.FILTER_ICONS.own)
    T.ok(not f.icon.file:find("OptionsButton", 1, true), "no gear")
    T.eq(L.FILTER_ICONS.daylight, "ui-micro-menu.png", "Daylight UI's menu bars")
    T.eq(L.FILTER_ICONS.own, "Interface\\AddOns\\ProfessionallyLost\\Media\\Menu")

    local menus = 0
    World.patch("MenuUtil.CreateContextMenu", function() menus = menus + 1 end)
    local was = CP.db.route
    local r = L.head.route
    r:GetScript("OnClick")(r, "RightButton")
    T.eq(menus, 0, "a right-click opens no menu")
    T.eq(CP.db.route, was, "and doesn't toggle the route")
    f:GetScript("OnClick")(f, "LeftButton")
    T.eq(menus, 1, "the filter opens it")

    local owners = 0
    World.set(GameTooltip, "SetOwner", function() owners = owners + 1 end)
    for _, b in ipairs({ r, f }) do
        local enter = b:GetScript("OnEnter")
        if enter then enter(b) end
    end
    T.eq(owners, 0, "the header icons show no tooltip")
    CP.db.route = was
end)

-- Opens the route menu for a player with `skills` and returns what it holds.
local function openMenu(skills)
    local root, menu = menuRoot()
    World.patch("MenuUtil.CreateContextMenu", function(owner, gen) gen(owner, root) end)
    local was, zoneOf = CP.Gather.Skills, CP.Gather.PlayerZone
    CP.Gather.Skills = function() return skills end
    CP.Gather.PlayerZone = function() return DUROTAR end
    CP.GatherList.RouteMenu(UIParent)
    CP.Gather.Skills, CP.Gather.PlayerZone = was, zoneOf
    return menu
end

T.test("the radios read 'Follow the guide' and 'Farm: pick what to gather'", function()
    local restore = flatMap()
    local menu = openMenu({ [MINE] = 100 })
    restore()
    T.eq(menu.radios[1].text, "Follow the guide")
    T.eq(menu.radios[2].text, "Farm: pick what to gather")
end)

T.test("leveling shows one dim line naming what the guide follows, no ticks and no reset", function()
    local restore = flatMap()
    local saved = { mode = CP.db.routeMode, skip = CP.db.routeSkip }
    local ok, err = pcall(function()
        CP.db.routeMode, CP.db.routeSkip = nil, { ["Copper Vein"] = true }
        local menu = openMenu({ [MINE] = 1 })
        T.eq(#menu.checks, 0, "no checkboxes")
        T.eq(#menu.buttons, 0, "no reset")
        local head
        for i, t in ipairs(menu.titles) do
            if t:find("^|cff%x%x%x%x%x%xFollowing the guide|r$") then head = i end
        end
        T.ok(head ~= nil and head < #menu.titles, "the dim heading, names under it")
        T.ok(menu.titles[#menu.titles]:find("^|cff%x%x%x%x%x%x") ~= nil, "the names lines are dim too")
        T.eq(CP.db.routeSkip, { ["Copper Vein"] = true }, "the ticks stay saved")
        local GL = CP.GatherList
        T.eq(GL.FollowLines({}), { "Following the guide", "nothing to gather here" })
        T.eq(GL.FollowLines({ "Peacebloom", "Copper Ore" }), { "Following the guide", "Peacebloom", "Copper Ore" })
        T.eq(GL.FollowLines({ "a", "b", "c", "d", "e", "f", "g", "h" }), { "Following the guide", "a", "b +6 more" })
    end)
    CP.db.routeMode, CP.db.routeSkip = saved.mode, saved.skip
    restore()
    T.ok(ok, err)
end)

T.test("the reset entry only re-ticks nodes; the mode stays", function()
    local restore = flatMap()
    local saved = { mode = CP.db.routeMode, skip = CP.db.routeSkip }
    local ok, err = pcall(function()
        CP.db.routeMode = "farm"
        CP.db.routeSkip = { ["Copper Vein"] = true }
        local menu = openMenu({ [MINE] = 100 })
        T.eq(#menu.buttons, 1, "one reset entry")
        menu.buttons[1].fn()
        T.eq(CP.db.routeSkip, nil, "every node ticks again")
        T.eq(CP.db.routeMode, "farm", "the mode stays")
    end)
    CP.db.routeMode, CP.db.routeSkip = saved.mode, saved.skip
    restore()
    T.ok(ok, err)
end)

T.test("the reset entry's label follows the player's gathering professions", function()
    local restore = flatMap()
    local mode = CP.db.routeMode
    CP.db.routeMode = "farm"
    local ok, err = pcall(function()
        local cases = {
            { { [HERB] = 50 }, "Show every herb" },
            { { [MINE] = 50 }, "Show every ore" },
            { { [HERB] = 50, [MINE] = 50 }, "Show every herb and ore" },
            { { [SKIN] = 50 }, "Show every leather" },
            { { [HERB] = 50, [SKIN] = 50 }, "Show every herb and leather" },
            { { [MINE] = 50, [SKIN] = 50 }, "Show every ore and leather" },
            { { [HERB] = 50, [MINE] = 50, [SKIN] = 50 }, "Show every herb, ore and leather" },
        }
        for _, c in ipairs(cases) do
            local menu = openMenu(c[1])
            T.eq(#menu.buttons, 1)
            T.eq(menu.buttons[1].text, c[2])
        end
        T.eq(#openMenu({}).buttons, 0, "neither profession: no reset entry")

        -- The options page has no reset: the route menu keeps the only one.
        for _, e in ipairs(CP.Settings.LIST) do
            T.ok(not (e.label or ""):find("^Show every"), "no options reset: " .. tostring(e.label))
        end
    end)
    CP.db.routeMode = mode
    restore()
    T.ok(ok, err)
end)

T.test("nodes above the player's skill are no route rows", function()
    local restore = flatMap()
    local ok, err = pcall(function()
        local SILVERPINE = 1421
        local rows = CP.Gather.SkillRows(SILVERPINE, { [MINE] = 1 }, true)
        T.ok(#rows > 0, "Copper routes at Mining 1")
        for _, r in ipairs(rows) do T.eq(r.sources[1].name, "Copper Vein", "only Copper at Mining 1") end
        local walk = CP.Route.Points(SILVERPINE, rows, nil, "node")
        T.ok(#walk > 0)
        for _, p in ipairs(walk) do T.ok(p.name == "Copper Vein", "the loop walks only " .. tostring(p.name)) end
    end)
    restore()
    T.ok(ok, err)
end)

T.test("a herb split over several data entries still routes", function()
    local restore = flatMap()
    local ok, err = pcall(function()
        local rows = CP.Gather.SkillRows(DUROTAR, { [HERB] = 1 })
        local names = {}
        for _, r in ipairs(rows) do names[r.sources[1].name] = (names[r.sources[1].name] or 0) + 1 end
        T.ok(names["Peacebloom"] and names["Silverleaf"], "Durotar's starting herbs")
        T.ok(CP.Gather.NameSpawns(DUROTAR, "Peacebloom") >= CP.Gather.MIN_NODE_SPAWNS)
        local stops = CP.Route.Points(DUROTAR, rows, nil, "node")
        T.ok(#stops > 10, ("%d stops"):format(#stops))
    end)
    restore()
    T.ok(ok, err)
end)

T.test("with GatherMate2 covering a zone, herbs it never found there are left out", function()
    local restore = flatMap()
    local GM = CP.GatherMate
    local orig = GM.Nodes
    local ok, err = pcall(function()
        local HILLSBRAD = 1424
        local function names()
            local out = {}
            for _, n in ipairs(CP.Gather.RouteNodes(HERB, HILLSBRAD)) do out[n.name] = true end
            return out
        end
        T.ok(names()["Khadgar's Whisker"], "vanilla data alone lets it leak in")
        -- GatherMate2 has 40 Hillsbrad herbs on record, none of them Khadgar's Whisker.
        local spots = {}
        for i = 1, 20 do spots[i] = { 0.3 + i * 0.01, 0.4, 1 } end
        GM.Nodes = function(zone)
            if zone ~= HILLSBRAD then return {} end
            return { ["Bruiseweed"] = spots, ["Kingsblood"] = spots }
        end
        CP.Gather.ResetClusters()
        local seen = names()
        T.ok(not seen["Khadgar's Whisker"] and not seen["Goldthorn"], "the leaked herbs go")
        T.ok(seen["Bruiseweed"] and seen["Kingsblood"], "the recorded ones stay")
    end)
    GM.Nodes = orig
    CP.Gather.ResetClusters()
    restore()
    T.ok(ok, err)
end)

T.test("no zone holds a gathering guide for most of its length", function()
    local restore = flatMap()
    local ok, err = pcall(function()
        for _, side in ipairs({ "Horde", "Alliance" }) do
            for _, line in ipairs({ HERB, MINE }) do
                local start = side == "Horde" and DUROTAR or ELWYNN
                local stretch, zone, from = 0, nil, 1
                for _, r in ipairs(gatherRows(rows(line, 1, 75, 5, side, start))) do
                    if r.gather.zone ~= zone then zone, from = r.gather.zone, r.from end
                    stretch = math.max(stretch, r.to - from)
                end
                T.ok(stretch <= 110, ("%s %d: longest stretch in one zone %d points"):format(side, line, stretch))
            end
        end
    end)
    restore()
    T.ok(ok, err)
end)

T.test("a Horde gathering guide follows the levelling lane and never goes back", function()
    local restore = flatMap()
    local ok, err = pcall(function()
        T.ok(CP.GatherGuide.InLane(1424, "Horde", 25), "Hillsbrad is on the Horde lane in the 20s")
        T.ok(not CP.GatherGuide.InLane(1424, "Horde", 50), "but not at 50")
        for _, line in ipairs({ HERB, MINE, SKIN }) do
            local seen, last = {}, nil
            for _, r in ipairs(gatherRows(rows(line, 1, 75, 5, "Horde", DUROTAR))) do
                local z = r.gather.zone
                if z ~= last then
                    T.ok(not seen[z], ("%d: back to zone %d at %d"):format(line, z, r.from))
                    seen[z], last = true, z
                end
            end
        end
    end)
    restore()
    T.ok(ok, err)
end)

T.test("wow-professions.com's zones lead each band; each faction keeps its own home zones", function()
    local restore = flatMap()
    local ok, err = pcall(function()
        local HILLSBRAD, REDRIDGE, ARATHI, NEEDLES, HINTERLANDS = 1424, 1433, 1417, 1441, 1425
        T.ok(GG.InSite(MINE, REDRIDGE, "Alliance", 80) and not GG.InSite(MINE, REDRIDGE, "Horde", 80),
            "Redridge is the Alliance's, not the Horde's")
        local function zoneAt(line, side, skill)
            local start = side == "Horde" and DUROTAR or ELWYNN
            for _, r in ipairs(gatherRows(rows(line, 1, 75, 5, side, start))) do
                if skill >= r.from and skill < r.to then return r.gather.zone end
            end
        end
        T.eq(zoneAt(MINE, "Horde", 100), HILLSBRAD, "Horde Mining 65-125")
        T.eq(zoneAt(MINE, "Horde", 160), ARATHI, "Horde Mining 125-175")
        T.eq(zoneAt(HERB, "Horde", 250), HINTERLANDS, "Herbalism 230-270")
        T.eq(zoneAt(SKIN, "Horde", 180), NEEDLES, "Horde Skinning 125-205")
    end)
    restore()
    T.ok(ok, err)
end)

T.test("Mining 100: the guide starts in the player's zone while it pays, longer when the skill trails the level", function()
    local restore = flatMap()
    local ok, err = pcall(function()
        local SILVERPINE, ASHENVALE = 1421, 1440
        for _, level in ipairs({ 25, 30 }) do
            local r = gatherRows(rows(MINE, 100, 150, level, "Horde", SILVERPINE))
            T.eq(r[1].gather.zone, SILVERPINE, ("Silverpine at level %d"):format(level))
            -- Silverpine's veins share their spots (Tin 67% · Copper 17% · Silver 17%), so it pays
            -- to 110, no longer to the stretch's end at 125.
            T.ok(r[1].to >= 110, ("for more than one step: to %d"):format(r[1].to))
        end
        -- The first stretch stays on the player's continent. On Kalimdor the Barrens scores
        -- about 40% of Ashenvale at level 30: only the behind rule keeps a miner there.
        local behind = gatherRows(rows(MINE, 100, 150, 30, "Horde", BARRENS))
        T.eq(behind[1].gather.zone, BARRENS, "level 30, skill behind: a weaker zone still keeps them")
        local was = GG.HOME_BEHIND
        GG.HOME_BEHIND = 0.5
        GG.Reset()
        local without = gatherRows(rows(MINE, 100, 150, 30, "Horde", BARRENS))
        GG.HOME_BEHIND = was
        GG.Reset()
        T.eq(without[1].gather.zone, ASHENVALE, "without the rule: off to Ashenvale")
    end)
    restore()
    T.ok(ok, err)
end)

T.test("a character with Mining 100: the checklist and guide see it, under its 150 cap", function()
    MapWorld.begin({ zone = 1421, level = 30, side = "Horde" })
    CraftWorld.begin({ professions = { [MINE] = 100 } })
    CraftWorld.Open(MINE)
    T.eq(CP.Professions.Current().name, "Mining")
    T.eq(CP.Gather.Skills()[MINE], 100, "the checklist and guide see Mining 100")
    T.eq(CP.Gather.MaxRank(MINE), 150)
    T.eq(CP.Gather.Skills()[HERB], nil, "no Herbalism")
end)

T.test("the Alliance levelling lane covers 1-60", function()
    T.ok(GG.InLane(1429, "Alliance", 5), "Elwynn at 5")
    T.ok(GG.InLane(1436, "Alliance", 14), "Westfall at 14")
    T.ok(GG.InLane(1434, "Alliance", 45), "Stranglethorn at 45")
    T.ok(not GG.InLane(1411, "Alliance", 5), "not Durotar")
    for level = 1, 60 do
        local any = false
        for _, step in ipairs(CP.Lanes.Alliance) do
            if level >= step[1] and level <= step[2] then any = true end
        end
        T.ok(any, "a lane zone at level " .. level)
    end
end)
