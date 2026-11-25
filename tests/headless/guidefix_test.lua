-- Guide audit fixes (2026-11-12): faction-gated patterns, trainer and quest rank stops,
-- per-unit cost of a maker that makes two, and the acquisition data the generator keeps.

local CP = ProfLost
local G = CP.Guide
local Q = CP.Queue
local alchemy, cooking, firstAid, engineering = CP.Guides[171], CP.Guides[185], CP.Guides[129], CP.Guides[202]

local DREAMLESS = 24366   -- Greater Dreamless Sleep Potion, Zandalar Tribe Friendly

-- Runs `fn` with the game reporting `reaction` with every faction (nil: the API answers
-- without a reaction, as when the faction is not met yet).
local function withReaction(reaction, fn)
    World.patch("C_Reputation.GetFactionDataByID", function(id)
        return { factionID = id, name = id == 270 and "Zandalar Tribe" or "Faction", reaction = reaction }
    end)
    local ok, err = pcall(fn)
    T.ok(ok, err)
end

-- The live plan from `skill` in Buy-and-power-level or Level-as-you-go.
local function plan(guide, skill, collect, learned)
    local saved = CP.db.collect
    CP.db.collect = collect
    local key = "guidefix" .. guide.name .. skill .. tostring(collect)
    local steps = CP.Plan.Offline(guide, key, skill, 300, learned or {}).plan
    CP.charDB.lastPlan[key] = nil
    -- A fresh plan each time, not the one committed by an earlier call (Plan.Commit).
    if CP.charDB.committed then CP.charDB.committed[key] = nil end
    CP.db.collect = saved
    return steps
end

local function uses(steps, spell)
    for _, st in ipairs(steps) do
        if st.spell == spell then return true end
    end
    return false
end

