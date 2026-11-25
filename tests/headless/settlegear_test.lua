-- A maker settles into the start of a step that uses craft-only gear (decision 0008 rule 1).
-- Release run on b40ff62, leatherworking-*-buy-returning40nobook-s1: "Dark Leather Belt 100-120
-- ~20 crafts, with 20 Cured Medium Hide first plays to 124.0". The belt uses Fine Leather Belts
-- (craft-only gear), and the settle never overwrote such a step, so the 20 hides' points at 100
-- (green until 105) went on no row.

local CP = ProfLost
local lw = CP.Guides[165]
local FINE_BELT, DARK_BELT, CURED_MEDIUM = 3763, 3766, 3817

local function listPrice(_, g) return g and g[1] > 0 and g[1] or nil end

local function plan()
    local only = { [FINE_BELT] = true, [DARK_BELT] = true, [CURED_MEDIUM] = true }
    return CP.Solver.Plan(lw, 85, {}, listPrice, function(id) return only[id] == true end, nil, {})
end

local function text(st)
    local r = st.spell and lw.recipes[st.spell]
    return ("%s %d-%d"):format(r and r.name or "-", st.from, st.to)
end

T.test("Cured Medium Hide settles before the Dark Leather Belt it feeds", function()
    local steps = plan()
    local hide, belt
    for _, st in ipairs(steps) do
        if st.spell == CURED_MEDIUM then hide = st end
        if st.spell == DARK_BELT then belt = st end
    end
    local all = {}
    for _, st in ipairs(steps) do all[#all + 1] = text(st) end
    print("SETTLEGEAR|" .. table.concat(all, "; "))
    T.ok(hide ~= nil, "the plan makes the hides on a row of their own: " .. table.concat(all, "; "))
    T.ok(belt ~= nil, "the plan has the belt row")
    if not (hide and belt) then return end
    T.eq(hide.from, 100, "the hides start where the belt did")
    T.eq(hide.to, belt.from, "the belt starts where the hides end")

    -- The hides the belt row needs, made first, take the skill to the belt row's start.
    local need = belt.crafts
    local played = CP.Solver.Play(lw.recipes[CURED_MEDIUM], hide.from, need)
    T.ok(math.abs(played - belt.from) <= 1, ("%d hides from %d play to %.2f, not %d"):format(need, hide.from,
        played, belt.from))
    local after = CP.Solver.Play(lw.recipes[DARK_BELT], belt.from, belt.crafts)
    T.ok(math.abs(after - belt.to) <= 1, ("the belt row's count plays to %.2f, not %d"):format(after, belt.to))
end)

T.test("a step that makes craft-only gear still blocks the settle", function()
    local steps = plan()
    local fine
    for _, st in ipairs(steps) do
        if st.spell == FINE_BELT then fine = st end
    end
    T.ok(fine ~= nil and fine.from == 85 and fine.to == 100, "Fine Leather Belt keeps 85-100")
end)
