-- Plan.RouteCost counts each item once. A maker row pays its own materials, and the steps after it
-- take its output for free; only what the route's own maker rows leave short costs, at maker cost.
-- Plan.Better compares routes with it, so a route with a bolt row must not lose to a bolt-free one
-- on a bolt counted twice.

local CP = ProfLost
local TAILOR = 197
local SILK_BOLT, SHIRT = 3839, 3870
local DUROTAR = 1411

T.test("Tailoring 100 alone: silk bolts 100-120 then Dark Silk Shirt 120-127 cost each bolt once", function()
    MapWorld.begin({ zone = DUROTAR, level = 30, side = "Horde" })
    CraftWorld.begin({ professions = { [TAILOR] = { rank = 100, max = 150 } }, bags = {} })
    World.set(CP.db, "collect", true)
    World.set(CP.charDB, "committed", nil)
    World.set(CP.charDB, "lastPlan", nil)
    CraftWorld.Open(TAILOR)
    T.advance(1)
    local live = CP.Plan.Current()
    local guide = live.guide
    local route = { { spell = SILK_BOLT, from = 100, to = 120 }, { spell = SHIRT, from = 120, to = 127 } }
    local total, points = CP.Plan.RouteCost(guide, route, 100, live.costs, live.dead, live.learned)

    -- Each item once: the bolts' silk, and the shirts' materials less the bolts the bolt row made.
    local bolts = CP.Guide.Crafts(guide.recipes[SILK_BOLT], 100, 120)
    local shirts = CP.Guide.Crafts(guide.recipes[SHIRT], 120, 127)
    print(("ROUTECOST|silk|%.1f bolts, %.1f shirts|RouteCost %.1f over %d points"):format(bolts, shirts, total or -1, points))
    T.ok(bolts >= 2 * shirts, "the bolt row makes every bolt the shirts use")
    T.eq(points, 27, "the route covers 100-127")
    T.ok(total and math.abs(total - 418.1) < 0.05, ("RouteCost %.1f: 418.1 counts each bolt once, 563.7 counts the shirts' bolts twice"):format(total or -1))
    CraftWorld.Close()
end)

-- A made-up guide: a bolt from 2 cloth, a shirt from 2 bolts and a thread, and a bolt-free vest.
local CLOTH, BOLT_ITEM, THREAD, VEST_MAT = 9001, 9002, 9003, 9004
local BOLT, SHIRT_ID, VEST = 1, 2, 3

local function madeUp()
    return {
        recipes = {
            [BOLT] = { name = "Bolt", learn = 1, yellow = 10, grey = 30, ups = 1, reagents = { { CLOTH, 2 } }, makes = BOLT_ITEM },
            [SHIRT_ID] = { name = "Shirt", learn = 1, yellow = 30, grey = 60, ups = 1, reagents = { { BOLT_ITEM, 2 }, { THREAD, 1 } } },
            [VEST] = { name = "Vest", learn = 1, yellow = 30, grey = 60, ups = 1, reagents = { { VEST_MAT, 1 } } },
        },
        prep = { [BOLT_ITEM] = BOLT },
        items = { [CLOTH] = {}, [BOLT_ITEM] = {}, [THREAD] = {}, [VEST_MAT] = {} },
    }
end

T.test("Plan.Better: a bolt route holds against a bolt-free one that only wins on the bolts counted twice", function()
    local guide = madeUp()
    local vestPrice = 0
    local prices = { [CLOTH] = 1, [THREAD] = 1 }
    local function price(item) return prices[item] or (item == VEST_MAT and vestPrice) or nil, "collect" end
    local bolts = CP.Guide.Crafts(guide.recipes[BOLT], 1, 20)
    local shirts = CP.Guide.Crafts(guide.recipes[SHIRT_ID], 20, 27)
    local vests = CP.Guide.Crafts(guide.recipes[VEST], 1, 27)
    T.ok(bolts * 1 >= shirts * 2, "the bolt row makes every bolt the shirts use")
    -- Each item once: the bolts' cloth and the shirts' thread. Counted twice: the shirts' bolts again.
    local once = bolts * 2 + shirts
    local twice = once + shirts * 2 * 2
    local function costs()
        local out = {}
        for id, r in pairs(guide.recipes) do out[id] = CP.Solver.CraftCost(guide, r, price) end
        return CP.Solver.Priced(out, price)
    end
    local old = { { spell = BOLT, from = 1, to = 20 }, { spell = SHIRT_ID, from = 20, to = 27 } }
    local new = { { spell = VEST, from = 1, to = 27 } }

    -- The vests at 85% of the double count: 10% under it, but over the true cost less 10%.
    vestPrice = twice * 0.85 / vests
    local c = costs()
    local was = CP.Plan.RouteCost(guide, old, 1, c)
    print(("ROUTECOST|made-up|once %.1f, twice %.1f, bolt route %.1f, vests %.1f"):format(once, twice, was or -1, vestPrice * vests))
    T.ok(was and math.abs(was - once) < 1e-6, ("the bolt route costs each bolt once: %.2f, not %.2f"):format(was or -1, twice))
    T.eq(CP.Plan.Better(guide, old, new, 1, c), false, "the bolt route holds")

    -- The vests at 80% of the true cost: the bolt-free route wins on its own merit.
    vestPrice = once * 0.8 / vests
    T.eq(CP.Plan.Better(guide, old, new, 1, costs()), true, "a truly cheaper route still wins")
end)

T.test("Plan.RouteCost: what the route's maker rows leave short costs what making it takes, in buy mode too", function()
    local guide = madeUp()
    local function price(item) return ({ [CLOTH] = 1, [THREAD] = 1, [BOLT_ITEM] = 50 })[item] end
    local out = {}
    for id, r in pairs(guide.recipes) do out[id] = CP.Solver.CraftCost(guide, r, price) end
    local c = CP.Solver.Priced(out, price)
    local shirts = CP.Guide.Crafts(guide.recipes[SHIRT_ID], 20, 27)
    -- No bolt row: every bolt is made first, 2 cloth each.
    local total = CP.Plan.RouteCost(guide, { { spell = SHIRT_ID, from = 20, to = 27 } }, 20, c)
    T.ok(total and math.abs(total - shirts * (2 * 2 + 1)) < 1e-6, ("bolts at maker cost: %.2f"):format(total or -1))
end)
