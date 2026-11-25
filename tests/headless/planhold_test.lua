-- The current step holds while the player works it: crafting bolts for later steps does
-- not hand the step to the recipe those bolts feed (playtester report on 1.0.0).

local CP = ProfLost
local TAILOR = 197
local BOLT, LINEN = 2963, 2589      -- Bolt of Linen Cloth and the cloth it takes

local function current()
    local live = CP.Plan.Current()
    local p = live.prof
    for _, st in ipairs(live.plan or {}) do
        if st.spell and st.to > p.skill then return st, p.skill end
    end
end

local function name(spell) return spell and CP.Guides[TAILOR].recipes[spell].name or "none" end

-- Tailoring from 1, the window open, crafting the current step one cast at a time. The bolt step
-- runs into green (its bolts are made for later steps, decision 0008), so every craft short of grey
-- gives its point here: the test is about the hold, not the dice.
local function play(mode)
    CraftWorld.begin({ professions = { [TAILOR] = { rank = 1, max = 75 } }, bags = { [LINEN] = 400 },
                       roll = function(r, p) return p.rank < r.grey and (r.ups or 1) or 0 end })
    World.set(CP.db, "collect", mode == "collect")
    CP.Plan.Invalidate()
    CraftWorld.Open(TAILOR)
    T.advance(1)
end

for _, mode in ipairs({ "collect", "buy" }) do
    T.test(mode .. ": the bolt step holds until its target as bolts pile up", function()
        play(mode)
        local first = current()
        T.eq(name(first.spell), name(BOLT), "the plan starts on bolts")
        local target, seen = first.to, {}
        for _ = 1, 200 do
            local st, skill = current()
            if skill >= target then break end
            if st.spell ~= BOLT then
                T.ok(false, ("at skill %d with %d bolts held the step is %s, not bolts to %d")
                    :format(skill, CraftWorld.Bag(2996), name(st.spell), target))
                return
            end
            seen[#seen + 1] = st.to
            C_TradeSkillUI.CraftRecipe(BOLT, 1)
            CraftWorld.Cast()
            T.advance(0.2)
        end
        local _, skill = current()
        T.ok(skill >= target, ("skill reached the bolt step's target %d (at %d)"):format(target, skill))
        for _, to in ipairs(seen) do T.eq(to, target, "the step's target never moved") end
    end)
end

-- The solver alone: Tailoring's bolts, with bolts in the bags.
local tailoring = CP.Guides[TAILOR]
local HELD = { [2996] = 20 }
local function known() return { [BOLT] = true, [2387] = true, [3915] = true, [12044] = true, [3755] = true } end
local function listPrice(_, info) return info and info[1] > 0 and info[1] or nil end
local function boltsFor(from, to)
    local map = {}
    for s = from, to - 1 do map[s] = BOLT end
    return map
end

T.test("without a last plan, held bolts make the cloak cheapest point by point (the flip the hold stops)", function()
    -- The pick loop alone, without the settle pass that then puts the bolts first (decision 0008).
    World.set(CP.Solver, "SETTLE", false)
    local steps = CP.Solver.Plan(tailoring, 5, known(), listPrice, nil, nil, HELD)
    T.ok(steps[1].spell ~= BOLT, "the pick loop spends the held bolts first: " .. name(steps[1].spell))
    World.set(CP.Solver, "SETTLE", true)
    steps = CP.Solver.Plan(tailoring, 5, known(), listPrice, nil, nil, HELD)
    T.eq(name(steps[1].spell), name(BOLT), "settled, the bolts later steps need come first while they give points")
end)

T.test("a bolt step under way holds with bolts in the bags", function()
    local steps = CP.Solver.Plan(tailoring, 5, known(), listPrice, nil, boltsFor(1, 29), HELD)
    T.eq(name(steps[1].spell), name(BOLT), "the current step")
    -- The settle pass only grows a maker's run: the hold's end at least.
    T.ok(steps[1].to >= 29, "to its end or past it: " .. steps[1].to)
end)

T.test("a bolt step about to start keeps its pick with bolts in the bags", function()
    local steps = CP.Solver.Plan(tailoring, 5, known(), listPrice, nil, boltsFor(5, 29), HELD)
    T.eq(name(steps[1].spell), name(BOLT), "held bolts are kept for later steps")
end)

T.test("a blocked current step gives way", function()
    local noBolt = function(id) return id ~= BOLT end
    local steps = CP.Solver.Plan(tailoring, 5, known(), listPrice, noBolt, boltsFor(1, 29), HELD)
    T.ok(steps[1].spell ~= BOLT, "a recipe the plan may no longer use is dropped: " .. name(steps[1].spell))
end)

T.test("the plan picks afresh once the step's target is reached", function()
    -- The pick loop alone (no settle pass): a fresh pick at 20 is another recipe.
    World.set(CP.Solver, "SETTLE", false)
    local fresh = CP.Solver.Plan(tailoring, 20, known(), listPrice, nil, nil, HELD)
    local after = CP.Solver.Plan(tailoring, 20, known(), listPrice, nil, boltsFor(1, 20), HELD)
    T.ok(fresh[1].spell ~= BOLT, "the fresh pick at 20 is another recipe: " .. name(fresh[1].spell))
    T.eq(name(after[1].spell), name(fresh[1].spell), "past the bolt step's end the plan is the fresh one")
    World.set(CP.Solver, "SETTLE", true)
    fresh = CP.Solver.Plan(tailoring, 20, known(), listPrice, nil, nil, HELD)
    after = CP.Solver.Plan(tailoring, 20, known(), listPrice, nil, boltsFor(1, 20), HELD)
    T.eq(("%s %d-%d"):format(name(after[1].spell), after[1].from, after[1].to),
        ("%s %d-%d"):format(name(fresh[1].spell), fresh[1].from, fresh[1].to), "settled too")
end)

T.test("a held step's saved plan says it is under way, so the next solve holds it too", function()
    local steps = CP.Solver.Plan(tailoring, 5, known(), listPrice, nil, boltsFor(1, 29), HELD)
    T.eq(steps[1].since, 1, "the held step keeps where it began")
    local again = CP.Solver.Plan(tailoring, 5, known(), listPrice, nil, CP.Plan.Expand(CP.Plan.Pack(steps)), HELD)
    T.eq(name(again[1].spell), name(BOLT), "a solve given the drawn plan draws it again")
    -- The drawn plan anchors the later picks too, so the settle may grow the run once more; it never shrinks.
    T.ok(again[1].to >= steps[1].to, ("held to %d, then %d"):format(steps[1].to, again[1].to))
    local third = CP.Solver.Plan(tailoring, 5, known(), listPrice, nil, CP.Plan.Expand(CP.Plan.Pack(again)), HELD)
    T.eq(third[1].to, again[1].to, "and then stays")
    local fresh = CP.Solver.Plan(tailoring, 5, known(), listPrice, nil, boltsFor(5, 29), HELD)
    T.eq(fresh[1].since, nil, "a step not yet under way has no start of its own")
end)
