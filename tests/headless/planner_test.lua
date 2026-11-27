-- The live planner on a fresh character, and the guides' late steps.

local CP = ProfLost

local function plan(key, collect)
    local saved = CP.db.collect
    CP.db.collect = collect
    local live = CP.Plan.Offline(CP.Guides[key], "test" .. key, 1, 300, {})
    CP.db.collect = saved
    return live.plan
end

T.test("a bolt and the cloak that uses it don't trade points one by one", function()
    local steps = plan(197, false)
    local early = 0
    for _, st in ipairs(steps) do if st.from < 30 then early = early + 1 end end
    T.ok(early <= 1, ("%d steps below 30: one stretch of bolts"):format(early))
end)

T.test("Level-as-you-go leaves no skill points without a recipe", function()
    for key, guide in pairs(CP.Guides) do
        local gaps = {}
        for _, st in ipairs(plan(key, true)) do
            if not st.spell then gaps[#gaps + 1] = st.from .. "-" .. st.to end
        end
        T.eq(#gaps, 0, guide.name .. " gaps: " .. table.concat(gaps, ", "))
    end
end)

T.test("cloth from creatures isn't a rare byproduct; hides still are", function()
    T.eq(CP.Guides[197].items[4338][5], nil, "Mageweave Cloth")
    T.eq(CP.Guides[165].items[4235][5], true, "Heavy Hide")
end)

T.test("no guide step leans on a material made on a cooldown", function()
    for _, guide in pairs(CP.Guides) do
        for _, st in ipairs(guide.steps) do
            local r = guide.recipes[st.spell]
            for _, pair in ipairs(r and r.reagents or {}) do
                T.ok(pair[1] ~= 14342, guide.name .. ": " .. r.name .. " needs Mooncloth")
            end
        end
    end
end)

T.test("a dropped pattern takes a step only where it's realistically had", function()
    for _, guide in pairs(CP.Guides) do
        for _, st in ipairs(guide.steps) do
            local r = guide.recipes[st.spell]
            if r and r.src == "pattern" then
                T.ok(r.how ~= nil and r.how ~= "", guide.name .. ": " .. r.name .. " says where it drops")
            end
        end
    end
end)

T.test("while Fishing levels, Cooking takes fish recipes where they level faster", function()
    local saved = { collect = CP.db.collect, fc = CP.db.fishCook, info = C_SkillInfo.GetSkillLineInfoByID }
    local function cookPlan(fishing, paired)
        C_SkillInfo.GetSkillLineInfoByID = function(id)
            if id == 356 then return { rank = fishing, maxRank = 75 } end
            return saved.info(id)
        end
        CP.db.collect, CP.db.fishCook = true, paired
        local live = CP.Plan.Offline(CP.Guides[185], "fishtest" .. fishing .. tostring(paired), 1, 300, {})
        local fishy = 0
        for _, st in ipairs(live.plan) do
            local r = st.spell and CP.Guides[185].recipes[st.spell]
            for _, pair in ipairs(r and r.reagents or {}) do
                if CP.Pricing.IsFish(pair[1]) then fishy = fishy + (st.to - st.from) break end
            end
        end
        return fishy
    end
    local ok, err = pcall(function()
        T.ok(CP.Pricing.IsFish(6303), "Raw Slitherskin Mackerel is a catch")
        T.ok(not CP.Pricing.IsFish(2318), "Light Leather isn't")
        local unpaired, paired, maxed = cookPlan(60, false), cookPlan(60, true), cookPlan(300, true)
        -- Fishing 60 counts only the fish its waters land (Sourcing.Reach, owner 2026-11-27), so the
        -- later fish recipes wait until Fishing reaches their water.
        T.ok(paired > 80, ("fish recipes cover %d points while Fishing levels, %d at 300"):format(paired, maxed))
        T.ok(maxed > 0, "Fishing at 300: fish recipes at their usual effort")
        T.eq(cookPlan(0, true), 0, "no Fishing: no fish to collect")
        T.eq(unpaired, 0, "Fish for Cooking off: as without Fishing")
    end)
    C_SkillInfo.GetSkillLineInfoByID, CP.db.collect, CP.db.fishCook = saved.info, saved.collect, saved.fc
    T.ok(ok, err)
end)

T.test("the checklist skips rares and lone spawns", function()
    local savedPos = CP.Waypoint.MapPosZone
    CP.Waypoint.MapPosZone = function(z) return z end
    CP.Gather.ResetClusters()
    local ok, err = pcall(function()
        local rows = CP.Gather.ForZone(1420, { [393] = 199 }, { here = CP.Gather.Farmable })
        T.ok(#rows > 0, "Tirisfal still lists its skins")
        for _, row in ipairs(rows) do
            for _, src in ipairs(row.sources) do
                T.ok(not src.name:find("Ressan"), "Ressan the Needler, a rare, is left out")
                T.ok(CP.Gather.Spawns(1420, "mobs", src.entry) >= CP.Gather.MIN_MOB_SPAWNS or src.kind ~= "mob",
                    src.name .. " has enough spawns")
            end
        end
    end)
    CP.Waypoint.MapPosZone = savedPos
    CP.Gather.ResetClusters()
    T.ok(ok, err)
end)

T.test("plans steer off green crafts where another recipe can take over", function()
    -- Green comes last, so fresh plans spend green points only at the guides' tops, where
    -- no recipe stays yellow (Huge Thorium Battleaxe, Wizardweave Turban): 13 points, with green from
    -- the midpoint rounded down. A maker's run (bolts, powders, grinding stones) is exempt: its crafts
    -- are made for later steps anyway (decision 0008; owner, 2026-11-19).
    local saved = CP.db.collect
    CP.db.collect = false
    local green = 0
    for key, g in pairs(CP.Guides) do
        local live = CP.Plan.Offline(g, "greentest" .. key, 1, 300, {})
        local prep, craftOnly = g.prep or {}, g.craftOnly or {}
        for _, st in ipairs(live.plan) do
            local r = st.spell and g.recipes[st.spell]
            local maker = r and r.makes and (prep[r.makes] or craftOnly[r.makes])
            if r and not maker then
                for s = st.from, st.to - 1 do
                    if CP.Solver.IsGreen(r, s) then green = green + 1 end
                end
            end
        end
    end
    CP.db.collect = saved
    T.ok(green <= 13, ("%d green points across fresh plans"):format(green))
end)

T.test("a recipe the game marks trivial never takes a step, whatever the data says", function()
    local guide = { recipes = {
        [818] = { name = "Basic Campfire", learn = 1, yellow = 45, grey = 75, reagents = {} },
        [2540] = { name = "Roasted Boar Meat", learn = 1, yellow = 45, grey = 85, reagents = {} },
    } }
    local live = {
        { id = 1229737, name = "Basic Campfire", learned = true, difficulty = CP.Professions.GREY },
        { id = 2540, name = "Roasted Boar Meat", learned = true, difficulty = CP.Professions.ORANGE },
    }
    local learned = CP.Professions.Learned(live)
    local alias = CP.Plan.Alias(guide, live, learned)
    local dead = CP.Plan.Dead(guide, live, alias)
    T.ok(dead[818], "the campfire, through the player's own same-name spell")
    T.ok(not dead[2540], "a recipe still giving points")
end)

T.test("Forever's Basic Campfire is out of the Cooking guide and its plans", function()
    T.eq(CP.Guides[185].recipes[818], nil)
    local saved = CP.db.collect
    for _, collect in ipairs({ true, false }) do
        CP.db.collect = collect
        for _, st in ipairs(CP.Plan.Offline(CP.Guides[185], "campfire" .. tostring(collect), 1, 300, {}).plan) do
            local r = st.spell and CP.Guides[185].recipes[st.spell]
            -- Forever's own campfire (1229737) gives points 1-5 and greys at 5, as the game shows.
            T.ok(not (r and r.name == "Basic Campfire" and st.to > 5), ("no campfire step past 5 (%d-%d)"):format(st.from, st.to))
        end
    end
    CP.db.collect = saved
end)

T.test("fallbacks: none on short steps, never the next step's recipe, and they say where they stop", function()
    local saved = CP.db.collect
    for _, collect in ipairs({ false, true }) do
        CP.db.collect = collect
        local guide = CP.Guides[185]
        local live = CP.Plan.Offline(guide, "fb" .. tostring(collect), 5, 300, {})
        live.sides, live.alias, live.dead = {}, {}, {}
        CP.Plan.AddFallbacks(live)
        for i, side in pairs(live.sides) do
            local st = live.plan[i]
            T.ok(st.to - st.from >= CP.Plan.MIN_FALLBACK, ("fallback on a %d-point step"):format(st.to - st.from))
            T.ok(not live.plan[i + 1] or side.spell ~= live.plan[i + 1].spell, "not the next step's own recipe")
            T.ok(side.upto <= side.recipe.grey and side.upto <= st.to, "stops where it greys or the step ends")
        end
    end
    CP.db.collect = saved
end)

T.test("no step shorter than 3 points when a neighbouring recipe can carry it", function()
    local saved = CP.db.collect
    for _, collect in ipairs({ true, false }) do
        CP.db.collect = collect
        for key, g in pairs(CP.Guides) do
            local plan = CP.Plan.Offline(g, "minrun" .. key .. tostring(collect), 1, 300, {}).plan
            -- Chained recipes (making or using craft-only or prep items) keep their runs,
            -- and never take a short run in.
            local function chained(r)
                if r.makes and ((g.prep or {})[r.makes] or (g.craftOnly or {})[r.makes]) then return true end
                for _, pair in ipairs(r.reagents or {}) do
                    if (g.craftOnly or {})[pair[1]] then return true end
                end
                return false
            end
            for i, st in ipairs(plan) do
                local r0 = st.spell and g.recipes[st.spell]
                if r0 and not chained(r0) and st.to - st.from < CP.Solver.MIN_RUN and i > 1 and i < #plan then
                    -- Allowed only when neither neighbour can give a point over it, no
                    -- greener than the run's own recipe.
                    local function carries(spell)
                        local r = spell and g.recipes[spell]
                        if not r or chained(r) then return false end
                        for k = st.from, st.to - 1 do
                            if r.learn > k or CP.Guide.Chance(r, k) <= 0 then return false end
                            if CP.Solver.IsGreen(r, k) and not CP.Solver.IsGreen(r0, k) then return false end
                        end
                        return true
                    end
                    T.ok(not carries(plan[i - 1].spell) and not carries(plan[i + 1].spell),
                        ("%s: %s %d-%d could join a neighbour"):format(g.name, g.recipes[st.spell].name, st.from, st.to))
                end
            end
        end
    end
    CP.db.collect = saved
end)

T.test("plans never use cooldown-made materials the player can't get", function()
    -- Mooncloth (4-day cooldown) was made on demand: 22 Mooncloth Robes, 88 Mooncloth.
    -- Buy mode priced it at its 1g60 list price. Without an auction scan it has none.
    local COOLDOWN = { [14342] = "Mooncloth", [12360] = "Arcanite Bar", [251290] = "Legionite Bar" }
    T.eq(CP.Pricing.Get(14342, CP.Guides[197].items[14342]), nil, "no list-price estimate for Mooncloth")
    local saved = CP.db.collect
    for _, collect in ipairs({ true, false }) do
        CP.db.collect = collect
        for key, g in pairs(CP.Guides) do
            for item in pairs(COOLDOWN) do
                T.eq((g.prep or {})[item], nil, g.name .. " makes " .. COOLDOWN[item] .. " on demand")
            end
            for _, st in ipairs(CP.Plan.Offline(g, "cooldown" .. key .. tostring(collect), 1, 300, {}).plan) do
                local r = st.spell and g.recipes[st.spell]
                for _, pair in ipairs(r and r.reagents or {}) do
                    T.ok(not COOLDOWN[pair[1]], ("%s %s %d-%d: %s uses %s"):format(collect and "collect" or "buy",
                        g.name, st.from, st.to, r.name, tostring(COOLDOWN[pair[1]])))
                end
            end
        end
    end
    CP.db.collect = saved
end)

T.test("Transmute: Elemental Fire stays a step; cooldown transmutes don't", function()
    -- Only a material made on a cooldown and nowhere else is cut. Elemental Fire's
    -- transmute has no cooldown; Iron to Gold and Mithril to Truesilver do, but their
    -- bars also drop and are mined, so the bars themselves stay plain materials.
    local alc = CP.Guides[171]
    local fire, gold, truesilver = alc.recipes[25146], alc.recipes[11479], alc.recipes[11480]
    T.ok(fire and fire.name == "Transmute: Elemental Fire", "in the Alchemy guide")
    T.eq(fire.step, true, "no cooldown: a step candidate")
    T.eq(fire.makes, 7068)
    T.eq(fire.yield, 3, "one Heart of Fire gives three Elemental Fire")
    T.ok(not (alc.items[7068] and alc.items[7068].cooldown), "Elemental Fire isn't cooldown-made")
    T.ok(gold and not gold.step, "Iron to Gold (cooldown) is never a step")
    T.ok(truesilver and not truesilver.step, "Mithril to Truesilver (cooldown) is never a step")
    for key, g in pairs(CP.Guides) do
        for _, item in ipairs({ 3577, 6037, 7068 }) do
            T.ok(not (g.items[item] and g.items[item].cooldown), ("%s flags item %d cooldown-made"):format(g.name, item))
        end
    end
end)

T.test("Level-as-you-go: an unlearned dropped pattern only covers points nothing else can", function()
    -- Tailoring took Wizardweave Turban (2% from Dark Casters) from 260 while Runecloth
    -- Boots was still yellow. From 265 Boots is green, and green comes after every orange
    -- or yellow recipe, dropped patterns included, so the Turban leads from there.
    local g, saved = CP.Guides[197], CP.db.collect
    CP.db.collect = true
    local plan = CP.Plan.Offline(g, "droppedLast", 1, 300, {}).plan
    local first
    for _, st in ipairs(plan) do
        local r = st.spell and g.recipes[st.spell]
        if r and r.src == "pattern" and not first then first = st.from end
    end
    T.eq(first, CP.Solver.GreenFrom(g.recipes[18423]), "the first dropped-pattern step starts where Runecloth Boots greens")
    -- Learned, the pattern competes like any other recipe.
    local learned = { [18450] = true }
    plan = CP.Plan.Offline(g, "droppedLearned", 240, 300, learned).plan
    local uses = false
    for _, st in ipairs(plan) do if st.spell == 18450 and st.from < 280 then uses = true end end
    T.ok(uses, "learned: the Turban can lead before 280")
    CP.db.collect = saved
end)
