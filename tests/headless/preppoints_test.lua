-- Intermediate crafts earn their points (decision 0008). Player report on
-- 1.2.0, Tailoring 67/150, empty bags: alone the guide read "Bolt of Woolen Cloth 67-73 ~138", whose
-- 138 bolts carry the skill to 85; with Enchanting it read "Woolen Cape 67-97 ~36" with no bolt row.
-- Both read a bolt row, then the capes. Wool Cloth is a creature drop (4.7 effort a cloth, not the
-- 3.5 of the skin it was once read as), so Reinforced Linen Cape covers 67-73 and the bolt row starts
-- at 73. Alone and with Enchanting it runs 73-84, makes 32 and keeps 28 for the capes and shoulders.
-- With Enchanting the silk bolts' settle takes Double-stitched Woolen Shoulders 112-120, so the
-- woolen bolts are sized again on the final picks: 73-85 x47 kept only 27 and left 20 spare.

local CP = ProfLost
local GT = CP.GuideTab
local TAILOR, ENCHANTING = 197, 333
local BOLT, CAPE, SHOULDERS, BOOTS = 2964, 2402, 3848, 18423
local BOLT_ITEM = 2997
local DUROTAR = 1411

local function scene(rank, withEnchanting, bags)
    MapWorld.begin({ zone = DUROTAR, level = 30, side = "Horde" })
    local profs = { [TAILOR] = { rank = rank, max = rank < 150 and 150 or 300 } }
    if withEnchanting then profs[ENCHANTING] = { rank = 60, max = 75 } end
    CraftWorld.begin({ professions = profs, bags = bags or {} })
    World.set(CP.db, "collect", true)
    World.set(CP.db, "hideInCombat", false)
    World.set(CP.charDB, "guideMode", "one")
    World.set(CP.charDB, "committed", nil)
    World.set(CP.charDB, "lastPlan", nil)
    if withEnchanting then
        CraftWorld.Open(ENCHANTING)
        T.advance(1)
        CP.Plan.Current()
        CraftWorld.Close()
        T.advance(1)
    end
end

local function open()
    CraftWorld.Open(TAILOR)
    T.advance(1)
    CP.Panel:Refresh()
    T.advance(0.3)
end

