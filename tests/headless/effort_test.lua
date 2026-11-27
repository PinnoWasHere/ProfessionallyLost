-- Level-as-you-go costs a gathered material by its own chance where it farms best, and
-- materials of one skin or node kind share its loots. Owner, 2026-11-27: "Heavy Hide isn't a
-- byproduct from bags. It's a loot chance when skinning, then I buy Salt from a vendor."
-- Real data (cMaNGOS skinning loot, data/sources/looted-items.csv): a Heavy Leather skin gives
-- Heavy Leather 0.49, Heavy Hide 0.03; whelps give Green Whelp Scale 0.20. All three are
-- farmed from Heavy Leather's skins (src "skin 4234").
--   Green Whelp Bracers: 6 scales + 8 Heavy Leather + 2 Silken Thread, about 30 skins.
--   Barbaric Shoulders: 8 Heavy Leather + 1 Cured Heavy Hide (1 Heavy Hide + 3 Salt) + 2 Fine
--   Thread, about 33 skins.

local CP = ProfLost
local LW, SKIN = 165, 393
local LEATHER, HIDE, SCALE = 4234, 4235, 7392
local BRACERS, SHOULDERS, CURING = 9202, 7151, 3818
local SWAMP = 1435
local VENDOR = 0.1   -- Pricing's VENDOR_EFFORT: Silken and Fine Thread, Salt

local function character()
    MapWorld.begin({ zone = SWAMP, level = 35, side = "Alliance" })
    CraftWorld.begin({ professions = { [LW] = { rank = 165, max = 225 }, [SKIN] = { rank = 170, max = 225 } } })
    World.set(CP.db, "collect", true)
    CP.Plan.Invalidate()
end

local function near(a, b) return math.abs(a - b) < 0.05 end

T.test("Heavy Hide is farmed at its own chance, not held to the bags", function()
    local items = CP.Guides[LW].items
    T.ok(items[HIDE][5] ~= true, "Heavy Hide is not stock-only")
    T.ok(items[HIDE][4] >= 25, ("a Heavy Hide costs about 33 skins (%.1f)"):format(items[HIDE][4]))
    T.ok(items[SCALE][4] >= 4.5, ("a Green Whelp Scale costs about 5 skins (%.1f)"):format(items[SCALE][4]))
    T.ok(items[LEATHER][4] >= 1.8, ("a Heavy Leather costs about 2 skins (%.1f)"):format(items[LEATHER][4]))
    T.ok(items[HIDE].src ~= nil and items[HIDE].src == items[LEATHER].src and items[SCALE].src == items[LEATHER].src,
        "the three come from one skin kind")
end)

T.test("Skinning 170, level 35: Bracers and Shoulders cost the skins their scarcest material takes", function()
    character()
    local guide, price = CP.Guides[LW], CP.Pricing.CollectFn()
    local e = function(item) return guide.items[item][4] end
    local bracers = CP.Solver.CraftCost(guide, guide.recipes[BRACERS], price)
    local shoulders = CP.Solver.CraftCost(guide, guide.recipes[SHOULDERS], price)
    local wantB = math.max(6 * e(SCALE), 8 * e(LEATHER)) + 2 * VENDOR
    local wantS = math.max(8 * e(LEATHER), e(HIDE)) + 3 * VENDOR + 2 * VENDOR
    T.ok(near(bracers, wantB), ("Green Whelp Bracers: %.2f, want %.2f (the leather comes with the scales)"):format(bracers, wantB))
    T.ok(near(shoulders, wantS), ("Barbaric Shoulders: %.2f, want %.2f (the leather comes with the hide)"):format(shoulders, wantS))
    T.ok(bracers < shoulders, "the Bracers' 30 skins beat the Shoulders' 33")
end)

T.test("with the Bracers out, the Shoulders carry 165-170 though no hide is held", function()
    character()
    local guide = CP.Guides[LW]
    local learned = { [SHOULDERS] = true, [CURING] = true, [BRACERS] = true }
    local function only(set) return function(id) return set[id] == true end end
    local opts = { rareFromStock = true }
    local steps = CP.Solver.Plan(guide, 165, learned, CP.Pricing.CollectFn(), only(learned), nil, {}, opts)
    T.eq(steps[1].spell, BRACERS, "the Bracers lead at 165")
    local noB = { [SHOULDERS] = true, [CURING] = true }
    steps = CP.Solver.Plan(guide, 165, noB, CP.Pricing.CollectFn(), only(noB), nil, {}, opts)
    T.eq(steps[1].spell, SHOULDERS, "the Shoulders lead without them")
    T.ok(steps[1].to >= 170, ("and carry on to %d"):format(steps[1].to))
    local per = steps[1].cost / steps[1].crafts
    T.ok(near(per, CP.Solver.CraftCost(guide, guide.recipes[SHOULDERS], CP.Pricing.CollectFn())),
        ("the step's cost per craft (%.2f) is the craft's"):format(per))
end)
