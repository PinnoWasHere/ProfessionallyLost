-- Limited-stock patterns: the pattern stays the main step, and its trainer alternatives
-- stand directly under it as "or" rows over the same range. A step right before it on
-- one of those recipes joins the pattern's step when the pattern gives points there,
-- and an "or" row's training folds into the visit before the step.

local CP = ProfLost
local P, G, GT = CP.Plan, CP.Guide, CP.GuideTab
local LW = 165
local DUSKY, WHELP, GUARDIAN, BELT = 9201, 9202, 7156, 3774
local CURED = 3818

-- Runs `fn` with Plan.Alternatives answering `spells` (in order), whatever the step.
local function withAlts(spells, fn)
    local saved = P.Alternatives
    P.Alternatives = function(live, step)
        local out = {}
        for _, id in ipairs(spells) do
            if id ~= step.spell then
                out[#out + 1] = { spell = id, recipe = live.guide.recipes[id], learned = live.learned[id] == true }
            end
        end
        return out
    end
    local ok, err = pcall(fn)
    P.Alternatives = saved
    T.ok(ok, err)
end

local function lwLive(plan, learned, skill)
    local recipes = {}
    for id in pairs(learned) do recipes[#recipes + 1] = { id = id, learned = true, craftable = 0 } end
    return { guide = CP.Guides[LW], learned = learned, recipes = recipes, plan = plan, sides = {}, alias = {},
             dead = {}, prof = { id = LW, skill = skill, max = 225 } }
end

local function step(spell, from, to)
    return { spell = spell, from = from, to = to, crafts = to - from, cost = 0 }
end

local function texts(rows)
    local out = {}
    for _, row in ipairs(rows) do
        local range, name = GT.RowTexts(row)
        out[#out + 1] = (row.side and "or " or "") .. range .. " " .. name
    end
    return table.concat(out, " / ")
end

T.test("Green Whelp Bracers keeps the main row; Guardian Gloves and Dusky Bracers are 'or' rows under it", function()
    T.eq(CP.Guides[LW].recipes[WHELP].limited, true, "the guide marks it limited")
    withAlts({ GUARDIAN, DUSKY }, function()
        local live = lwLive({ step(DUSKY, 160, 165), step(WHELP, 165, 175), step(GUARDIAN, 175, 197) },
            { [DUSKY] = true }, 160)
        P.AddFallbacks(live)
        local rows = GT.RowsOf(live)
        local s = texts(rows)
        -- The pattern can't be learned below 165, so Dusky Bracers keeps 160-165. Guardian Gloves
        -- needs Cured Heavy Hide, trained before the step its "or" row stands under.
        T.ok(s:find("160-165 Dusky Bracers / 165 Train Cured Heavy Hide / 165-175 Green Whelp Bracers / or  Guardian Gloves / or  Dusky Bracers", 1, true), s)
        local main
        for _, row in ipairs(rows) do if row.spell == WHELP then main = row end end
        T.eq(P.AlternativesText(live, main), P.LIMITED_ORS, "the card points at the rows, naming nothing twice")
        local keys = {}
        for _, row in ipairs(rows) do
            T.ok(not keys[row.key], "unique row key " .. tostring(row.key))
            keys[row.key] = true
            if row.side then
                T.eq(row.from, 165)
                T.eq(row.to, 175, "an 'or' row covers the pattern's range")
                T.eq(row.limited, true)
            end
        end
    end)
end)

T.test("a step right before the pattern on an 'or' recipe joins the pattern's step", function()
    withAlts({ DUSKY, GUARDIAN }, function()
        local live = lwLive({ step(BELT, 160, 167), step(DUSKY, 167, 170), step(WHELP, 170, 178), step(GUARDIAN, 178, 197) },
            { [DUSKY] = true, [BELT] = true }, 160)
        P.AddFallbacks(live)
        local s = texts(GT.RowsOf(live))
        T.ok(s:find("160-167 Green Leather Belt / 167-178 Green Whelp Bracers / or  Dusky Bracers / or  Guardian Gloves", 1, true), s)
        T.ok(not s:find("167-170 Dusky", 1, true), "Dusky Bracers isn't its own step too")
        T.eq(live.plan[2].crafts, G.Crafts(CP.Guides[LW].recipes[WHELP], 167, 178), "crafts counted again")
    end)
end)

T.test("a step below the pattern's learn skill stays: the plan needs it there", function()
    withAlts({ DUSKY }, function()
        local live = lwLive({ step(DUSKY, 160, 165), step(WHELP, 165, 175) }, { [DUSKY] = true }, 160)
        P.AddFallbacks(live)
        T.eq(#live.plan, 2)
        T.eq(live.plan[1].spell, DUSKY)
        T.eq(live.sides[2].spell, DUSKY)
    end)
end)

T.test("an 'or' row's training folds into the visit before the step, else the row says trainer", function()
    withAlts({ DUSKY, GUARDIAN }, function()
        -- Green Leather Belt is trained at 165; Dusky Bracers (learn 160) can be trained then too.
        -- Cured Heavy Hide is known, so the hides the steps make train nothing.
        local live = lwLive({ step(BELT, 165, 168), step(WHELP, 168, 178) }, { [CURED] = true }, 165)
        P.AddFallbacks(live)
        local rows = GT.RowsOf(live)
        local visit
        for _, row in ipairs(rows) do if row.train then visit = row.train end end
        T.ok(visit ~= nil, texts(rows))
        local names = {}
        for _, r in ipairs(visit.recipes) do names[#names + 1] = r.name end
        T.eq(table.concat(names, ", "), "Green Leather Belt, Dusky Bracers, Guardian Gloves")
        local r = CP.Guides[LW].recipes
        T.eq(visit.fee, r[BELT].fee + r[DUSKY].fee + r[GUARDIAN].fee)

        -- No visit at or below the step: nothing to fold into.
        live = lwLive({ step(WHELP, 165, 175) }, { [CURED] = true }, 165)
        P.AddFallbacks(live)
        rows = GT.RowsOf(live)
        for _, row in ipairs(rows) do
            T.ok(not row.train, "no visit made up for an 'or' row")
            if row.side then T.eq(select(3, GT.RowTexts(row)), "trainer") end
        end
    end)
end)

T.test("joining never crosses a rank's cap from below its learn skill", function()
    local guide = {
        name = "Test", ranks = { { skill = 125, cap = 150, kind = "trainer", name = "Expert Test", fee = 0 } },
        recipes = {
            [1] = { name = "Trained", src = "trainer", learn = 100, yellow = 160, grey = 200, reagents = {} },
            [2] = { name = "Limited", src = "vendor", limited = true, pattern = 99, learn = 100, yellow = 160, grey = 200,
                    reagents = {} },
        },
    }
    withAlts({ 1 }, function()
        local plan = { step(1, 120, 130), step(2, 130, 160) }
        local out = P.LimitedOrs({ guide = guide, learned = { [1] = true }, prof = { max = 150 } }, plan)
        T.eq(#out, 2, "120-130 stays: joining would cross 150 from below 125")
        out = P.LimitedOrs({ guide = guide, learned = { [1] = true }, prof = { max = 225 } }, plan)
        T.eq(#out, 1, "past the rank: joined")
        T.eq(out[1].from, 120)
    end)
end)

-- Decision 0008 rule 9: a join never changes what a maker was sized for. Item 50 is prep, made by
-- recipe 3.
local function madeUpGuide(trained, limited)
    return {
        name = "Test", ranks = {}, prep = { [50] = 3 },
        recipes = {
            [1] = { name = "Trained", src = "trainer", learn = 100, yellow = 160, grey = 200, reagents = trained.reagents or {},
                    makes = trained.makes },
            [2] = { name = "Limited", src = "vendor", limited = true, pattern = 99, learn = 100, yellow = 160, grey = 200,
                    reagents = limited.reagents or {} },
            [3] = { name = "Maker", src = "trainer", learn = 1, yellow = 100, grey = 200, reagents = {}, makes = 50 },
        },
    }
end

T.test("rule 9: a join is refused when the joined step uses more of a prep material", function()
    local guide = madeUpGuide({}, { reagents = { { 50, 1 } } })
    withAlts({ 1 }, function()
        local out, ors = P.LimitedOrs({ guide = guide, learned = { [1] = true }, prof = { max = 225 } },
            { step(1, 120, 130), step(2, 130, 160) })
        T.eq(#out, 2, "both steps stay")
        T.eq(out[2].from, 130, "the pattern keeps its own range")
        T.ok(ors[2] and #ors[2] > 0, "the pattern keeps its 'or' rows")
    end)
end)

T.test("rule 9: a join is refused when the step it would take in is a maker", function()
    local guide = madeUpGuide({ makes = 50 }, {})
    withAlts({ 1 }, function()
        local out = P.LimitedOrs({ guide = guide, learned = { [1] = true }, prof = { max = 225 } },
            { step(1, 120, 130), step(2, 130, 160) })
        T.eq(#out, 2, "the maker's step stays")
    end)
end)

T.test("rule 9: a join that uses no more of a prep material is kept", function()
    local guide = madeUpGuide({ reagents = { { 50, 2 } } }, { reagents = { { 50, 1 } } })
    withAlts({ 1 }, function()
        local out = P.LimitedOrs({ guide = guide, learned = { [1] = true }, prof = { max = 225 } },
            { step(1, 120, 130), step(2, 130, 160) })
        T.eq(#out, 1, "joined: 2 per craft in, 1 per craft out")
        T.eq(out[1].from, 120)
        guide = madeUpGuide({}, {})
        out = P.LimitedOrs({ guide = guide, learned = { [1] = true }, prof = { max = 225 } },
            { step(1, 120, 130), step(2, 130, 160) })
        T.eq(#out, 1, "joined: no made material")
    end)
end)

T.test("every guide: limited pattern steps carry their trainer alternatives as 'or' rows", function()
    local saved = CP.db.collect
    CP.db.collect = false
    local total = 0
    for key, guide in pairs(CP.Guides) do
        local live = P.Offline(guide, "limitedor" .. key, 1, 300, {})
        live.sides, live.alias, live.dead, live.recipes = {}, {}, {}, {}
        P.AddFallbacks(live)
        for i, st in ipairs(live.plan) do
            local r = st.spell and guide.recipes[st.spell]
            if r and r.limited and r.pattern then
                local shown = {}
                local side = live.sides[i]
                for _, s in ipairs(side and { side, unpack(side.more or {}) } or {}) do
                    T.ok(s.spell ~= st.spell, "never the step itself")
                    T.ok(s.limited, "marked limited")
                    shown[s.spell] = true
                    total = total + 1
                end
                -- Each known or trainer recipe the plan would use instead stands as an "or" row.
                for _, alt in ipairs(P.Alternatives(live, { spell = st.spell, recipe = r, from = st.from, to = st.to }, true)) do
                    local lo, upto = math.max(st.from, alt.recipe.learn), math.min(st.to, alt.recipe.grey)
                    if lo < upto and G.Crafts(alt.recipe, lo, upto) < math.huge then
                        T.ok(shown[alt.spell], guide.name .. ": " .. alt.recipe.name .. " is an 'or' row under " .. r.name)
                    end
                end
                local text = P.AlternativesText(live, { spell = st.spell, recipe = r, from = st.from, to = st.to, planIndex = i })
                T.ok(text and not text:find("(trainer)", 1, true), text)
            end
        end
    end
    CP.db.collect = saved
    T.ok(total > 0, "some guide has limited 'or' rows")
end)

-- Simulator finding, 2026-11-16: an Alchemist without Herbalism at 100, Holy Protection Potion
-- sold out. Herbs count as ungettable, so the main plan's herb recipes come from gap filling,
-- and the "or" rows found none: the guide stopped at 100.
T.test("a sold-out limited pattern gets the gap fillers the main plan uses as 'or' rows", function()
    local ALCHEMY, HOLY = 171, 7255
    local herb = { 7, 9, 182 }
    GatherWorld.AnswerClasses({ [2453] = herb, [2452] = herb, [2447] = herb, [765] = herb, [785] = herb,
                                [2449] = herb, [2450] = herb, [3820] = herb, [3355] = herb, [3356] = herb,
                                [3369] = herb, [3357] = herb })
    World.set(CP.db, "collect", true)
    CraftWorld.begin({ professions = { [ALCHEMY] = 100 } })
    local guide = CP.Guides[ALCHEMY]
    T.ok(not CP.Sourcing.CanGet(guide, 2453, CP.Sourcing.PlayerSkills()), "Bruiseweed counts as ungettable")
    local learned = {}
    for id, r in pairs(guide.recipes) do
        if (r.src == "trainer" or r.src == "auto") and r.learn <= 100 then learned[id] = true end
    end
    local live = { guide = guide, learned = learned, dead = {}, prof = { id = ALCHEMY, skill = 100, max = 150 } }
    local alts = P.Alternatives(live, { spell = HOLY, recipe = guide.recipes[HOLY], from = 100, to = 130 })
    T.ok(#alts > 0, "some recipe carries on over 100-130")
    for _, alt in ipairs(alts) do T.ok(alt.spell ~= HOLY, "never the sold-out recipe") end
    local _, ors = P.LimitedOrs(live, { { spell = HOLY, from = 100, to = 130, crafts = 30, cost = 0 } })
    T.ok(ors[1] ~= nil and #ors[1] > 0, "an 'or' row under Holy Protection Potion")
end)

-- Owner report, 2026-11-25: Leatherworking 155 with Skinning, Green Leather Armor (limited) on
-- 155-160 had no "or" row. The cheapest stand-in was another vendor pattern (Raptor Hide Belt),
-- which an "or" row can't be, while known and trainer recipes give points there (Frost
-- Leather Cloak, trainer, orange at 155).
-- The character's known and grey recipes are the owner's saved ones.
T.test("a limited pattern's 'or' rows come from known or trainer recipes, not another pattern", function()
    local KNOWN = { 2149, 2152, 2153, 2159, 2160, 2161, 2162, 2164, 2165, 2166, 2167, 2168, 2881, 3753, 3756, 3759,
        3760, 3761, 3763, 3764, 3766, 3768, 3770, 3774, 3780, 3816, 3817, 3818, 7126, 7135, 7147, 9058, 9059, 9060,
        9062, 9065, 9068, 9074, 9145, 9147, 9193, 9194, 20648, 20649, 23190 }
    local GREY = { 2149, 2152, 2153, 2158, 2159, 2160, 2161, 2162, 2164, 2165, 2166, 2167, 2168, 2881, 3753, 3756, 3759,
        3761, 3763, 3766, 3768, 3816, 3817, 3818, 6702, 6703, 7126, 7135, 7953, 7954, 9058, 9059, 9060, 9062, 9064,
        9065, 9068, 9070, 9072, 9074, 9145, 20648, 20649, 23190, 24940 }
    local ARMOR, SKINNING = 3772, 393
    World.set(CP.db, "collect", true)
    CraftWorld.begin({ professions = { [LW] = 155, [SKINNING] = 165 } })
    local learned, dead = {}, {}
    for _, id in ipairs(KNOWN) do learned[id] = true end
    for _, id in ipairs(GREY) do dead[id] = true end
    local live = lwLive({ step(ARMOR, 155, 160), step(DUSKY, 160, 165) }, learned, 155)
    live.dead = dead
    P.AddFallbacks(live)
    local side = live.sides[1]
    T.ok(side ~= nil, "Green Leather Armor has an 'or' row")
    local guide = CP.Guides[LW]
    for _, s in ipairs(side and { side, unpack(side.more or {}) } or {}) do
        T.ok(s.spell ~= ARMOR, "never the step itself")
        T.ok(s.learned or G.SourceWord(s.recipe) == "trainer", s.recipe.name .. " is known or trained")
        T.ok(s.lo == 155 and s.upto > 155, s.recipe.name .. " gives points from 155")
        T.ok(CP.Solver.GreenFrom(guide.recipes[s.spell]) > 155, s.recipe.name .. " is orange or yellow at 155")
    end
end)

-- Simulator finding, 2026-11-25: Engineering, Thorium Widget (limited) on 260-285 had Salt Shaker as
-- an "or" row. Salt Shaker needs a Gold Power Core, and no row trained Gold Power Core.
T.test("an 'or' row's made material is trained before the step, as a step's is", function()
    local ENG, WIDGET, SALT, DYNAMITE, CORE = 202, 19791, 19567, 23070, 12584
    local guide = CP.Guides[ENG]
    T.eq(guide.prep[10558], CORE, "Gold Power Core is made on demand")
    local function rows(learned)
        local recipes = {}
        for id in pairs(learned) do recipes[#recipes + 1] = { id = id, learned = true, craftable = 0 } end
        local live = { guide = guide, learned = learned, recipes = recipes, sides = {}, alias = {}, dead = {},
                       plan = { step(DYNAMITE, 257, 260), step(WIDGET, 260, 285) },
                       prof = { id = ENG, skill = 257, max = 300 } }
        P.AddFallbacks(live)
        return GT.RowsOf(live)
    end
    local function trains(row, id)
        for _, r in ipairs(row.train and row.train.recipes or {}) do
            if r == guide.recipes[id] then return true end
        end
        return false
    end
    withAlts({ SALT }, function()
        local list = rows({ [DYNAMITE] = true })
        local trainAt, orAt
        for i, row in ipairs(list) do
            if trains(row, CORE) then trainAt = trainAt or i end
            if row.side and row.spell == SALT then orAt = i end
        end
        T.ok(orAt ~= nil, "Salt Shaker is an 'or' row: " .. texts(list))
        T.ok(trainAt ~= nil and orAt ~= nil and trainAt < orAt, "a visit before it trains Gold Power Core: " .. texts(list))
        for _, row in ipairs(rows({ [DYNAMITE] = true, [CORE] = true })) do
            T.ok(not trains(row, CORE), "a known Gold Power Core isn't trained again")
        end
    end)
end)

-- Simulator finding, 2026-11-25: Leatherworking 250, Wicked Leather Gauntlets (limited) had Feathered
-- Breastplate as an "or" row. It needs Cured Thick Hide, whose recipe gives no points and so isn't in
-- the guide: no row could train it. The guide plans such a material from the bags only.
T.test("an 'or' row never needs a material no row can teach", function()
    local WICKED, CURED_THICK = 19049, 8172
    local guide = CP.Guides[LW]
    World.set(CP.db, "collect", true)
    CraftWorld.begin({ professions = { [LW] = 250 } })
    local learned = {}
    for id, r in pairs(guide.recipes) do
        if r.src == "trainer" and r.learn <= 250 then learned[id] = true end
    end
    local st = { spell = WICKED, recipe = guide.recipes[WICKED], from = 250, to = 265 }
    for _, alt in ipairs(P.Alternatives({ guide = guide, learned = learned, dead = {} }, st, true)) do
        for _, pair in ipairs(alt.recipe.reagents) do
            T.ok(pair[1] ~= CURED_THICK, alt.recipe.name .. " needs Cured Thick Hide")
        end
    end
    T.eq(guide.items[CURED_THICK][5], true, "Cured Thick Hide is planned from stock only")
end)

-- Simulator finding, 2026-11-25: Blacksmithing 224, gathering nothing. Ornate Thorium Handaxe on
-- 250-287 had Truesilver Breastplate as its "or" row alone and none with Alchemy, and the guide
-- did not say why. Alchemy lets in Arcanite Skeleton Key (Arcanite Bar), which gives points from
-- 250 but is planned from stock only, so the recipes the filter allows planned nothing there.
T.test("Alchemy doesn't take away a pattern step's 'or' row", function()
    local BS, ALCHEMY, HANDAXE, KEY = 164, 171, 16969, 19669
    local guide = CP.Guides[BS]

    -- Every material that isn't vendor stock is mined, as for a character who gathers nothing.
    local classes = {}
    for item in pairs(guide.items) do classes[item] = { 7, 7, 186 } end
    GatherWorld.AnswerClasses(classes)
    World.set(CP.db, "collect", true)
    local learned = {}
    for id, r in pairs(guide.recipes) do
        if (r.src == "trainer" or r.src == "auto" or r.src == "vendor") and r.learn <= 224 then learned[id] = true end
    end
    local st = { spell = HANDAXE, recipe = guide.recipes[HANDAXE], from = 250, to = 287 }
    local function alts(professions)
        CraftWorld.begin({ professions = professions })
        local out = {}
        for _, alt in ipairs(P.Alternatives({ guide = guide, learned = learned, dead = {} }, st, true)) do
            out[#out + 1] = alt.recipe.name
        end
        return table.concat(out, ", ")
    end
    local alone = alts({ [BS] = 250 })
    T.ok(alone ~= "", "something carries on over 250-287 alone")
    CraftWorld.begin({ professions = { [BS] = 250, [ALCHEMY] = 1 } })
    T.ok(CP.Sourcing.Filter(guide, learned, true)(KEY, guide.recipes[KEY]), "with Alchemy the filter lets in Arcanite Skeleton Key")
    T.eq(alts({ [BS] = 250, [ALCHEMY] = 1 }), alone, "the same alternatives with Alchemy")
end)