local function mainRows()
    local out = {}
    for _, row in ipairs(GT.ui.rows or {}) do
        if row.spell and not row.side and not (row.rank or row.train) then out[#out + 1] = row end
    end
    return out
end

local function text(row)
    return row and ("%s %d-%d x%d"):format(row.recipe.name, row.from, row.to, row.crafts) or "none"
end

local function card(row)
    GT.Pick(row)
    T.advance(0.3)
    return GT.ui.details.status:GetText() or "", GT.ui.details.sale:GetText() or ""
end

-- The bolt row and its card, then the cape row, as decision 0008 rule 6 reads them. `crafts` is the
-- bolt row's count, `keep` what later steps keep of it.
local function bolts(label, crafts, keep, last, cape)
    local rows = mainRows()
    print(("PREPPOINTS|%s|%s|%s|%s"):format(label, text(rows[1]), text(rows[2]), text(rows[3])))
    T.eq(text(rows[1]), ("Bolt of Woolen Cloth 73-%d x%d"):format(last, crafts), label .. ": the bolt row runs to the bolts' grey")
    T.eq(text(rows[2]), cape, label .. ": the cape row starts where the bolts end")
    T.eq(rows[3] and rows[3].spell, SHOULDERS, label .. ": the shoulders follow")
    local status, note = card(rows[1])
    print(("PREPPOINTS|%s|card|%s|%s"):format(label, status, note))
    T.ok(status:find(("73-%d"):format(last), 1, true) ~= nil, "range: " .. status)
    T.ok(status:find(("~%d crafts"):format(crafts), 1, true) ~= nil, "count: " .. status)
    if keep >= crafts then
        T.ok(status:find("53 for skill-ups", 1, true) ~= nil, "skill-ups: " .. status)
    end
    T.ok(status:find(("keep %d for later"):format(keep), 1, true) ~= nil, "keep: " .. status)
    T.ok(status:find("materials for", 1, true) ~= nil, "materials: " .. status)
    T.ok(note:find(("Keep %d for Woolen Cape, Double-stitched Woolen Shoulders"):format(keep), 1, true) ~= nil, "note: " .. note)
    local capeStatus = card(rows[2])
    print(("PREPPOINTS|%s|cape card|%s"):format(label, capeStatus))
    T.ok(capeStatus:find(cape:match("x(%d+)$") and ("~%s crafts"):format(cape:match("x(%d+)$")) or "", 1, true) ~= nil, "cape count: " .. capeStatus)
    T.ok(capeStatus:find("for skill-ups", 1, true) == nil, "a row that keeps nothing says no skill-ups: " .. capeStatus)
    T.ok(capeStatus:find("first", 1, true) == nil, "the bolt row before it makes the bolts: " .. capeStatus)
end

T.test("Tailoring 73 alone: the bolt row runs 73-84 for the capes and shoulders", function()
    scene(73, false)
    open()
    bolts("alone", 32, 28, 84, "Woolen Cape 84-97 x19")
    CraftWorld.Close()
end)

T.test("Tailoring 73 with Enchanting: the bolt row makes only what the capes and shoulders keep", function()
    scene(73, true)
    open()
    bolts("with Enchanting", 32, 28, 84, "Woolen Cape 84-97 x19")
    CraftWorld.Close()
end)

T.test("the cape card asks no bolts first while the bags hold the ones the bolt row made", function()
    scene(73, false)
    open()
    T.eq(text(mainRows()[1]), "Bolt of Woolen Cloth 73-84 x32", "the bolt row leads")
    -- The bolt row done: its 53 bolts in the bags, the skill at the bolts' grey.
    CraftWorld.SetBag(BOLT_ITEM, 53)
    CraftWorld.SetSkill(TAILOR, 85, 150)
    CP.Plan.Invalidate()
    T.advance(1)
    CP.Panel:Refresh()
    T.advance(0.3)
    local cape = mainRows()[1]
    T.eq(cape and cape.spell, CAPE, "the cape step is current at 85: " .. text(cape))
    local status = card(cape)
    print(("PREPPOINTS|85 with 53 bolts|%s|%s"):format(text(cape), status))
    T.ok(status:find("first", 1, true) == nil, "no make N first: " .. status)
    for _, line in ipairs(GT.ui.details.rows) do
        if line:IsShown() and line.itemID == BOLT_ITEM then
            T.eq(line.tag:GetText() or "", "", "the bolt line asks nothing made")
        end
    end
    CraftWorld.Close()
end)

T.test("the stop line stays quiet past the bolts' end while the row's count is unmet", function()
    scene(73, false)
    open()
    local row = mainRows()[1]
    T.eq(row and row.spell, BOLT, "the bolt step leads")
    GT.Pick(row)
    T.advance(0.3)
    CP.Crafting.Start(BOLT, row.crafts)
    T.advance(0.5)
    T.eq(CP.Crafting.stepEnd, 84, "the batch noted the row's end")
    CraftWorld.SetSkill(TAILOR, 85, 150)
    CP.Panel:Refresh()
    T.advance(0.5)
    T.ok(CP.Crafting.Busy(), "the batch still runs")
    T.ok((GT.ui.details.sale:GetText() or ""):find("Stop the batch", 1, true) == nil,
        "no stop line while bolts are still owed: " .. (GT.ui.details.sale:GetText() or ""))
    T.ok(not CP.Crafting.Overshoot(85), "no overshoot at 85 with the count unmet")
    CP.Crafting.Stop()
    CraftWorld.Close()
end)

T.test("a batch whose crafts reach the row's count says stop at the row's end", function()
    scene(73, false)
    open()
    local row = mainRows()[1]
    GT.Pick(row)
    T.advance(0.3)
    CP.Crafting.Start(BOLT, row.crafts + 5)
    T.advance(0.5)
    T.eq(CP.Crafting.stepCount, row.crafts, "the batch noted the row's count")
    World.set(CP.Crafting, "count", 4)
    CraftWorld.SetSkill(TAILOR, 85, 150)
    CP.Panel:Refresh()
    T.advance(0.5)
    T.ok(CP.Crafting.Overshoot(85), "the count is met: overshoot")
    CP.Crafting.Stop()
    CraftWorld.Close()
end)

-- Version 2 and 3 plans (decision 0008 rule 4): one breaking rule 1 is solved afresh once; a clean
-- one keeps its locks and is marked the current version.
local function saveOld(steps, skill, version, prof)
    prof = prof or TAILOR
    local ctx = CP.Plan.Context(prof)
    local all = { [ctx] = { version = version or 2, ctx = ctx, steps = steps, made = 0, skill = skill, shown = true,
                            curKey = CP.Plan.StepKey(steps[1]) } }
    World.set(CP.charDB, "committed", { [prof] = all })
    World.set(CP.charDB, "lastPlan", prof == TAILOR and { [TAILOR] = { { 67, 73, BOLT } } } or nil)
    return ctx
end

T.test("a version 2 plan holding Bolt of Woolen Cloth 67-73 x138 is solved afresh", function()
    scene(67, false)
    local ctx = saveOld({
        { 67, 73, BOLT, nil, 7, 138, { "Woolen Cape", "Double-stitched Woolen Shoulders" }, 0, 138 },
        { 73, 97, CAPE, nil, 30, nil, nil, 0, 30 },
        { 97, 127, SHOULDERS, nil, 36, nil, nil, 0, 36 },
    }, 67)
    open()
    local rows = mainRows()
    print(("PREPPOINTS|v2 67-73|%s|%s"):format(text(rows[1]), text(rows[2])))
    T.eq(text(rows[1]), "Reinforced Linen Cape 67-73 x9", "the stale bolt row gave way")
    local c = CP.charDB.committed[TAILOR][ctx]
    T.eq(c and c.version, CP.Plan.COMMIT_VERSION, "saved again at the current version")
    CraftWorld.Close()
end)

for _, version in ipairs({ 2, 3 }) do
    T.test(("a clean version %d plan keeps its locked step and is marked the current version"):format(version), function()
        scene(260, false)
        local ctx = saveOld({ { 260, 266, BOOTS, nil, 11, nil, nil, 0, 11 } }, 260, version)
        open()
        local rows = mainRows()
        print(("PREPPOINTS|v%d clean|%s"):format(version, text(rows[1])))
        T.eq(text(rows[1]), "Runecloth Boots 260-266 x11", "the locked step holds")
        local c = CP.charDB.committed[TAILOR][ctx]
        T.eq(CP.Plan.COMMIT_VERSION, 5, "the current version")
        T.eq(c and c.version, 5, "re-marked version 5")
        CraftWorld.Close()
    end)
end

-- Rule 4 as amended: a version 3 plan saved before rule 10 holds "Coarse Blasting Powder 75-90, 45"
-- with a keep of 45. The powder is no prep, but the row keeps, and its 45 crafts play to 95.
local ENGINEERING, POWDER, DYNAMITE = 202, 3929, 3931

T.test("a version 3 plan holding a keep row that plays past its end is solved afresh", function()
    MapWorld.begin({ zone = DUROTAR, level = 30, side = "Horde" })
    CraftWorld.begin({ professions = { [ENGINEERING] = { rank = 75, max = 150 } }, bags = {} })
    World.set(CP.db, "collect", false)
    World.set(CP.db, "hideInCombat", false)
    World.set(CP.charDB, "guideMode", "one")
    local ctx = saveOld({
        { 75, 90, POWDER, nil, 17, 45, { "Coarse Dynamite", "Large Copper Bomb", "Aquadynamic Fish Attractor" }, 0, 45 },
        { 90, 94, DYNAMITE, nil, 5, nil, nil, 0, 5 },
    }, 75, 3, ENGINEERING)
    CraftWorld.Open(ENGINEERING)
    T.advance(1)
    CP.Panel:Refresh()
    T.advance(0.3)
    local rows = mainRows()
    print(("PREPPOINTS|v3 powder|%s|%s"):format(text(rows[1]), text(rows[2])))
    T.eq(text(rows[1]), "Coarse Blasting Powder 75-90 x17", "the stale powder row gave way")
    local c = CP.charDB.committed[ENGINEERING][ctx]
    T.eq(c and c.version, CP.Plan.COMMIT_VERSION, "saved again at the current version")
    CraftWorld.Close()
end)

-- Rule 8: a maker a locked step blocks. Tailoring at 44, no bolts, Coarse Thread in the bags locks the
-- saved Linen Belt 45-67 (0007). The settle stops at the belt, so Bolt of Linen Cloth 44-45 carries the
-- whole need as its count; made in full it plays past 45 into the belt's range, under the bolts' grey.
-- The real solver plans Bolt of Woolen Cloth from 67, not 0008's hand example's Reinforced Linen Cape
-- 67-77, so the need is the belt's 28 bolts (not 60) and they play to 48.3 (not 49.95).
local LINEN_BOLT, LINEN_BOLT_ITEM, BELT, COARSE_THREAD = 2963, 2996, 8776, 2320

T.test("rule 8: a locked Linen Belt blocks the bolts; the bolt row keeps the whole need", function()
    MapWorld.begin({ zone = DUROTAR, level = 30, side = "Horde" })
    CraftWorld.begin({ professions = { [TAILOR] = { rank = 44, max = 75 } }, bags = { [COARSE_THREAD] = 28 } })
    World.set(CP.db, "collect", true)
    World.set(CP.db, "hideInCombat", false)
    World.set(CP.charDB, "guideMode", "one")
    World.set(CP.charDB, "lastPlan", nil)
    local ctx = CP.Plan.Context(TAILOR)
    local steps = { { 45, 67, BELT, nil, 28, nil, nil, 0, 28 }, { 67, 77, 2397, nil, 16, nil, nil, 0, 16 } }
    World.set(CP.charDB, "committed", { [TAILOR] = { [ctx] = { version = CP.Plan.COMMIT_VERSION, ctx = ctx,
        steps = steps, made = 0, skill = 44, shown = true, curKey = CP.Plan.StepKey(steps[1]) } } })
    open()
    local rows = mainRows()
    print(("PREPPOINTS|rule 8|%s|%s|%s"):format(text(rows[1]), text(rows[2]), text(rows[3])))
    T.eq(rows[1] and rows[1].spell, LINEN_BOLT, "the bolts lead: " .. text(rows[1]))
    T.eq(rows[1] and ("%d-%d"):format(rows[1].from, rows[1].to), "44-45", "the settle stops at the locked belt")
    T.eq(text(rows[2]), "Linen Belt 45-67 x28", "the locked belt holds")
    -- The whole need: every later row's bolts up to the next bolt row.
    local need = 0
    for i = 2, #rows do
        if rows[i].recipe.makes == LINEN_BOLT_ITEM then break end
        for _, pair in ipairs(rows[i].recipe.reagents) do
            if pair[1] == LINEN_BOLT_ITEM then need = need + pair[2] * rows[i].crafts end
        end
    end
    T.eq(rows[1] and rows[1].crafts, need, "the bolt row's count is the whole need")
    local bolt = CP.Guides[TAILOR].recipes[LINEN_BOLT]
    local played = CP.Solver.Play(bolt, 44, rows[1] and rows[1].crafts or 0)
    print(("PREPPOINTS|rule 8|%d bolts from 44 play to %.2f"):format(rows[1] and rows[1].crafts or 0, played))
    -- SimCheck.RowPoints's blocked bound (that file is not loaded headless): no lower than the end less
    -- the slack, no higher than the lower of the bolts' grey and the belt's end.
    T.ok(played >= 45 - 1 and played <= math.min(bolt.grey, 67), ("within the blocked bound: %.2f"):format(played))
    T.ok(played > 45 + 1, "past the plain slack, so only the blocked bound passes it")
    CraftWorld.Close()
end)

-- A maker row makes what real consumers keep. Its keep, played from the row's start, reaches the row's
-- end within rowpoints' slack, unless the pick loop chose the maker there on its own merit (the
-- unsettled solve has a run of it reaching that end). Every guide with makers, from 1, both modes.
local GUIDES = { { "Alchemy", 171 }, { "Blacksmithing", 164 }, { "Engineering", 202 }, { "Leatherworking", 165 },
                 { "Tailoring", TAILOR }, { "Tailoring with Enchanting", TAILOR, ENCHANTING } }

