-- Enchanting's dust credit from another guide's greens counts only toward the Enchanting
-- steps whose skill reaches what disenchanting that green needs (Disenchant.Skill).

local CP = ProfLost
local Sh, DE = CP.Shared, CP.Disenchant
local TAILORING, ENCHANTING = 197, 333
local DUST, BROWN_LINEN_ROBE = 10940, 7623

local function withChar(fields, fn)
    local saved = {}
    for k, v in pairs(fields) do
        saved[k] = CP.charDB[k]
        CP.charDB[k] = v
    end
    local ok, err = pcall(fn)
    for k in pairs(fields) do CP.charDB[k] = saved[k] end
    if not ok then error(err, 0) end
end

-- The Tailoring recipe (lowest id) whose product needs at least `min` skill to disenchant,
-- and the first material it gives.
local function highRecipe(min)
    local best, bestID
    for id, r in pairs(CP.Guides[TAILORING].recipes) do
        local group = r.makes and CP.DisenchantData.items[r.makes]
        local need = group and DE.Skill(nil, nil, group)
        if need and need >= min and #Sh.DEYield(r) > 0 and (not bestID or id < bestID) then best, bestID = r, id end
    end
    return best, bestID, best and Sh.DEYield(best)[1].item
end

local function price(_, info) return info and info[4] or 1 end

T.test("a group's disenchant skill follows Classic's item level rule", function()
    T.eq(DE.Skill(nil, nil, 1), 1, "green to item level 15")
    T.eq(DE.Skill(nil, nil, 2), 1, "green to item level 20")
    T.eq(DE.Skill(nil, nil, 3), 25, "green to item level 25")
    T.eq(DE.Skill(nil, nil, 4), 50, "green to item level 30")
    T.eq(DE.Skill(nil, nil, 41), 25, "blue to item level 25")
    T.eq(DE.Skill(nil, nil, 999999), nil, "no band names it")
end)

T.test("dust counts only toward Enchanting steps the green's disenchant skill reaches", function()
    local low = CP.Guides[TAILORING].recipes[BROWN_LINEN_ROBE]
    local high, highID, mat = highRecipe(100)
    T.ok(high ~= nil, "Tailoring has a green that needs 100 skill")
    local early = { [DUST] = { { to = 50, need = 40 } }, [mat] = { { to = 50, need = 40 } } }
    local late = { [DUST] = { { to = 150, need = 40 } }, [mat] = { { to = 150, need = 40 } } }
    local needs = { [DUST] = 40, [mat] = 40 }
    T.ok(Sh.DECredit(low, price, needs, early) > 0, "a green anyone can disenchant feeds an early step")
    T.eq(Sh.DECredit(high, price, needs, early), 0, "a green that needs 100 gives nothing to a step ending at 50")
    T.ok(Sh.DECredit(high, price, needs, late) > 0, "it feeds a step ending at 150 (recipe " .. tostring(highID) .. ")")
    T.ok(Sh.DECredit(high, price, needs) > 0, "without step data the flat needs stand")
end)

T.test("the solver's credit for a guide follows the same rule", function()
    local high, _, mat = highRecipe(100)
    local skills = { [ENCHANTING] = true, [TAILORING] = true }
    local needs = { [mat] = 40 }
    local early = Sh.CreditFor(TAILORING, true, skills, needs, { [mat] = { { to = 50, need = 40 } } })
    local late = Sh.CreditFor(TAILORING, true, skills, needs, { [mat] = { { to = 150, need = 40 } } })
    T.eq(early(0, high, 10), 10, "no credit while Enchanting can't reach it")
    T.ok(late(0, high, 10) < 10, "credit once a step reaches it")
end)

T.test("the incoming dust count leaves out greens the Enchanting skill can't disenchant yet", function()
    local high, highID, mat = highRecipe(100)
    withChar({ committed = {}, lastPlan = { [TAILORING] = { { 100, 110, highID } } } }, function()
        T.eq((Sh.DEIncoming(mat, 50)), 0, "Enchanting at 50 can't disenchant it")
        T.ok(Sh.DEIncoming(mat, 300) > 0, "Enchanting at 300 can: " .. high.name)
        T.ok(Sh.DEIncoming(mat) > 0, "with no Enchanting step to limit it, it counts")
    end)
    withChar({ committed = {}, lastPlan = { [TAILORING] = { { 25, 45, BROWN_LINEN_ROBE } } } }, function()
        T.ok(Sh.DEIncoming(DUST, 10) > 0, "a green that needs 1 counts at Enchanting 10")
    end)
end)
