-- The gather world (tests/world/gatherworld.lua): nodes, corpses and water, as its header
-- describes them. MOCK facts: a hand-made SimGather shape with made-up entries, so no rule
-- here leans on the truth fixture's numbers.

local CP = ProfLost
local HERB, SKIN, FISH = 182, 393, 356
local ELWYNN, DUROTAR = 1429, 1411
local LOW, HIGH, BOAR, BRUTE, ELITE = 990101, 990102, 990201, 990202, 990203
local HERB_ITEM, BONUS, LEATHER, FISH_ITEM = 990301, 990302, 990303, 990304

-- MOCK facts.
local function facts()
    return {
        nodes = {
            [LOW] = { name = "Mock Weed", line = HERB, skill = 1,
                      loot = { { HERB_ITEM, 100, 1, 3 }, { group = { { BONUS, 50, 1, 1 } } } } },
            [HIGH] = { name = "Mock Lotus", line = HERB, skill = 150, loot = { { HERB_ITEM, 100, 1, 1 } } },
        },
        mobs = {
            [BOAR] = { name = "Mock Boar", line = SKIN, min = 15, max = 15, loot = { { LEATHER, 100, 1, 1 } } },
            [BRUTE] = { name = "Mock Brute", line = SKIN, min = 40, max = 40, loot = { { LEATHER, 100, 1, 1 } } },
            [ELITE] = { name = "Mock Elite", line = SKIN, min = 15, max = 15, elite = true,
                        loot = { { ref = { { LEATHER, 100, 2, 2 } }, chance = 100, times = 2 } } },
        },
        zones = {
            [ELWYNN] = { name = "Elwynn Forest", nodes = { [LOW] = { n = 30, at = "" }, [HIGH] = { n = 10, at = "" } },
                         mobs = { [BOAR] = { n = 5, at = "" } },
                         fish = { base = -70, loot = { { group = { { FISH_ITEM, 100, 1, 1 } } } } } },
            [DUROTAR] = { name = "Durotar", mobs = { [BRUTE] = { n = 5, at = "" }, [ELITE] = { n = 5, at = "" } },
                          fish = { sub = { [1] = { name = "Deep", base = 200, loot = { { FISH_ITEM, 100, 1, 1 } } } } } },
        },
    }
end

local function scene(line, skill, opts)
    opts = opts or {}
    MapWorld.begin({ zone = opts.zone or ELWYNN, level = opts.level or 60, side = "Alliance" })
    CraftWorld.begin({ professions = { [line] = { rank = skill, max = opts.max or 300 } }, charDB = {} })
    GatherWorld.begin({ facts = facts(), seed = opts.seed or 7 })
    return CraftWorld.state.profs[line]
end

