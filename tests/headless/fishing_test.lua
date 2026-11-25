-- Fishing leveling plan against the generated zone data.

local CP = ProfLost
local F = CP.Fishing
local BARRENS, DUROTAR, WESTFALL = 1413, 1411, 1436

local function none() return 0 end

T.test("skill-up chance follows cMaNGOS", function()
    T.eq(F.SkillUpChance(50), 1)
    T.eq(F.SkillUpChance(100), 0.5)
    T.ok(math.abs(F.SkillUpChance(200) - 1 / 6) < 1e-9)
    T.eq(F.CatchesTo(1, 75), 74, "one catch per point below 75")
    T.ok(F.CatchesTo(75, 150) > 150, "about two catches per point from 75")
end)

T.test("rank steps come at the cap: trainer, book, quest", function()
    T.eq(F.RankStep(74, 75), nil)
    T.eq(F.RankStep(75, 75).kind, "trainer")
    T.eq(F.RankStep(150, 150).kind, "book")
    T.eq(F.RankStep(150, 150).item, 16083)
    T.eq(F.RankStep(225, 225).kind, "quest")
    T.eq(F.RankStep(300, 300), nil)
    T.ok(#F.RankStep(75, 75).npcs > 5, "Fishing trainers in both factions")
    local book = F.RankStep(150, 150).npcs[1]
    T.eq(CP.GatherData.fishing.npcs[book][1], "Old Man Heming")
end)

T.test("candidates land the most bites and are safe for the level", function()
    local early = F.Candidates(1, 10)
    T.ok(#early > 0, "starter waters at skill 1")
    T.eq(early[1].land, 76, "base -70 lands 76% at skill 1")
    for _, c in ipairs(F.Candidates(30, 10)) do
        T.eq(c.land, 100)
        T.ok(CP.GatherData.zones[c.zone].lvl[1] <= 12, "zone too high for level 10")
    end
    local high = {}
    for _, c in ipairs(F.Candidates(300, 60)) do high[c.zone] = true end
    T.ok(high[BARRENS] and high[WESTFALL], "everything lands at 300")
end)

T.test("fish here when every bite lands, else the nearest water that does", function()
    local p = F.Plan({ skill = 30, maxRank = 75, level = 15, zone = DUROTAR, have = none,
        distance = function() return 100 end })
    T.eq(p.kind, "zone")
    T.ok(p.here, "Durotar lands everything at 30")
    T.eq(p.catches, 45)
    local away = F.Plan({ skill = 1, maxRank = 75, level = 15, zone = 1446,   -- Tanaris, base 255
        have = none, distance = function(z) return z == DUROTAR and 10 or 1000 end })
    T.ok(not away.here)
    T.eq(away.zone, DUROTAR, "nearest")
end)

T.test("at the cap the plan is the rank step", function()
    local p = F.Plan({ skill = 75, maxRank = 75, level = 20, zone = BARRENS, have = none })
    T.eq(p.kind, "rank")
    T.eq(p.rank.kind, "trainer")
end)

T.test("with the Cooking option, waters whose catch Cooking needs win", function()
    local smallfish = 6291   -- Raw Brilliant Smallfish, the Cooking guide's early fish
    local feeds = {}
    for zone in pairs(CP.GatherData.zones) do
        if #F.Feeds(zone, { [smallfish] = 72 }, none) > 0 then feeds[zone] = true end
    end
    T.ok(next(feeds) ~= nil, "some water has Brilliant Smallfish")
    local p = F.Plan({ skill = 30, maxRank = 75, level = 15, zone = BARRENS, cook = true,
        needs = { [smallfish] = 72 }, have = none, distance = function() return 100 end })
    T.ok(feeds[p.zone], "picked water with smallfish")
    T.eq(p.feeds[1].item, smallfish)
    T.eq(p.feeds[1].need, 72)
end)

T.test("plan lines read plainly", function()
    local lines = CP.GatherList.FishLines({ kind = "zone", zone = DUROTAR, here = true, land = 100, catches = 45, feeds = {} },
        DUROTAR, 75)
    T.eq(lines[1].text, "Fish here to 75")
    T.eq(lines[1].info, "~45 catches")
    local rank = CP.GatherList.FishLines({ kind = "rank", rank = F.RankStep(150, 150) }, DUROTAR, 150)
    T.eq(rank[1].text, "Buy Expert Fishing")
    T.ok(rank[1].pin ~= nil, "pin to the vendor")
end)

T.test("what the fishing feeds sits under its heading behind a down-right arrow", function()
    local GL, S = CP.GatherList, CP.Style
    World.set(CP, "ItemName", function(id) return id == 6291 and "Raw Brilliant Smallfish" or "Raw Longjaw Mud Snapper" end)
    local lines = GL.FishLines({ kind = "zone", zone = DUROTAR, here = false, land = 100, catches = 45,
        feeds = { { item = 6291, need = 46, have = 0 }, { item = 6289, need = 52, have = 60 } } }, DUROTAR, 75)
    T.eq(#lines, 3, "the heading and two feeds, wording unchanged")
    T.eq(lines[2].kind, "feed")
    T.eq(lines[2].text, "Raw Brilliant Smallfish x46")
    T.eq(lines[2].textColor, S.color.warn, "short: yellow")
    T.eq(lines[3].text, "Raw Longjaw Mud Snapper: enough")
    T.eq(lines[3].textColor, S.color.good)

    -- Drawn: the arrow under the heading's text, the name to its right, indented past the heading.
    -- Refresh puts other sections ("Next up") on top of the list it is given: a copy.
    local headLine, feedLine = lines[1], lines[2]
    local saved = GL.Lines
    GL.Lines = function() return { lines[1], lines[2], lines[3] } end
    local ok, err = pcall(function()
        GL.Refresh()
        T.advance(0.1)
        local _, rows = GL.Drawn()
        local heading, feed
        for _, r in ipairs(rows) do
            if r:IsShown() and r.line == headLine then heading = r end
            if r:IsShown() and r.line == feedLine then feed = r end
        end
        T.ok(heading and feed, "both drawn")
        T.ok(feed.arrow:IsShown(), "the arrow shows")
        -- The last LEFT point each was given: SetPoint("LEFT", x, 0) or ("LEFT", rel, "RIGHT", x, 0).
        local function left(region)
            for i = region:GetNumPoints(), 1, -1 do
                local p = { region:GetPoint(i) }
                if p[1] == "LEFT" then return p end
            end
        end
        local ax, hx = left(feed.arrow)[2], left(heading.name)[2]
        T.ok(ax > hx, ("the arrow (%s) sits in from the heading's text (%s)"):format(ax, hx))
        T.ok(left(feed.name)[2] == feed.arrow, "the name follows the arrow")
        T.eq(feed.name:GetText(), "Raw Brilliant Smallfish x46")
        T.ok(not heading.arrow:IsShown(), "no arrow on the heading")
    end)
    GL.Lines = saved
    GL.Refresh()
    T.ok(ok, err)
end)

T.test("fishing never sends a player to the other faction's capital", function()
    -- Cross-check with FishFry: the Horde's 75-130 list held Stormwind. Their own capital
    -- stays (Thunder Bluff's pond, Stormwind's canals).
    local G, F = ProfLost.Gather, ProfLost.Fishing
    local CAPITALS = { Alliance = { 1453, 1455, 1457 }, Horde = { 1454, 1456, 1458 } }
    local ENEMY = { Alliance = "Horde", Horde = "Alliance" }
    for _, side in ipairs({ "Horde", "Alliance" }) do
        for _, zone in ipairs(CAPITALS[ENEMY[side]]) do
            T.ok(G.EnemyHome(zone, side), ("%s: %d counts as enemy"):format(side, zone))
        end
        for _, zone in ipairs(CAPITALS[side]) do
            T.ok(not G.EnemyHome(zone, side), ("%s: own capital %d allowed"):format(side, zone))
        end
        for _, skill in ipairs({ 75, 100, 125 }) do
            for _, c in ipairs(F.Candidates(skill, 20, side)) do
                T.ok(not G.EnemyHome(c.zone, side), ("%s at %d: sent to %d"):format(side, skill, c.zone))
            end
        end
    end
end)

T.test("fishing rank rows say what learning them needs", function()
    -- The classic trainer, book and quest rows: Journeyman level 10 from 50, the Expert
    -- book level 20 from 125, Katoom's Artisan level 35 from 200, Nat Pagle's quest level
    -- 35 at 225.
    local want = { ["75 trainer"] = { 10, 50 }, ["150 book"] = { 20, 125 }, ["225 trainer"] = { 35, 200 },
                   ["225 quest"] = { 35, 225 } }
    local seen = 0
    for _, r in ipairs(ProfLost.GatherData.fishing.ranks) do
        local key = r.skill .. " " .. r.kind
        T.ok(want[key] ~= nil, "rank " .. key)
        T.eq({ r.level or 0, r.at }, want[key], "rank " .. key)
        seen = seen + 1
    end
    T.eq(seen, 4, "four ranks")
    local book
    for _, r in ipairs(ProfLost.GatherData.fishing.ranks) do if r.kind == "book" then book = r end end
    local title, where = ProfLost.GuideTab.RankText({ fishRank = book, name = "Expert Fishing" })
    T.eq(title, "Buy the Expert Fishing book")
    T.eq(where, "from a vendor  ·  Fishing 125  ·  level 20")
end)