local function ends(steps)
    local last = steps[#steps]
    for _, st in ipairs(steps) do T.ok(st.spell ~= nil, "no gap at " .. st.from) end
    return last and last.to
end

-- Faction-gated patterns -------------------------------------------------------

T.test("Greater Dreamless Sleep carries its faction and standing", function()
    local r = alchemy.recipes[DREAMLESS]
    T.eq(r.src, "vendor")
    T.eq(r.pattern, 20012)
    T.eq(r.faction, 270)
    T.eq(r.standing, 5, "ItemSparse MinReputation 4 is reaction 5, Friendly")
    T.eq(alchemy.factions[270], "Zandalar Tribe")
end)

T.test("no stored guide step leans on a faction-gated pattern", function()
    for _, g in pairs(CP.Guides) do
        for _, st in ipairs(g.steps) do
            local r = st.spell and g.recipes[st.spell]
            T.ok(not (r and r.faction), ("%s %d-%d: %s"):format(g.name, st.from, st.to, r and r.name or "-"))
        end
    end
end)

T.test("below the standing, the gated pattern is never the main step, in either mode", function()
    withReaction(4, function()
        T.eq(G.HasStanding(alchemy.recipes[DREAMLESS]), false)
        T.ok(CP.Plan.Locked(DREAMLESS, alchemy.recipes[DREAMLESS]))
        for _, collect in ipairs({ false, true }) do
            local steps = plan(alchemy, 265, collect)
            T.ok(not uses(steps, DREAMLESS), "collect " .. tostring(collect))
            T.eq(ends(steps), 300, "something else covers 290-300")
        end
    end)
end)

T.test("at the standing, the gated pattern can lead again", function()
    withReaction(5, function()
        T.eq(G.HasStanding(alchemy.recipes[DREAMLESS]), true)
        T.ok(not CP.Plan.Locked(DREAMLESS, alchemy.recipes[DREAMLESS]))
        T.ok(uses(plan(alchemy, 265, false), DREAMLESS), "buy mode plans it at 297-300")
    end)
end)

T.test("a learned gated recipe stays usable whatever the standing", function()
    withReaction(4, function()
        local only = function(id) return id == DREAMLESS end
        local opts = { locked = CP.Plan.Locked }
        local price = function() return 100 end
        local unlearned = CP.Solver.Plan(alchemy, 290, {}, price, only, nil, nil, opts)
        T.ok(not uses(unlearned, DREAMLESS), "locked and unlearned: never planned")
        local learned = CP.Solver.Plan(alchemy, 290, { [DREAMLESS] = true }, price, only, nil, nil, opts)
        T.eq(learned[1].spell, DREAMLESS)
    end)
end)

T.test("unreadable standing keeps the recipe and names what it needs", function()
    withReaction(nil, function()
        local r = alchemy.recipes[DREAMLESS]
        T.eq(G.HasStanding(r), nil)
        T.ok(not CP.Plan.Locked(DREAMLESS, r))
        T.ok(uses(plan(alchemy, 265, false), DREAMLESS), "still planned")
        T.eq(G.StandingText(alchemy, r), "needs Zandalar Tribe Friendly")
        T.ok(G.LearnText(r, alchemy):find("needs Zandalar Tribe Friendly", 1, true) ~= nil, G.LearnText(r, alchemy))
    end)
end)

-- Rank stops -------------------------------------------------------------------

local function rankBy(guide, spell)
    for _, rank in ipairs(guide.ranks) do
        if rank.spell == spell then return rank end
    end
end

T.test("Cooking has Journeyman from a trainer and Artisan from Clamlette Surprise", function()
    local journeyman, artisan = rankBy(cooking, 3102), rankBy(cooking, 18260)
    T.eq({ journeyman.kind, journeyman.skill, journeyman.cap, journeyman.fee }, { "trainer", 50, 75, 500 })
    T.ok(#journeyman.npcs >= 10, "Cooking trainers of both factions")
    T.eq({ artisan.kind, artisan.skill, artisan.cap, artisan.quest, artisan.level }, { "quest", 225, 225, "Clamlette Surprise", 35 })
    T.eq(artisan.npcs, { 8125 })
    T.ok(cooking.npcs[8125] ~= nil, "Dirge Quikcleave has a spawn")
    for i = 2, #cooking.ranks do T.ok(cooking.ranks[i - 1].skill <= cooking.ranks[i].skill, "lowest skill first") end
end)

T.test("First Aid has Artisan from Triage, a quest per faction", function()
    local artisan = rankBy(firstAid, 10846)
    T.eq({ artisan.kind, artisan.skill, artisan.cap, artisan.quest }, { "quest", 225, 225, "Triage" })
    T.eq(artisan.quests, { 6622, 6624 })
    local sides = {}
    for _, n in ipairs(artisan.npcs) do sides[firstAid.npcs[n][2]] = true end
    T.ok(sides.A and sides.H, "a quest giver for each faction")
end)

T.test("each rank stop shows while the cap is below it, before the step that passes it", function()
    local function kinds(maxSkill)
        local out = {}
        for _, p in ipairs(G.PendingRanks(cooking, maxSkill, cooking.steps)) do
            out[#out + 1] = p.rank.kind or "book"
            T.ok(cooking.steps[p.before].to > p.rank.cap, "before the step past " .. p.rank.cap)
        end
        return table.concat(out, " ")
    end
    T.eq(kinds(75), "trainer book quest")
    T.eq(kinds(150), "book quest")
    T.eq(kinds(225), "quest")
    T.eq(kinds(300), "")
end)

T.test("rank rows say what to do and where to go", function()
    local journeyman, artisan = rankBy(cooking, 3102), rankBy(cooking, 18260)
    local name, line = G.StopText({ rank = journeyman })
    T.eq(name, "Train Journeyman Cooking")
    T.ok(line:find("Visit a trainer at skill 50 to train past 75", 1, true) ~= nil, line)
    T.eq(select(2, G.WaypointFor({ rank = journeyman })), "trainer")
    T.eq(G.RankTag(journeyman), CP.Pricing.Format(500))

    name, line = G.StopText({ rank = artisan })
    T.eq(name, "Artisan Cooking")
    T.eq(line, "Quest at skill 225 to train past 225: Clamlette Surprise  ·  level 35")
    T.eq(select(2, G.WaypointFor({ rank = artisan })), "quest giver")
    T.eq(G.RankTag(artisan), "quest")

    T.eq(select(2, G.WaypointFor({ rank = rankBy(firstAid, 10846) })), "quest giver")
    T.eq(G.RankTag(firstAid.ranks[2]), "buy", "the Expert book is still a buy")
end)

T.test("the Guide and Queue lists put the rank rows in place", function()
    local rows = G.WithStops(cooking, cooking.steps, {}, 1, 75)
    local names = {}
    for _, row in ipairs(rows) do
        if row.rank then names[#names + 1] = row.rank.name end
    end
    T.eq(names, { "Journeyman Cooking", "Expert Cookbook", "Artisan Cooking" })

    local function rankNames(q)
        local out = {}
        for _, e in ipairs(q) do if e.kind == "rank" then out[#out + 1] = e.rank.name end end
        return table.concat(out, ", ")
    end
    T.eq(rankNames(Q.Build(cooking, 40, 75, 150, cooking.steps)), "Journeyman Cooking")
    T.eq(rankNames(Q.Build(firstAid, 200, 225, 300, firstAid.steps)), "Artisan First Aid")
end)

T.test("trainer and quest ranks are never offered as vendor buys", function()
    for _, b in ipairs(G.VendorBuys(cooking, {}, 75)) do
        T.ok(b.item ~= nil, b.name)
        T.ok(b.name ~= "Journeyman Cooking" and b.name ~= "Artisan Cooking", b.name)
    end
end)

T.test("the doctors' bandages need Triage first", function()
    for _, spell in ipairs({ 10841, 18629, 18630 }) do
        local r = firstAid.recipes[spell]
        T.eq(r.after, 10846, r.name)
        T.eq(G.AfterText(firstAid, r), "after the Triage quest")
    end
    T.eq(firstAid.recipes[10840].after, nil, "Mageweave Bandage is an ordinary trainer recipe")
    local steps = { { spell = 10841, from = 247, to = 260, crafts = 17 } }
    local stops = G.TrainStops(firstAid, steps, {}, 247)
    T.eq(stops[1].after, "after the Triage quest")
    local _, line = G.StopText({ train = stops[1] })
    T.ok(line:find("after the Triage quest", 1, true) ~= nil, line)
end)

-- Per-unit cost of a maker that makes two ------------------------------------------

T.test("a two-yield maker's material costs half its batch per unit", function()
    T.eq(alchemy.recipes[7837].yield, 2, "Fire Oil makes 2")
    T.eq(alchemy.prep[6371], 7837)
    T.eq(alchemy.recipes[17551].yield, 2, "Stonescale Oil makes 2")
    T.eq(alchemy.prep[13423], 17551)

    -- Maker 1 turns 3 of item 800 (10c each) into `yield` of item 900. Recipe 2 uses one
    -- 900 (15c at yield 2, 30c at yield 1); recipe 3 uses two 801 at 8c (16c).
    local function guide(yield)
        local function recipe(name, reagents, extra)
            local r = { name = name, src = "trainer", learn = 1, yellow = 50, grey = 100, ups = 1,
                        reagents = reagents, step = true }
            for k, v in pairs(extra or {}) do r[k] = v end
            return r
        end
        return {
            name = "Yield test", steps = {}, ranks = {},
            recipes = {
                [1] = recipe("Maker", { { 800, 3 } }, { makes = 900, yield = yield, step = false }),
                [2] = recipe("Uses the made item", { { 900, 1 } }),
                [3] = recipe("Uses bought items", { { 801, 2 } }),
            },
            items = { [800] = { 10, true }, [801] = { 8, true } },
            prep = { [900] = 1 }, craftOnly = {},
        }
    end
    local price = function(item) return ({ [800] = 10, [801] = 8 })[item] end
    T.eq(CP.Solver.Plan(guide(2), 1, {}, price)[1].spell, 2, "15c per unit beats 16c")
    T.eq(CP.Solver.Plan(guide(1), 1, {}, price)[1].spell, 3, "30c per unit loses to 16c")
end)

-- Acquisition data the generator keeps -----------------------------------------------

T.test("the fuse maker keeps its schematic and favor source, and the dynamite step says so", function()
    local fuse = engineering.recipes[1266914]
    T.eq(fuse.src, "favor")
    T.eq(fuse.pattern, 264211)
    T.ok(fuse.how:find("180 Merchant's Favor", 1, true) ~= nil, fuse.how)
    T.eq(engineering.prep[260801], 1266914)
    local note = G.PrepNote(engineering, engineering.recipes[23069], {})
    T.ok(note and note:find("EZ-Thro Fireproof Fuse: Schematic for 180 Merchant's Favor", 1, true) ~= nil, note)
    T.eq(G.PrepNote(engineering, engineering.recipes[23069], { [1266914] = true }), nil, "nothing once learned")
end)

T.test("First Aid manuals keep their item and where they drop", function()
    local want = {
        [1244434] = { 255723, "Syndicate Mercenary" },
        [1259341] = { 255728, "Lost One Muckdweller" },
        [1259343] = { 255724, "Defias Enchanter" },
    }
    for spell, w in pairs(want) do
        local r = firstAid.recipes[spell]
        T.eq(r.pattern, w[1], r.name)
        T.ok(r.how and r.how:find(w[2], 1, true) ~= nil, r.name .. ": " .. tostring(r.how))
    end
end)

T.test("Elixir of Greater Defense keeps its limited stock", function()
    local r = alchemy.recipes[17554]
    T.eq(r.pattern, 13478, "Recipe: Elixir of Superior Defense teaches Elixir of Greater Defense")
    T.eq(r.limited, true)
end)

T.test("a faction the game has no data for (never met) counts as no standing: the pattern is locked", function()
    World.patch("C_Reputation.GetFactionDataByID", function() return nil end)
    local ok, err = pcall(function()
        local r = alchemy.recipes[DREAMLESS]
        T.eq(G.Standing(270), 0)
        T.eq(G.HasStanding(r), false)
        T.ok(CP.Plan.Locked(DREAMLESS, r))
        T.ok(not uses(plan(alchemy, 265, false), DREAMLESS), "off the plan")
        T.eq(G.StandingText(alchemy, r), "needs Zandalar Tribe Friendly", "named from the guide's faction list")
    end)
    T.ok(ok, err)
end)
