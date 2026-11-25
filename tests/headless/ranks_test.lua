-- Profession ranks (2026-11-14): every crafting profession's Journeyman, Expert and Artisan
-- rank is a guide stop. It rides a trainer visit between its learn skill and its cap, else
-- sits at the cap, where the player needs it (tester, 2026-11-18). A skill that has opened a rank the level can't train says so.
-- Owner's report: Leatherworking 125/150 never showed "Train Expert Leatherworking".

local CP = ProfLost
local G, Q = CP.Guide, CP.Queue
local LW = 165

local CRAFTING = { 164, 165, 171, 197, 202, 333 }
-- Rank, learn skill, cap it lifts past, player level (from the trainers' rows).
local TRAINER_RANKS = { { "Journeyman", 50, 75, 10 }, { "Expert", 125, 150, 20 }, { "Artisan", 200, 225, 35 } }

local function rankNamed(guide, name)
    for _, rank in ipairs(guide.ranks or {}) do
        if rank.name == name then return rank end
    end
end

local function rowIndex(rows, test)
    for i, row in ipairs(rows) do
        if test(row) then return i end
    end
end

-- The guide window on profession `line` at `skill` / `max`, its rows and step card.
local function open(line, skill, max, level)
    MapWorld.begin({ zone = 1411, level = level or 40, side = "Horde" })
    CraftWorld.begin({ professions = { [line] = { rank = skill, max = max } } })
    CraftWorld.Open(line)
    T.advance(0.5)
    CP.Panel.tabs.guide.button:GetScript("OnClick")()
    return CP.GuideTab.ui.rows, CP.GuideTab.ui.details
end

-- The owner's bug ------------------------------------------------------------------------

T.test("Leatherworking 125 with cap 150 shows Train Expert Leatherworking before the cap", function()
    local rows = open(LW, 125, 150)
    local train = rowIndex(rows, function(r) return r.rank and r.rank.name == "Expert Leatherworking" end)
    T.ok(train ~= nil, "a Train Expert Leatherworking row")
    local past = rowIndex(rows, function(r) return r.spell and not r.rank and r.to > 150 end)
    T.ok(past ~= nil and train < past, "before every step past 150")
    T.eq(select(1, G.StopText(rows[train])), "Train Expert Leatherworking")
    local _, line = G.StopText(rows[train])
    T.ok(line:find("Visit a trainer at skill 125 to train past 150", 1, true) ~= nil, line)
    T.ok(line:find("level 20", 1, true) ~= nil, "says the level it needs: " .. line)
    T.eq(select(2, G.WaypointFor(rows[train])), "trainer")
    CraftWorld.Close()
end)

-- Tester, 2026-11-18: "put the skill upgrade step at where it's needed". With no trainer
-- visit on the way, the rank sits at the cap, between the two parts of the step through it.
T.test("below the cap, the rank sits at the cap, between the parts of the step through it", function()
    local rows = open(LW, 140, 150)
    local train = rowIndex(rows, function(r) return r.rank and r.rank.name == "Expert Leatherworking" end)
    local past = rowIndex(rows, function(r) return r.spell and not r.rank and not r.side and r.to > 150 end)
    T.ok(train ~= nil and past ~= nil and train < past, "the rank before the step past 150")
    T.eq(rows[past].from, 150, "the step past 150 starts at the cap")
    T.eq(rows[past].crafts, G.Crafts(rows[past].recipe, rows[past].from, rows[past].to), "its crafts count to its end")
    local before = rows[train - 1]
    T.ok(before and before.spell and before.to == 150, "right after the step that reaches 150")
    for i = 1, train - 1 do
        T.ok(not rows[i].spell or rows[i].to <= 150, "nothing before the rank climbs past the cap")
    end
    CraftWorld.Close()
end)

T.test("Enchanting 53: Enchant Chest - Inferior Stamina is cut at 75, Train Journeyman between", function()
    local rows = open(333, 53, 75)
    T.ok(not rows[1].rank, "the first row is a craft, not the rank")
    local train = rowIndex(rows, function(r) return r.rank and r.rank.name == "Journeyman Enchanting" end)
    T.ok(train ~= nil and train > 1, "the rank comes later")
    local prev, next = rows[train - 1], rows[train + 1]
    T.ok(prev and prev.spell and prev.to == 75, "after the part up to 75")
    T.ok(next and next.spell and next.from == 75, "before the part from 75")
    T.eq(rows[train].at, 75, "shown at 75")
    CraftWorld.Close()
end)

T.test("at the cap without the rank, the step card says so and offers no craft", function()
    local rows, d = open(LW, 150, 150)
    T.ok(rows[1].rank ~= nil, "first row is the rank")
    T.eq(rows[1].rank.name, "Expert Leatherworking")
    T.ok(rows[1].capped, "marked as what holds the player")
    T.eq(d.title:GetText(), "Train Expert Leatherworking")
    T.ok(tostring(d.status:GetText()):find("Skill capped at 150", 1, true) ~= nil, tostring(d.status:GetText()))
    for _, b in ipairs({ d.craftOne, d.craftAvail, d.craftAll }) do
        T.ok(not CP.Style.IsOn(b), "craft buttons off")
    end
    CraftWorld.Close()
end)

T.test("at the cap, the next step everywhere else is the rank", function()
    local guide = CP.Guides[LW]
    local plan = { { spell = 3780, from = 150, to = 154, crafts = 4, cost = 0 } }
    local st = CP.Gather.NextStep(guide, { skill = 150, max = 150 }, plan, {})
    T.ok(st and st.rank, "the rank")
    T.eq(st.rank.name, "Expert Leatherworking")
    T.eq(st.short, 0)
    st = CP.Gather.NextStep(guide, { skill = 150, max = 225 }, plan, {})
    T.eq(st.spell, 3780, "trained: the craft again")
    T.eq(G.CapRank(guide, 149, 150), nil, "below the cap: nothing holds")
    T.eq(G.CapRank(guide, 300, 300), nil, "maxed")
end)

T.test("the All view's card names the rank and has no craft button at the cap", function()
    open(LW, 150, 150)
    local live = CP.Plan.Current()
    local card = CP.GuideTab.Card(live)
    T.eq(card.step, "Train Expert Leatherworking")
    T.eq(card.need, "Skill capped at 150")
    T.eq(card.spell, nil, "nothing to craft")
    CraftWorld.Close()
end)

-- Every profession, every rank -----------------------------------------------------------

T.test("each crafting profession trains Journeyman 50, Expert 125 and Artisan 200", function()
    for _, line in ipairs(CRAFTING) do
        local guide = CP.Guides[line]
        T.eq(#guide.ranks, 3, guide.name)
        for i, want in ipairs(TRAINER_RANKS) do
            local rank = guide.ranks[i]
            local label = guide.name .. " " .. want[1]
            T.eq(rank.name, want[1] .. " " .. guide.name, label)
            T.eq({ rank.kind, rank.skill, rank.cap }, { "trainer", want[2], want[3] }, label)
            T.ok((rank.fee or 0) > 0, label .. " has a fee")
            T.ok(#rank.npcs > 0, label .. " has trainers")
            for _, n in ipairs(rank.npcs) do T.ok(guide.npcs[n] ~= nil, label .. " trainer " .. n .. " has a spawn") end
            -- Tailoring's Artisan trainers name no level in the server data.
            if rank.level or not (line == 197 and want[1] == "Artisan") then
                T.eq(rank.level, want[4], label .. " level")
            end
        end
    end
end)

T.test("Cooking and First Aid: Journeyman trainer, Expert book, Artisan quest", function()
    for _, line in ipairs({ 185, 129 }) do
        local guide = CP.Guides[line]
        local kinds = {}
        for _, rank in ipairs(guide.ranks) do
            kinds[#kinds + 1] = ("%s %d %d"):format(rank.kind or "book", rank.skill, rank.cap)
        end
        T.eq(table.concat(kinds, ", "), "trainer 50 75, book 125 150, quest 225 225", guide.name)
        T.ok(#guide.ranks[1].npcs > 0, guide.name .. " Journeyman trainers")
    end
    T.eq(CP.Guides[129].ranks[1].name, "Journeyman First Aid")
end)

-- Each cap: which ranks are pending and where they sit. A rank that rides an earlier trainer
-- visit cuts no step at its cap (SPLITROW-01).
T.test("every profession's pending ranks follow the cap, each trainable at the start of its step", function()
    for line, guide in pairs(CP.Guides) do
        for _, max in ipairs({ 75, 150, 225, 300 }) do
            local skill = max == 75 and 1 or max - 75
            local plan = CP.Plan.Offline(guide, "ranks" .. line, skill, max, {}).plan
            CP.charDB.lastPlan["ranks" .. line] = nil
            local pending = G.PendingRanks(guide, max, plan)
            local want = 0
            for _, rank in ipairs(guide.ranks) do if rank.cap >= max then want = want + 1 end end
            T.eq(#pending, want, ("%s at cap %d"):format(guide.name, max))
            local visits = G.TrainStops(guide, plan, {}, skill, {})
            for _, p in ipairs(pending) do
                local label = ("%s %s"):format(guide.name, p.rank.name)

                -- Nothing before the rank climbs past its cap; the step after it starts at the cap,
                -- unless the rank rides a visit before it.
                for i = 1, p.before - 1 do
                    T.ok(plan[i].to <= p.rank.cap, ("%s: %d-%d before it"):format(label, plan[i].from, plan[i].to))
                end
                local st = plan[p.before]
                if not G.RankVisit(p, visits) then
                    T.ok(st.from >= p.rank.cap, ("%s before %d-%d"):format(label, st.from, st.to))
                end
            end
        end
    end
end)

T.test("a trainer rank shares the trainer visit at its learn skill", function()
    local guide = CP.Guides[LW]
    local steps = { { spell = 3818, from = 120, to = 125, crafts = 5 }, { spell = 3818, from = 125, to = 143, crafts = 25 },
                    { spell = 3780, from = 143, to = 150, crafts = 9 }, { spell = 3780, from = 150, to = 154, crafts = 5 } }
    local pending = G.PendingRanks(guide, 150, steps)
    T.eq(pending[1].rank.name, "Expert Leatherworking")
    T.eq(pending[1].before, 4, "on its own: at the start of the step past 150")
    local rows = G.WithStops(guide, steps, {}, 120, 150)
    local i = rowIndex(rows, function(r) return r.rank ~= nil end)
    T.eq(rows[i].at, 125, "joins the visit at 125")
    T.ok(rows[i - 1].spell == 3818 and rows[i - 1].to == 125, "right after the step up to 125")
    T.ok(rows[i + 1].train ~= nil, "the rank comes before the recipes trained there")
end)

T.test("a visit at or past the cap is not the rank's: the step through the cap is drawn cut there", function()
    local guide = CP.Guides[LW]

    -- Barbaric Shoulders (7151) is taught at 150, so its visit sits past the cap. A saved step
    -- through 150 (SPLITROW-01) draws as two rows with the rank between.
    local steps = { { spell = 3764, from = 130, to = 154, crafts = 30 }, { spell = 7151, from = 154, to = 160, crafts = 6 } }
    local rows = G.WithStops(guide, steps, { [3764] = true }, 130, 150)
    local i = rowIndex(rows, function(r) return r.rank ~= nil end)
    T.eq(i, 2, "after the part up to 150")
    T.eq(rows[i].at, 150)
    T.ok(rows[i - 1].spell == 3764 and rows[i - 1].from == 130 and rows[i - 1].to == 150, "the part up to 150")
    T.ok(rows[i + 1].spell == 3764 and rows[i + 1].from == 150 and rows[i + 1].to == 154, "then the part past it")
    T.eq(rows[i - 1].crafts + rows[i + 1].crafts, 30, "the parts share the step's crafts")
    T.ok(rowIndex(rows, function(r) return r.train ~= nil end) > i + 1, "the visit at 154 comes later")
end)

T.test("with no visit on the way, the rank waits at the cap, never before a step that ends there", function()
    local guide = CP.Guides[LW]
    local all = setmetatable({}, { __index = function() return true end })

    -- No trainer visit: the steps reach 150 and stop there, so the rank sits after them.
    local steps = { { spell = 3764, from = 120, to = 143, crafts = 30 }, { spell = 3780, from = 143, to = 150, crafts = 9 },
                    { spell = 3780, from = 150, to = 154, crafts = 5 } }
    T.eq(G.SplitAtCaps(guide, steps, 150), steps, "a step ending at the cap needs no cut")
    local rows = G.WithStops(guide, steps, all, 120, 150)
    local i = rowIndex(rows, function(r) return r.rank ~= nil end)
    T.eq(i, 3, "after the step up to 150")
    T.eq({ rows[i].at, rows[i + 1].from, rows[i + 1].to }, { 150, 150, 154 })

    -- One step from below 125 through 150: cut at 150, the rank between the parts.
    steps = G.SplitAtCaps(guide, { { spell = 3764, from = 120, to = 154, crafts = 40, cost = 4000 } }, 150)
    T.eq({ steps[1].from, steps[1].to, steps[2].from, steps[2].to }, { 120, 150, 150, 154 })
    rows = G.WithStops(guide, steps, all, 120, 150)
    i = rowIndex(rows, function(r) return r.rank ~= nil end)
    T.eq(i, 2, "after the part up to 150")
    T.eq({ rows[i].at, rows[i + 1].from, rows[i + 1].to }, { 150, 150, 154 })
end)

T.test("SplitAtCaps cuts every step through a cap still to train at the cap", function()
    local guide = CP.Guides[LW]
    local steps = { { spell = 3780, from = 145, to = 154, crafts = 12, cost = 1200 } }
    T.eq(G.SplitAtCaps(guide, steps, 225), steps, "trained past 150: whole")
    local out = G.SplitAtCaps(guide, steps, 150)
    T.eq(#out, 2, "starts past 125: still cut at 150")
    T.eq({ out[1].from, out[1].to, out[2].from, out[2].to }, { 145, 150, 150, 154 })
    steps = { { spell = 3764, from = 120, to = 154, crafts = 40, cost = 4000 } }
    out = G.SplitAtCaps(guide, steps, 150)
    T.eq(#out, 2, "starts below 125: cut at 150")
    T.eq(out[1].crafts, G.Crafts(guide.recipes[3764], 120, 150))
    T.eq(out[1].cost, 4000 * out[1].crafts / 40)
    T.eq(out[2].crafts, G.Crafts(guide.recipes[3764], 150, 154))
end)

T.test("the queue through the cap holds the rank and its fee first", function()
    local guide = CP.Guides[LW]
    local steps = G.SplitAtCaps(guide, { { spell = 3780, from = 145, to = 154, crafts = 12, cost = 0 } }, 150)
    local q = Q.Build(guide, 145, 150, 154, steps)
    local kinds = {}
    for _, e in ipairs(q) do kinds[#kinds + 1] = e.kind end
    T.eq(table.concat(kinds, " "), "craft rank craft")
    local _, _, training = Q.Cost(guide, q, {}, function() return 0 end)
    T.eq(training, rankNamed(guide, "Expert Leatherworking").fee)
end)

-- Level warning ---------------------------------------------------------------------------

T.test("a rank the skill has opened but the level can't train says so", function()
    local guide = CP.Guides[LW]
    local expert = rankNamed(guide, "Expert Leatherworking")
    local steps = { { spell = 3780, from = 130, to = 154, crafts = 30 } }
    local all = setmetatable({}, { __index = function() return true end })
    local function rankRow(rows) return rows[rowIndex(rows, function(r) return r.rank ~= nil end)] end
    local row = rankRow(G.WithStops(guide, steps, all, 130, 150, 18))
    T.eq(row.rank, expert)
    T.eq(row.levelShort, { need = 20, have = 18, text = "Expert Leatherworking needs level 20 (you're 18)" })
    local _, line = G.StopText(row)
    T.ok(line:find("Expert Leatherworking needs level 20 (you're 18).", 1, true) == 1, line)
    T.eq(rankRow(G.WithStops(guide, steps, all, 130, 150, 20)).levelShort, nil, "level 20: nothing to say")
    T.eq(G.LevelShort(expert, 124, 18), nil, "skill below 125: not open yet")
    T.eq(G.LevelShort(expert, 125, 18).need, 20, "open at 125")
    T.eq(G.LevelShortFor(guide, 130, 150, 18).need, 20)
    T.eq(G.LevelShortFor(guide, 130, 225, 18), nil, "trained: nothing")
end)

T.test("the level warning reaches the step card and the next step", function()
    local rows, d = open(LW, 150, 150, 18)
    T.eq(rows[1].levelShort and rows[1].levelShort.have, 18)
    local status = tostring(d.status:GetText())
    T.ok(status:find("Skill capped at 150. Expert Leatherworking needs level 20 (you're 18).", 1, true) == 1, status)
    CraftWorld.Close()

    local guide = CP.Guides[LW]
    MapWorld.begin({ level = 18 })
    local plan = { { spell = 3780, from = 150, to = 154, crafts = 4, cost = 0 } }
    local st = CP.Gather.NextStep(guide, { skill = 150, max = 150 }, plan, {})
    T.eq(st.levelShort and st.levelShort.text, "Expert Leatherworking needs level 20 (you're 18)", "at the cap")
    plan = { { spell = 3780, from = 140, to = 154, crafts = 14, cost = 0 } }
    st = CP.Gather.NextStep(guide, { skill = 140, max = 150 }, plan, {})
    T.eq(st.spell, 3780)
    T.eq(st.levelShort and st.levelShort.need, 20, "below the cap, past 125")
    MapWorld.SetLevel(20)
    T.eq(CP.Gather.NextStep(guide, { skill = 140, max = 150 }, plan, {}).levelShort, nil, "level 20: none")
end)
