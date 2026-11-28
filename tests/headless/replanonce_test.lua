-- A plan picked before Level-as-you-go costed a gathered material by its own loot chance is solved
-- afresh once, its current step too (owner, 2026-11-28: "I just want it to be a one-time patch. This
-- was a bug on our part and now we need to fix it."). A plan with the `costfix` mark holds as decision
-- 0007 says. The guide chooses the step: no row offers a cheaper recipe, and no click on a row moves
-- the current step ("I don't want to be able to choose steps at will.").
-- The case: Leatherworking 165, Green Whelp Bracers 165-175 saved under the old costs, 4 of 10 made.
-- Under today's costs the bracers win here, so the cases that need another pick make the scale take
-- a hundred times the skins, as a cost correction would.

local CP = ProfLost
local GT = CP.GuideTab
local LW, SKINNING = 165, 393
local BRACERS, SHOULDERS, HIDE, SCALE = 9202, 7151, 4235, 7392

-- Every trainer recipe up to `rank`, and the bracers' pattern.
local function known(rank)
    local out = { BRACERS }
    for id, r in pairs(CP.Guides[LW].recipes) do
        if (r.src == "trainer" or r.src == "auto") and (r.learn or 1) <= rank then out[#out + 1] = id end
    end
    return out
end

-- Leatherworking 165 with Skinning 290 at level 40 under Gather it yourself.
local function character(bags)
    MapWorld.begin({ zone = 1417, level = 40, side = "Horde" })
    CraftWorld.begin({ professions = { [LW] = { rank = 165, max = 225, known = known(165) },
                                       [SKINNING] = { rank = 290, max = 300 } }, bags = bags })
    World.set(CP.db, "collect", true)
    World.set(CP.charDB, "lastPlan", nil)
    World.set(CP.charDB, "committed", nil)
    World.set(CP.Plan, "Corrected", {})
    CP.Plan.Invalidate()
end

-- The scale costs a hundred times the skins it did.
local function dearScale()
    local item = CP.Guides[LW].items[SCALE]
    World.set(item, 4, item[4] * 100)
end

-- Recipe `spell` 165-175 saved as the current step with 4 of 10 made; `fields` adds to the saved plan.
local function saved(spell, fields)
    local ctx = CP.Plan.Context(LW)
    local c = { version = CP.Plan.COMMIT_VERSION, ctx = ctx, reach = true, shown = true, skill = 165, made = 4,
                curKey = spell .. ":165:175", current = 1,
                steps = { { 165, 175, spell, nil, 10, nil, nil, nil, 10 } } }
    for k, v in pairs(fields or {}) do c[k] = v end
    World.set(CP.charDB, "committed", { [LW] = { [ctx] = c } })
    World.set(CP.charDB, "lastPlan", nil)
    CP.Plan.Invalidate()
end

local function mainRows()
    local out = {}
    for _, row in ipairs(GT.ui.rows) do
        if row.spell and not row.side and not (row.rank or row.train) then out[#out + 1] = row end
    end
    return out
end

local function stepText(row) return row and ("%d %d-%d x%d"):format(row.spell, row.from, row.to, row.crafts or 0) or "none" end

local function status() return GT.ui.details.status:GetText() or "" end

local function noted() return status():find(CP.Plan.CORRECTED, 1, true) == 1 end

-- The window open: the current step's row, picked.
local function look()
    CraftWorld.Open(LW)
    T.advance(1)
    CP.Panel:Refresh()
    local cur = mainRows()[1]
    if cur then
        GT.Pick(cur)
        T.advance(0.3)
    end
    return cur
end

-- What a solve with no saved plan picks first; `dear` makes the scale dear first.
local function fresh(dear)
    character()
    if dear then dearScale() end
    local cur = look()
    CraftWorld.Close()
    return cur and cur.spell
end

T.test("a plan saved before the cost fix is solved again once, its current step too", function()
    local want = fresh(true)
    T.ok(want ~= nil and want ~= BRACERS, "a fresh solve picks another step than the bracers: " .. tostring(want))

    character()
    dearScale()
    saved(BRACERS)
    local cur = look()
    print(("REPLANONCE|resolved|want %s|%s|%s"):format(tostring(want), stepText(cur), status()))
    T.eq(cur and cur.spell, want, "the current step follows the fixed costs")
    local c = CP.Plan.Committed(LW)
    T.ok(c and c.costfix, "the plan is marked")
    T.eq(c and c.made, 0, "the new step starts its crafts at 0")
    T.ok(noted(), "the card says the guide was updated: " .. status())

    -- The next craft of the new step clears the line.
    T.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", cur.spell)
    T.advance(0.3)
    CP.Panel:Refresh()
    GT.Pick(mainRows()[1])
    T.advance(0.3)
    T.ok(not noted(), "a craft clears the line: " .. status())

    -- A second load solves nothing again.
    local key = CP.Plan.Committed(LW).curKey
    CP.Plan.ForgetBook()
    CP.Plan.Invalidate()
    look()
    T.eq(CP.Plan.Committed(LW).curKey, key, "the step holds after the one re-solve")
    CraftWorld.Close()
end)

T.test("a reload clears the line", function()
    character()
    dearScale()
    saved(BRACERS)
    look()
    T.ok(noted(), "the line shows: " .. status())
    CraftWorld.Close()
    World.set(CP.Plan, "Corrected", {})
    CP.Plan.Invalidate()
    look()
    T.ok(not noted(), "gone after a reload: " .. status())
    CraftWorld.Close()
end)

-- The cost fix changed Level-as-you-go only (owner, 2026-11-28: "Limit it to level as you go").
T.test("a Buy-and-power-level plan saved before the cost fix holds its current step", function()
    character()
    World.set(CP.db, "collect", false)
    CP.Plan.Invalidate()
    saved(BRACERS, { steps = { { 165, 175, BRACERS, nil, 10, nil, nil, nil, 10 } },
                     made = 4, curKey = BRACERS .. ":165:175" })
    local c = CP.Plan.Committed(LW)
    T.ok(c and not tostring(c.ctx):find("collect=true", 1, true), "a Buy-and-power-level plan: " .. tostring(c and c.ctx))
    local cur = look()
    print(("REPLANONCE|buy|%s|%s"):format(stepText(cur), status()))
    T.eq(stepText(cur), ("%d 165-175 x6"):format(BRACERS), "the bracers hold with 6 left")
    T.ok(not noted(), "no line: " .. status())
    c = CP.Plan.Committed(LW)
    T.ok(c and c.costfix, "the plan is marked, so it is never checked again")
    CraftWorld.Close()
end)

T.test("the same plan with the mark holds its current step (decision 0007)", function()
    character()
    dearScale()
    saved(BRACERS, { costfix = true })
    local cur = look()
    print(("REPLANONCE|marked|%s|%s"):format(stepText(cur), status()))
    T.eq(stepText(cur), ("%d 165-175 x6"):format(BRACERS), "the bracers hold with 6 left")
    T.ok(not noted(), "no line: " .. status())
    CraftWorld.Close()
end)

T.test("a re-solve that still picks the saved recipe changes nothing visible", function()
    T.eq(fresh(false), BRACERS, "today's costs pick the bracers here")
    character()
    saved(BRACERS)
    local cur = look()
    T.eq(stepText(cur), ("%d 165-175 x6"):format(BRACERS), "the bracers hold as saved, 4 made")
    T.ok(not noted(), "no line: " .. status())
    T.ok(CP.Plan.Committed(LW).costfix, "the plan is marked")
    CraftWorld.Close()
end)

T.test("a step an \"or\" row click put in is solved again once too", function()
    -- The owner's character: Barbaric Shoulders made current by a click, with no mark.
    local want = fresh(false)
    character({ [HIDE] = 10 })
    saved(SHOULDERS, { made = 0 })
    local cur = look()
    print(("REPLANONCE|swapped|want %s|%s|%s"):format(tostring(want), stepText(cur), status()))
    T.eq(cur and cur.spell, want, "the guide's own pick replaces the clicked step")
    T.ok(noted(), "the card says the guide was updated: " .. status())
    CraftWorld.Close()
end)

T.test("no row offers a cheaper recipe, and no click on a row changes the current step", function()
    character({ [HIDE] = 10 })
    saved(BRACERS, { costfix = true })
    local cur = look()
    local key = CP.Plan.Committed(LW).curKey
    T.eq(stepText(cur), ("%d 165-175 x6"):format(BRACERS), "the bracers hold")
    local rows = {}
    for _, row in ipairs(GT.ui.rows) do rows[#rows + 1] = row end
    T.ok(#rows > 1, "rows to click")
    for _, row in ipairs(rows) do
        T.eq(row.cheaper, nil, "no cheaper row: " .. stepText(row.spell and row or nil))
        GT.Pick(row)
        T.advance(0.3)
        T.ok(not status():find("Cheaper now", 1, true), "no card offers a cheaper recipe: " .. status())
        T.eq(CP.Plan.Committed(LW).curKey, key, "a click leaves the current step: " .. tostring(row.key))
    end
    CraftWorld.Close()
end)
