-- One recipe's run is one guide row (SPLITROW-01). Owner, `/proflost preview tailoring 50`: the
-- guide listed "Woolen Cape 73-75" then "Woolen Cape 75-97". The plan cuts a step at a rank's
-- cap (Guide.SplitAtCaps), but Journeyman rides the trainer visit at 55, so nothing stands at 75.
-- Guide.JoinRuns draws the two parts as one row; a stop row between them, the current row, a
-- locked step and a step with "or" rows keep theirs. Since decision 0008 the run that crosses 75 is
-- Bolt of Woolen Cloth 55-85, made for the capes and shoulders after it.

local CP = ProfLost
local GT = CP.GuideTab
local TAILORING = 197
local CAPE, BOLT, WOOL = 2402, 2964, 2592

-- The guide window's rows as text, stop rows included.
local function layout()
    local out = {}
    for _, row in ipairs(GT.ui.rows) do
        if row.rank then
            out[#out + 1] = "rank " .. row.rank.name
        elseif row.train then
            out[#out + 1] = "train " .. row.train.skill
        elseif row.spell and not row.side then
            out[#out + 1] = ("%s %d-%d x%d"):format(row.recipe and row.recipe.name or row.spell, row.from, row.to, row.crafts or 0)
        end
    end
    return table.concat(out, "; ")
end

-- Main craft rows of one recipe that touch with no row between: "A 73-75 / A 75-97" each.
local function splits(rows)
    local out, prev = {}, nil
    for _, row in ipairs(rows) do
        local step = row.spell and not row.side and not (row.rank or row.train)
        if row.side then
            -- An "or" row belongs to the row above; it sits between nothing.
        elseif step and prev and prev.spell == row.spell and prev.to == row.from then
            out[#out + 1] = ("%s %d-%d / %d-%d"):format(row.recipe.name, prev.from, prev.to, row.from, row.to)
            prev = row
        else
            prev = step and row or nil
        end
    end
    return out
end

local function rowsOf(spell)
    local out = {}
    for _, row in ipairs(GT.ui.rows) do
        if row.spell == spell and not row.side then out[#out + 1] = row end
    end
    return out
end

local function scene(skill, bags)
    MapWorld.begin({ zone = 1454, level = 30, side = "Horde" })
    CraftWorld.begin({ professions = { [TAILORING] = { rank = skill, max = 75 } }, bags = bags or {} })
    World.set(CP.db, "collect", true)
    World.set(CP.charDB, "committed", nil)
    World.set(CP.charDB, "lastPlan", nil)
    CraftWorld.Open(TAILORING)
    T.advance(1)
    CP.Panel:Refresh()
end

T.test("the owner's case: Tailoring 50, the run through 75 is one row", function()
    scene(50)
    local text = layout()
    print("SPLITROW|tailoring 50|" .. text)
    T.ok(text:find("rank Journeyman Tailoring; train 55", 1, true) ~= nil, "Journeyman rides the visit at 55: " .. text)
    local bolts = rowsOf(BOLT)
    T.eq(#bolts, 1, "one Bolt of Woolen Cloth row: " .. text)
    T.eq(bolts[1] and bolts[1].from, 55)
    T.eq(bolts[1] and bolts[1].to, 85)
    T.eq(bolts[1] and bolts[1].crafts, bolts[1] and bolts[1].keep and bolts[1].keep.count, "the count is what later steps keep")
    T.eq(#rowsOf(CAPE), 1, "one Woolen Cape row: " .. text)
    T.eq(#splits(GT.ui.rows), 0, table.concat(splits(GT.ui.rows), "; "))
end)

T.test("the plan itself keeps the bolt run whole while Journeyman rides the visit at 55", function()
    scene(50)
    local live = CP.Plan.Current()
    local bolts = {}
    for _, st in ipairs(live.plan) do
        if st.spell == BOLT then bolts[#bolts + 1] = ("%d-%d"):format(st.from, st.to) end
    end
    T.eq(table.concat(bolts, ", "), "55-85", "one Bolt of Woolen Cloth step")
end)

T.test("with no trainer visit before the cap, the step is cut there and the rank sits between", function()
    scene(74)
    local text = layout()
    print("SPLITROW|tailoring 74|" .. text)
    -- The part that ends at grey keeps the surplus (decision 0008, rule 3).
    T.ok(text:find("Bolt of Woolen Cloth 74-75 x2; rank Journeyman Tailoring; Bolt of Woolen Cloth 75-85 x124", 1, true) ~= nil, text)
end)

T.test("SplitAtCaps: a rank on a trainer visit before its cap cuts nothing; without the solve's known set it cuts", function()
    MapWorld.begin({ zone = 1454, level = 30, side = "Horde" })
    local guide = CP.Guides[TAILORING]
    -- Woolen Bag (learn 50) is trained at 55 and Journeyman (cap 75) rides that visit.
    local function steps(learned)
        local out = { { spell = 3757, from = 55, to = 64, crafts = 12 }, { spell = CAPE, from = 64, to = 90, crafts = 30 } }
        out.learned = learned
        return out
    end
    local whole = CP.Guide.SplitAtCaps(guide, steps({ [CAPE] = true }), 75)
    T.eq(#whole, 2, "the cape step stays whole")
    T.eq(whole[2].to, 90)
    local cut = CP.Guide.SplitAtCaps(guide, steps(nil), 75)
    T.eq(#cut, 3, "cut at 75")
    T.eq(cut[2].to, 75)
    -- Everything known: no visit before 75, so the rank stands at its cap.
    local all = {}
    for id in pairs(guide.recipes) do all[id] = true end
    T.eq(#CP.Guide.SplitAtCaps(guide, steps(all), 75), 3, "cut at 75 with no visit")
end)

T.test("a saved step through a cap whose rank lost its visit is drawn cut there, the rank between", function()
    -- Planned while Journeyman rode a visit; every recipe known since, so it stands at 75.
    MapWorld.begin({ zone = 1454, level = 30, side = "Horde" })
    local guide = CP.Guides[TAILORING]
    local all = {}
    for id in pairs(guide.recipes) do all[id] = true end
    local function text(rows)
        local out = {}
        for _, row in ipairs(rows) do
            out[#out + 1] = row.rank and ("rank " .. row.rank.name .. " @" .. row.at)
                or ("%d-%d x%d%s"):format(row.from, row.to, row.crafts, row.current and " current" or "")
        end
        return table.concat(out, "; ")
    end
    local steps = { { spell = 3757, from = 70, to = 73, crafts = 4, key = 70, current = true },
                    { spell = CAPE, from = 73, to = 97, crafts = 32, key = 73 } }
    T.eq(text(CP.Guide.WithStops(guide, steps, all, 70, 75, 30, {})),
        "70-73 x4 current; 73-75 x4; rank Journeyman Tailoring @75; 75-97 x28")
    -- The current step keeps its one row, as its card and Next up count it; the rank leads it.
    steps = { { spell = CAPE, from = 73, to = 97, crafts = 32, key = 73, current = true } }
    T.eq(text(CP.Guide.WithStops(guide, steps, all, 73, 75, 30, {})), "rank Journeyman Tailoring @73; 73-97 x32 current")
end)

T.test("a picked joined row's card counts the whole run", function()
    scene(50)
    local bolt = rowsOf(BOLT)[1]
    GT.Pick(bolt)
    T.advance(0.3)
    local live = CP.Plan.Current()
    local sel = GT.Selected(live, true)
    T.eq(sel and sel.spell, BOLT)
    T.eq(sel and sel.to, 85)
    T.eq(sel and sel.crafts, bolt.crafts)
end)

-- A plan saved before the fix holds the cut at 75 (Plan.Commit keeps a route that costs the same).
local function savedCut(bags)
    local riding = CP.Guide.RidingRanks
    World.set(CP.Guide, "RidingRanks", function() return {} end)
    scene(50, bags)
    World.set(CP.Guide, "RidingRanks", riding)
    CP.Plan.Invalidate()
    CP.Panel:Refresh()
    T.advance(0.3)
    local cut = {}
    for _, f in ipairs(CP.Plan.Committed(TAILORING).steps) do
        if f[3] == BOLT then cut[#cut + 1] = ("%d-%d"):format(f[1], f[2]) end
    end
    return table.concat(cut, ", ")
end

T.test("a saved plan's old cut shows as one row", function()
    T.eq(savedCut(), "55-75, 75-85", "the saved plan holds the cut")
    local bolts = rowsOf(BOLT)
    T.eq(#bolts, 1, "one row: " .. layout())
    T.eq(bolts[1] and ("%d-%d"):format(bolts[1].from, bolts[1].to), "55-85")
end)

T.test("a locked part of a saved cut keeps its row", function()
    -- Wool Cloth in the bags starts the first bolt step (decision 0007), which locks it.
    T.eq(savedCut({ [WOOL] = 6 }), "55-75, 75-85", "the saved plan holds the cut")
    local text = layout()
    print("SPLITROW|tailoring 50, 2 bolts, saved cut|" .. text)
    local c = CP.Plan.Committed(TAILORING)
    local locks = CP.Plan.Locks(c, CP.Guides[TAILORING], 50, CP.Plan.Current().learned, {})
    local locked
    for i in pairs(locks) do
        if c.steps[i][3] == BOLT then locked = ("%d-%d"):format(c.steps[i][1], c.steps[i][2]) end
    end
    T.eq(locked, "55-75", "the first part is locked")
    T.ok(text:find("Bolt of Woolen Cloth 55%-75 x%d+; Bolt of Woolen Cloth 75%-85") ~= nil, "both rows stay: " .. text)
end)

local function step(spell, from, to, crafts, extra)
    local row = { spell = spell, from = from, to = to, crafts = crafts, cost = crafts * 10 }
    for k, v in pairs(extra or {}) do row[k] = v end
    return row
end

T.test("JoinRuns: touching parts of one recipe join; crafts, cost and keeps add up", function()
    local rows = CP.Guide.JoinRuns({
        step(1, 10, 20, 12, { keep = { count = 5, names = { "Cloak" } } }),
        step(1, 20, 30, 14, { keep = { count = 3, names = { "Cloak", "Vest" } } }),
        step(2, 30, 40, 9),
    })
    T.eq(#rows, 2)
    T.eq(rows[1].from, 10)
    T.eq(rows[1].to, 30)
    T.eq(rows[1].crafts, 26)
    T.eq(rows[1].cost, 260)
    T.eq(rows[1].keep.count, 8)
    T.eq(table.concat(rows[1].keep.names, ","), "Cloak,Vest")
end)

T.test("JoinRuns: a stop row, the current row, a held row or a gap keeps the parts apart", function()
    local train = { key = "train20", train = { skill = 20 } }
    local rank = { key = "rank50", rank = { name = "Journeyman" } }
    T.eq(#CP.Guide.JoinRuns({ step(1, 10, 20, 5), train, step(1, 20, 30, 5) }), 3, "a trainer visit")
    T.eq(#CP.Guide.JoinRuns({ step(1, 10, 20, 5), rank, step(1, 20, 30, 5) }), 3, "a rank")
    T.eq(#CP.Guide.JoinRuns({ step(1, 10, 20, 5, { current = true }), step(1, 20, 30, 5) }), 2, "the current row")
    local held = step(1, 20, 30, 5)
    T.eq(#CP.Guide.JoinRuns({ step(1, 10, 20, 5), held }, function(r) return r == held end), 2, "a held row")
    T.eq(#CP.Guide.JoinRuns({ step(1, 10, 20, 5), step(1, 21, 30, 5) }), 2, "ranges that don't touch")
    T.eq(#CP.Guide.JoinRuns({ step(1, 10, 20, 5), step(2, 20, 30, 5) }), 2, "another recipe")
    T.eq(#CP.Guide.JoinRuns({ step(1, 10, 20, 5), step(1, 20, 30, 5), step(1, 30, 40, 5) }), 1, "three parts")
end)
