-- Enchanting's dust counts follow the plan the other guide shows (review items 22 and 23):
-- the "now" count drops as that guide's current step is crafted, and the note reads the
-- committed plan, not the solver's candidate.

local CP = ProfLost
local ENCHANTING, TAILOR = 333, 197
local LINEN, THREAD, BOLT, GLOVES = 2589, 2320, 2963, 3840
local DUST = 10940
local ELWYNN = 1429

local function solveBoth(skills, bags)
    MapWorld.begin({ zone = ELWYNN, level = 20, side = "Alliance" })
    CraftWorld.begin({ professions = skills, bags = bags })
    World.set(CP.db, "collect", true)
    World.set(CP.db, "deEnchant", true)
    World.set(CP.Solver, "SETTLE", false)
    World.patch("InCombatLockdown", function() return false end)
    CraftWorld.Open(ENCHANTING)
    T.advance(1)
    CP.Plan.Current()
    CraftWorld.Close()
    T.advance(1)
    CraftWorld.Open(TAILOR)
    T.advance(1)
    local live = CP.Plan.Current()
    return live
end

T.test("Enchanting's now count drops as the other guide's step is crafted", function()
    local live = solveBoth({ [ENCHANTING] = { rank = 1, max = 75 }, [TAILOR] = { rank = 30, max = 75 } },
                           { [LINEN] = 200, [THREAD] = 40 })
    local step = live and live.plan and live.plan[1]
    T.eq(step and step.spell, GLOVES, "Tailoring's step under way is Heavy Linen Gloves")
    if not (step and step.spell == GLOVES) then return end
    local before = CP.Plan.StepCrafts(step)
    local nowBefore = CP.Shared.DEIncomingSplit(DUST).now
    T.ok(nowBefore > 0, "the step gives dust now")
    for _ = 1, 4 do
        CraftWorld.Miss()
        C_TradeSkillUI.CraftRecipe(BOLT, 1)
        CraftWorld.Cast()
    end
    for _ = 1, 2 do
        CraftWorld.Miss()
        C_TradeSkillUI.CraftRecipe(GLOVES, 1)
        CraftWorld.Cast()
    end
    T.advance(0.5)
    local cur = CP.Plan.Current().plan[1]
    local after = CP.Plan.StepCrafts(cur)
    T.eq(after, before - 2, "Tailoring's card counts two crafts down")
    local nowAfter = CP.Shared.DEIncomingSplit(DUST).now
    T.ok(nowAfter < nowBefore, ("the now count drops: %d -> %d"):format(nowBefore, nowAfter))
    local per = nowBefore / before
    T.ok(math.abs(nowAfter - math.floor(per * after)) <= 1,
        ("the now count follows the card's %d crafts: %d"):format(after, nowAfter))
    CraftWorld.Close()
end)

T.test("Enchanting's note reads the plan Tailoring shows, not the solver's candidate", function()
    solveBoth({ [ENCHANTING] = { rank = 53, max = 75 }, [TAILOR] = { rank = 66, max = 150 } }, nil)
    local c = CP.Plan.Committed(TAILOR)
    T.ok(c and c.steps and #c.steps >= 2, "Tailoring has a committed plan")
    if not (c and c.steps and #c.steps >= 2) then return end
    local guide = CP.Guides[TAILOR]
    -- The last step the note names as "later".
    local base = CP.Shared.DEIncomingSplit(DUST)
    T.ok(base.laterStep ~= nil, "a later step is named")
    if not base.laterStep then return end
    -- Hold a different route: swap the later step for another recipe that gives dust over
    -- the same range; the candidate in lastPlan stays as the solver left it.
    local idx
    for i = (c.current or 1) + 1, #c.steps do
        if guide.recipes[c.steps[i][3]].name == base.laterStep.recipe then idx = i break end
    end
    T.ok(idx ~= nil, "the named step is in the committed plan")
    if not idx then return end
    local held = c.steps[idx]
    local was = held[3]
    World.onEnd(function() held[3] = was end)
    local alt
    for spell, r in pairs(guide.recipes) do
        if spell ~= was and r.name ~= base.laterStep.recipe then
            held[3] = spell
            local s = CP.Shared.DEIncomingSplit(DUST)
            if s.laterStep and s.laterStep.recipe == r.name then alt = r break end
        end
    end
    T.ok(alt ~= nil, "the note names the held step, not the solver's")
    local _, names = CP.Shared.DEIncoming(DUST)
    T.ok(#names > 0, "the whole-plan count still names Tailoring")
    CraftWorld.Close()
end)
