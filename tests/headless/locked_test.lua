-- Lock what you've invested in (decision 0007). Owner's report on
-- 1.1.0: Leatherworking 143 with 58 Heavy Leather showed Heavy Armor Kit 143-153 and Heavy Leather
-- 58/60; skinning 9 more leather, without a craft, made it 143-155 and 67/80. The current step and
-- every step the player has started preparing for hold; the rest re-plans only for a route at least
-- Plan.BETTER_BY cheaper; a setting turned is the player asking.

local CP = ProfLost
local GT = CP.GuideTab
local LW, TAILOR, ENCHANTING = 165, 197, 333
local KIT, HEAVY, HEAVY_HIDE = 3780, 4234, 4235
local LINEN, LINEN_BOLT = 2589, 2963

local function scene(leather)
    MapWorld.begin({ zone = 1411, level = 30, side = "Horde" })
    CraftWorld.begin({ professions = { [LW] = { rank = 143, max = 225 } }, bags = { [HEAVY] = leather } })
    World.set(CP.db, "collect", true)
    World.set(CP.charDB, "committed", nil)
    World.set(CP.charDB, "lastPlan", nil)
    CraftWorld.Open(LW)
    T.advance(1)
    CP.Panel:Refresh()
end

local function layout()
    local out = {}
    for _, row in ipairs(GT.ui.rows) do
        if row.spell and not row.side then out[#out + 1] = ("%s %d-%d x%d"):format(row.spell, row.from, row.to, row.crafts or 0) end
        if row.train then out[#out + 1] = "train " .. row.train.skill end
        if row.rank then out[#out + 1] = "rank " .. row.rank.name end
    end
    return table.concat(out, "; ")
end

local function current()
    for _, row in ipairs(GT.ui.rows) do
        if row.spell and not row.side and not (row.rank or row.train) then return row end
    end
end

local function leatherLine()
    for _, l in ipairs(GT.ui.details.rows) do
        if l:IsShown() and l.itemID == HEAVY then return l.count:GetText(), l.done:IsShown() end
    end
end

T.test("the owner's Heavy Armor Kit case: 58 then 67 Heavy Leather leaves the kit step as it was", function()
    scene(58)
    local cur = current()
    T.eq(cur and cur.spell, KIT, "the current step is Heavy Armor Kit")
    local kit = ("%d-%d x%d"):format(cur.from, cur.to, cur.crafts)
    local before = layout()
    GT.Pick(cur)
    T.advance(0.3)
    local count = leatherLine()
    print(("LOCKPLAN|kit|58 Heavy Leather|Heavy Armor Kit %s|leather %s"):format(kit, tostring(count)))
    CraftWorld.SetBag(HEAVY, 67)
    -- A rare hide too: the held counts the solve reads move, so the plan is solved again. And
    -- Heavy Leather now weighs far more, so a free solve would drop the kit step.
    CraftWorld.SetBag(HEAVY_HIDE, 3)
    local collect = CP.Pricing.CollectFn
    World.set(CP.Pricing, "CollectFn", function(...)
        local f = collect(...)
        return function(item, ...)
            if item == HEAVY then return 1e7 end
            return f(item, ...)
        end
    end)
    CP.Plan.Invalidate()
    T.advance(1)
    CP.Panel:Refresh()
    local now = current()
    T.eq(("%d-%d x%d"):format(now.from, now.to, now.crafts), kit, "the kit step's range and count hold")
    local text = leatherLine()
    print(("LOCKPLAN|kit|67 Heavy Leather|Heavy Armor Kit %d-%d x%d|leather %s"):format(now.from, now.to, now.crafts, tostring(text)))
    if count then
        local need = tonumber(count:match("/ (%d+)"))
        T.eq(text, ("67 / %d"):format(need), "only the have count moved")
    end
    T.ok(before ~= "", "a plan: " .. before)
    CraftWorld.Close()
end)

T.test("a craft of the current step counts it down by one", function()
    scene(58)
    local cur = current()
    local n = cur.crafts
    T.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", cur.spell)
    CP.Panel:Refresh()
    T.eq(current().crafts, n - 1, "one fewer")
    CraftWorld.Close()
end)

-- A guide of four made-up steps for Plan.Locks: A (current) uses cloth 1; B uses leather 2 and
-- cloth 1; C uses bolt 3, made from cloth 4 (prep); D uses belt 5, which B makes (craft-only).
local function fakeGuide()
    local function r(name, reagents, makes)
        return { name = name, reagents = reagents, makes = makes, learn = 1, yellow = 200, grey = 300 }
    end
    return {
        recipes = { [11] = r("A", { { 1, 1 } }), [12] = r("B", { { 2, 1 }, { 1, 1 } }, 5),
                    [13] = r("C", { { 3, 1 } }), [14] = r("D", { { 5, 1 } }), [15] = r("Bolt", { { 4, 2 } }, 3) },
        prep = { [3] = 15 }, craftOnly = { [5] = true },
    }
end
local STEPS = { { 100, 110, 11 }, { 110, 120, 12 }, { 120, 130, 13 }, { 130, 140, 14 } }

local function locked(bags, dead, invested)
    CraftWorld.begin({ professions = {}, bags = bags })
    local set = CP.Plan.Locks({ steps = STEPS, invested = invested }, fakeGuide(), 105, {}, dead)
    local out = {}
    for i = 1, #STEPS do if set[i] then out[#out + 1] = i end end
    return table.concat(out, ",")
end

T.test("Plan.Locks: the current step, and each step the bags have started", function()
    T.eq(locked({}), "1", "empty bags: the current step alone")
    T.eq(locked({ [1] = 5 }), "1", "cloth counts toward the earliest step that uses it, the current one")
    T.eq(locked({ [2] = 5 }), "1,2", "leather locks B, the only step that uses it")
    T.eq(locked({ [4] = 2 }), "1,3", "the bolt's cloth locks C through its prep maker")
    T.eq(locked({ [5] = 1 }), "1,2,4", "a held belt locks D, and D locks B, which makes the belts")
    T.eq(locked({}, { [11] = true }), "", "a current step gone grey is not locked")
    T.eq(locked({ [1] = 5 }, nil, { ["12:110:120"] = true }), "1,2",
        "B, locked at the last solve, keeps its lock while the bags hold its cloth")
    T.eq(locked({}, nil, { ["12:110:120"] = true }), "1", "and loses it once they hold none of its materials")
end)

T.test("Plan.Better: the unlocked route changes only for a route BETTER_BY cheaper or when it can't be done", function()
    local guide = fakeGuide()
    local old = { { spell = 11, from = 100, to = 110, locked = true }, { spell = 12, from = 110, to = 120 } }
    local function new(spell) return { { spell = 11, from = 100, to = 110, locked = true }, { spell = spell, from = 110, to = 120 } } end
    T.eq(CP.Plan.BETTER_BY, 0.10, "the threshold the decision records")
    T.eq(CP.Plan.Better(guide, old, new(13), 100, { [12] = 100, [13] = 95 }), false, "5% cheaper: hold")
    T.eq(CP.Plan.Better(guide, old, new(13), 100, { [12] = 100, [13] = 89 }), true, "11% cheaper: change")
    T.eq(CP.Plan.Better(guide, old, new(13), 100, { [13] = 120 }), true, "the old step's recipe has no cost now: change")
    T.eq(CP.Plan.Better(guide, old, new(13), 100, { [12] = 100, [13] = 100 }, { [12] = true }), true, "the old step went grey: change")
    local short = { { spell = 11, from = 100, to = 110, locked = true }, { spell = 13, from = 110, to = 125 } }
    T.eq(CP.Plan.Better(guide, old, short, 100, { [12] = 100, [13] = 100 }), true, "another span of skill: change")
end)

-- Tailoring at `skill` (default 1) with Enchanting at 1, its needs saved.
local function tailorWithEnchanting(skill)
    MapWorld.begin({ zone = 1429, level = 20, side = "Alliance" })
    CraftWorld.begin({ professions = { [ENCHANTING] = { rank = 1, max = 75 }, [TAILOR] = { rank = skill or 1, max = 75 } },
                       bags = { [LINEN] = 42 } })
    World.set(CP.db, "collect", true)
    World.set(CP.db, "deEnchant", true)
    World.set(CP.charDB, "committed", nil)
    World.set(CP.charDB, "lastPlan", nil)
    CraftWorld.Open(ENCHANTING)
    T.advance(1)
    CP.Plan.Current()
    CraftWorld.Close()
    T.advance(1)
    CraftWorld.Open(TAILOR)
    T.advance(1)
end

local function mainSteps(live)
    local out = {}
    for _, st in ipairs(live.plan) do
        if st.spell then out[#out + 1] = st end
    end
    return out
end

T.test("a coupled profession's change never lands on the locked step", function()
    -- At 1 Enchanting's credit sets how far Bolt of Linen Cloth runs (1-45; without the credit 1-41),
    -- so the current step is one the credit shaped.
    tailorWithEnchanting(1)
    local first = mainSteps(CP.Plan.Current())[1]
    T.eq(first.spell, LINEN_BOLT, "Bolt of Linen Cloth is the current step")
    local was = ("%d %d-%d x%d"):format(first.spell, first.from, first.to, CP.Plan.StepCrafts(first))
    -- Enchanting needs nothing now: its credit no longer stretches the bolts.
    World.set(CP.Shared, "EnchantingNeeds", function() return {}, "", nil end)
    CP.Plan.Invalidate()
    local now = mainSteps(CP.Plan.Current())[1]
    T.eq(("%d %d-%d x%d"):format(now.spell, now.from, now.to, CP.Plan.StepCrafts(now)), was, "the bolt step holds")
    -- Without the hold the same solve shortens the bolts: the lock is what kept them.
    World.set(CP.Plan, "Hold", function() return nil, {} end)
    CP.Plan.Invalidate()
    local free = mainSteps(CP.Plan.Current())[1]
    T.ok(("%d %d-%d x%d"):format(free.spell, free.from, free.to, CP.Plan.StepCrafts(free)) ~= was, "a free solve would have moved the step")
    CraftWorld.Close()
end)

T.test("a setting turned gives a fresh plan; turned back with nothing else changed, the plan it left", function()
    tailorWithEnchanting()
    local live = CP.Plan.Current()
    local function text(l)
        local out = {}
        for _, st in ipairs(mainSteps(l)) do out[#out + 1] = ("%d %d-%d x%d"):format(st.spell, st.from, st.to, st.crafts or 0) end
        return table.concat(out, "; ")
    end
    local was = text(live)
    World.set(CP.db, "deEnchant", false)
    CP.Plan.Invalidate()
    local c = CP.Plan.Hold(live.prof, live.guide, live.learned, live.dead)
    T.eq(c, nil, "under the turned setting nothing is held")
    CP.Plan.Current()
    World.set(CP.db, "deEnchant", true)
    CP.Plan.Invalidate()
    T.eq(text(CP.Plan.Current()), was, "back: the plan it left")
    CraftWorld.Close()
end)

-- Owner, 2026-11-23: a setting turned on and back off is no real change, so the started steps hold
-- even when a craft moved the skill in between (leatherworking-alliance-buy-new-controls-s1).
T.test("a setting turned and back with a skill-up between: the started steps hold", function()
    scene(58)
    World.set(CP.db, "collect", false)
    CP.Plan.Invalidate()
    local live = CP.Plan.Current()
    local c, locks = CP.Plan.Hold(live.prof, live.guide, live.learned, live.dead)
    local want = {}
    for i in pairs(locks) do
        local f = c.steps[i]
        want[#want + 1] = { spell = f[3], from = f[1], to = f[2], crafts = f[5] }
    end
    table.sort(want, function(a, b) return a.from < b.from end)
    T.ok(#want >= 1, "a locked step to keep")
    World.set(CP.db, "collect", true)
    CP.Plan.Invalidate()
    CP.Plan.Current()
    CraftWorld.SetSkill(LW, 145)
    CP.Plan.Invalidate()
    CP.Plan.Current()
    World.set(CP.db, "collect", false)
    CP.Plan.Invalidate()
    local now = CP.Plan.Current()
    T.eq(now.prof.skill, 145, "the skill moved")
    for _, w in ipairs(want) do
        local found
        for _, st in ipairs(mainSteps(now)) do
            if st.spell == w.spell and st.to == w.to and st.from == math.max(w.from, 145)
                and CP.Plan.StepCrafts(st) == w.crafts then
                found = true
            end
        end
        T.ok(found, ("locked step %d %d-%d x%d holds"):format(w.spell, w.from, w.to, w.crafts))
    end
    CraftWorld.Close()
end)

T.test("Re-plan and the route note are gone", function()
    T.eq(CP.Plan.Replan, nil, "no Plan.Replan")
    T.eq(CP.Plan.RouteNote, nil, "no route note")
    T.eq(CP.Plan.ROUTE_NOTE, nil)
    T.eq(CP.Window.REPLAN_LABEL, nil, "no menu entry")
end)