local function listen()
    local heard = {}
    local f = CreateFrame("Frame")
    for _, e in ipairs({ "UI_ERROR_MESSAGE", "CHAT_MSG_SKILL", "SKILL_LINES_CHANGED", "BAG_UPDATE_DELAYED" }) do
        f:RegisterEvent(e)
    end
    f:SetScript("OnEvent", function(_, event, ...) heard[#heard + 1] = { event = event, ... } end)
    World.onEnd(function() f:UnregisterAllEvents() end)
    return heard
end

local function src(entry)
    for _, s in ipairs(GatherWorld.Sources(GatherWorld.Facts().nodes[entry] and HERB or SKIN, MapWorld.state.zone)) do
        if s.entry == entry then return s end
    end
end

T.test("the gather world is inert before begin and puts back what it replaced", function()
    local before = C_Map.SetUserWaypoint
    local can = C_Map.CanSetUserWaypointOnMap
    scene(HERB, 1)
    T.ok(C_Map.SetUserWaypoint ~= before, "patched during the scene")
    World.finish()
    T.eq(C_Map.SetUserWaypoint, before, "the stub is back")
    T.eq(C_Map.CanSetUserWaypointOnMap, can)
    T.eq(next(GatherWorld.state), nil, "no state after the scene")
end)

T.test("a harvest needs the node's skill; below it the game refuses with its error", function()
    local p = scene(HERB, 100)
    local heard = listen()
    local ok, why, code, need = GatherWorld.Harvest(HERB, src(HIGH))
    T.eq({ ok, code, need }, { false, "skill", 150 }, why)
    T.eq(p.rank, 100, "no point from a refusal")
    T.eq(CraftWorld.Bag(HERB_ITEM), 0, "no loot from a refusal")
    T.eq(#GatherWorld.state.refusals, 1)
    T.eq(heard[1] and heard[1].event, "UI_ERROR_MESSAGE")
    T.eq(heard[1] and heard[1][2], GatherWorld.TOO_LOW)
    p.rank = 150
    T.ok((GatherWorld.Harvest(HERB, src(HIGH))), "at the need it gathers")
end)

T.test("loot lands in the bags by the truth's rolls", function()
    scene(HERB, 1)
    local bonus = 0
    for _ = 1, 200 do
        local ok, info = GatherWorld.Harvest(HERB, src(LOW))
        T.ok(ok)
        T.ok(info.items[HERB_ITEM] >= 1 and info.items[HERB_ITEM] <= 3, "1 to 3 of the herb every time")
        bonus = bonus + (info.items[BONUS] or 0)
    end
    T.ok(CraftWorld.Bag(HERB_ITEM) >= 200 and CraftWorld.Bag(HERB_ITEM) <= 600)
    T.ok(bonus > 70 and bonus < 130, "the group's 50% item about half the time: " .. bonus)
    T.eq(GatherWorld.state.loot[HERB_ITEM], CraftWorld.Bag(HERB_ITEM))
end)

T.test("a reference rolls its rows `times` times", function()
    T.eq(GatherWorld.Roll and true, true)
    scene(SKIN, 300, { zone = DUROTAR })
    local ok, info = GatherWorld.Harvest(SKIN, src(ELITE))
    T.ok(ok)
    T.eq(info.items[LEATHER], 4, "two rolls of a 2-count row")
end)

T.test("skill-ups follow the colours at the classic chances with a fixed seed", function()
    T.eq({ GatherWorld.Chance(10, 1), GatherWorld.Chance(26, 1), GatherWorld.Chance(51, 1), GatherWorld.Chance(101, 1) },
        { 100, 75, 25, 0 })
    T.eq({ GatherWorld.Chance(24, 0), GatherWorld.Chance(25, 0), GatherWorld.Chance(49, 0), GatherWorld.Chance(50, 0),
           GatherWorld.Chance(99, 0), GatherWorld.Chance(100, 0) }, { 100, 75, 75, 25, 25, 0 })
    T.eq(GatherWorld.Chance(60, 1, true), 50, "an elite corpse doubles the chance")
    local function rate(skill)
        local p = scene(HERB, skill, { seed = 3 })
        local ups = 0
        for _ = 1, 400 do
            p.rank = skill
            local _, info = GatherWorld.Harvest(HERB, src(LOW))
            if info.up then ups = ups + 1 end
        end
        World.finish()
        return ups
    end
    T.eq(rate(10), 400, "orange: every harvest")
    local yellow, green = rate(30), rate(60)
    T.ok(yellow > 270 and yellow < 330, "yellow near 75%: " .. yellow)
    T.ok(green > 70 and green < 130, "green near 25%: " .. green)
    T.eq(rate(150), 0, "grey: never")
    T.eq(rate(30), yellow, "the same seed gives the same rolls")
end)

T.test("a skill-up fires the skill events and stops at the cap", function()
    local p = scene(HERB, 10, { max = 11 })
    local heard = listen()
    GatherWorld.Harvest(HERB, src(LOW))
    T.eq(p.rank, 11)
    local events = {}
    for _, h in ipairs(heard) do events[#events + 1] = h.event end
    T.eq(table.concat(events, ","), "BAG_UPDATE_DELAYED,BAG_UPDATE_DELAYED,CHAT_MSG_SKILL,SKILL_LINES_CHANGED")
    local _, info = GatherWorld.Harvest(HERB, src(LOW))
    T.eq({ p.rank, info.up }, { 11, false }, "no point past the cap")
end)

T.test("a corpse needs the classic skill for its level; a creature far above the character is left", function()
    T.eq({ GatherWorld.CorpseSkill(5), GatherWorld.CorpseSkill(15), GatherWorld.CorpseSkill(40) }, { 1, 50, 200 })
    scene(SKIN, 40, { level = 20 })
    local ok, _, code, need = GatherWorld.Harvest(SKIN, src(BOAR))
    T.eq({ ok, code, need }, { false, "skill", 50 })
    World.finish()
    local p = scene(SKIN, 300, { zone = DUROTAR, level = 35 })
    ok, _, code = GatherWorld.Harvest(SKIN, src(BRUTE))
    T.eq({ ok, code }, { false, "danger" }, "level 40 against level 35 is DANGER levels")
    T.eq(GatherWorld.state.dangerous, 1)
    T.eq(p.rank, 300)
    MapWorld.SetLevel(36)
    T.ok((GatherWorld.Harvest(SKIN, src(BRUTE))), "four levels above is fair game")
end)

T.test("finds come from the zone the character stands in, by spawn weight", function()
    scene(HERB, 1)
    local seen = { [LOW] = 0, [HIGH] = 0 }
    for _ = 1, 400 do
        local s = GatherWorld.Find(HERB)
        seen[s.entry] = seen[s.entry] + 1
    end
    T.ok(seen[LOW] > 260 and seen[LOW] < 340, "30 of 40 spawns: " .. seen[LOW])
    MapWorld.Move(DUROTAR, 0.5, 0.5)
    local s, why = GatherWorld.Find(HERB)
    T.eq(s, nil, "no herbs in this zone")
    T.ok(why:find("Durotar"), why)
end)

T.test("a cast lands against the zone's base skill and gives fishing skill by the classic rule", function()
    T.eq({ GatherWorld.Land(1, -70), GatherWorld.Land(50, 100), GatherWorld.Land(300, 200) }, { 76, 0, 100 })
    T.eq({ GatherWorld.FishChance(74), GatherWorld.FishChance(75), GatherWorld.FishChance(100),
           GatherWorld.FishChance(275) }, { 100, 100, 50, 11 })
    local p = scene(FISH, 1)
    local landed, ups = 0, 0
    for _ = 1, 200 do
        p.rank = 1
        local ok, info = GatherWorld.Cast()
        if ok then
            landed = landed + 1
            if info.up then ups = ups + 1 end
        end
    end
    T.ok(landed > 130 and landed < 175, "76% at skill 1 in base -70 water: " .. landed)
    T.eq(GatherWorld.state.landed, landed)
    T.eq(ups, landed, "below 75 every landed fish gives a point")
    T.eq(CraftWorld.Bag(FISH_ITEM), landed, "each landed fish reaches the bags")
    World.finish()
    p = scene(FISH, 100, { zone = DUROTAR })
    local heard = listen()
    local ok, why = GatherWorld.Cast()
    T.eq({ ok, why }, { false, "escaped" }, "base 200 water at skill 100 lands nothing (the sub-area's)")
    T.eq(heard[1] and heard[1][2], GatherWorld.ESCAPED)
    World.finish()
    scene(FISH, 100, { zone = 1426 })
    local _, _, code = GatherWorld.Cast()
    T.eq(code, "water", "no water in the truth: the cast is refused")
end)

T.test("ProfLost's waypoint lands in the world through C_Map.SetUserWaypoint", function()
    scene(HERB, 1)
    CP.Waypoint.PlaceOnMap(DUROTAR, 0.25, 0.75, "Test")
    T.eq(GatherWorld.Waypoint(), { zone = DUROTAR, x = 0.25, y = 0.75 })
end)