local function solved(p, collect, settle)
    MapWorld.begin({ zone = DUROTAR, level = 30, side = "Horde" })
    local profs = { [p[2]] = { rank = 1, max = 300 } }
    if p[3] then profs[p[3]] = { rank = 1, max = 300 } end
    CraftWorld.begin({ professions = profs, bags = {} })
    World.set(CP.db, "collect", collect)
    World.set(CP.db, "hideInCombat", false)
    World.set(CP.charDB, "committed", nil)
    World.set(CP.charDB, "lastPlan", nil)
    World.set(CP.Solver, "SETTLE", settle)
    CP.Plan.Invalidate()
    if p[3] then
        CraftWorld.Open(p[3])
        T.advance(1)
        CP.Plan.Current()
        CraftWorld.Close()
        T.advance(1)
    end
    CraftWorld.Open(p[2])
    T.advance(1)
    local live = CP.Plan.Current()
    CraftWorld.Close()
    return live
end

for _, collect in ipairs({ true, false }) do
    for _, p in ipairs(GUIDES) do
        T.test(("%s from 1, %s: no maker row makes more than its consumers keep"):format(p[1],
            collect and "Level-as-you-go" or "buy"), function()
            local live = solved(p, collect, true)
            local guide = live.guide
            local prep, craftOnly = guide.prep or {}, guide.craftOnly or {}
            local keeps = CP.Guide.Keeps(guide, live.plan, {})
            local plain = solved(p, collect, false).plan
            for i, st in ipairs(live.plan) do
                local r = st.spell and guide.recipes[st.spell]
                if r and r.makes and (prep[r.makes] or craftOnly[r.makes]) then
                    local keep = keeps[i] and keeps[i].count or 0
                    local reach = CP.Solver.Play(r, st.from, keep / (r.yield or 1))
                    local merit = false
                    for _, u in ipairs(plain) do
                        if u.spell == st.spell and u.from < st.to and u.to >= st.to - 1 then merit = true end
                    end
                    print(("PREPPOINTS|spare|%s|%s %d-%d x%d keep %d plays to %.1f%s"):format(p[1], r.name, st.from,
                        st.to, st.crafts, keep, reach, merit and ", the pick loop's own run" or ""))
                    T.ok(reach >= st.to - 1 or merit, ("%s %d-%d makes %d, its consumers keep %d, which play to %.1f"):format(
                        r.name, st.from, st.to, st.crafts, keep, reach))
                end
            end
        end)
    end
end
