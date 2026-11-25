-- No detour from a guaranteed point: a step under way holds to its end, even where the
-- limited pattern after it already gives points (Engineering 275: Thorium Widget, then the
-- Thorium Tube pattern).

local CP = ProfLost
local ENG = 202
local WIDGET, TUBE = 19791, 19795

local function live()
    return { guide = CP.Guides[ENG], learned = { [WIDGET] = true }, dead = {}, prof = { id = ENG, skill = 275, max = 300 } }
end

local function texts(plan)
    local out = {}
    for _, st in ipairs(plan) do out[#out + 1] = ("%d-%d:%s"):format(st.from, st.to, tostring(st.spell)) end
    return table.concat(out, ";")
end

T.test("the guide data: Thorium Tube is a limited pattern learned at 275, Widget still orange there", function()
    local g = CP.Guides[ENG]
    T.ok(g.recipes[TUBE].limited and g.recipes[TUBE].pattern, "limited pattern")
    T.eq(g.recipes[TUBE].learn, 275)
    T.ok(275 < g.recipes[WIDGET].yellow, "Widget orange at 275")
end)

T.test("a step under way is not joined into the limited pattern after it", function()
    local plan = { { spell = WIDGET, from = 275, to = 285, crafts = 10, cost = 1, since = 274 },
                   { spell = TUBE, from = 285, to = 300, crafts = 20, cost = 1 } }
    local out = CP.Plan.LimitedOrs(live(), plan)
    T.eq(out[1].spell, WIDGET, "the current step stays: " .. texts(out))
    T.eq(out[1].to, 285)
end)

-- Thorium Widget makes a prep material (15994), so the pattern never takes its step in, even
-- before it is under way (decision 0008 rule 9).
T.test("a maker step not yet under way stays before the pattern, which keeps its 'or' rows", function()
    T.eq(CP.Guides[ENG].prep[15994], WIDGET, "Widget makes a prep material")
    local plan = { { spell = WIDGET, from = 275, to = 285, crafts = 10, cost = 1 },
                   { spell = TUBE, from = 285, to = 300, crafts = 20, cost = 1 } }
    local out, ors = CP.Plan.LimitedOrs(live(), plan)
    T.eq(texts(out), ("275-285:%d;285-300:%d"):format(WIDGET, TUBE))
    local names = {}
    for _, side in ipairs(ors[2] or {}) do names[side.spell] = true end
    T.ok(names[WIDGET], "Widget is the pattern's 'or' row")
end)
