-- Recipes that make a step's materials (`guide.prep`: bolts, oils, grinding stones, blasting
-- powder) get a Train row before the first step that needs them, or a pattern row for a
-- vendor or favor schematic. Tester's case, 1.0.24: with Enchanting on, Woolen Cape's card said
-- "make 47 Bolt of Woolen Cloth" and no row trained the bolt (INTERMED-01).

local CP = ProfLost
local G = CP.Guide
local TAILORING, ENGINEERING = 197, 202
local CAPE, BOLT, BAG = 2402, 2964, 3757
local DYNAMITE2, FUSE = 23069, 1266914
local FRAG, POWDER, CONTACT = 12603, 12585, 3973

local function names(stop)
    local out = {}
    for _, r in ipairs(stop.recipes) do out[#out + 1] = r.name end
    table.sort(out)
    return table.concat(out, ", ")
end

-- The stops that teach `name`.
local function teaching(stops, name)
    local out = {}
    for _, stop in ipairs(stops) do
        for _, r in ipairs(stop.recipes) do
            if r.name == name then out[#out + 1] = stop end
        end
    end
    return out
end

T.test("a step's made material whose recipe is unknown gets a visit before the step", function()
    MapWorld.begin({ zone = 1454, level = 20, side = "Horde" })
    local guide = CP.Guides[TAILORING]
    local steps = { { spell = CAPE, from = 64, to = 80, crafts = 47 } }
    local stops = G.TrainStops(guide, steps, { [CAPE] = true }, 64, {})
    T.eq(#stops, 1, "one visit")
    T.eq(names(stops[1]), "Bolt of Woolen Cloth")
    T.eq(stops[1].skill, 64, "at the step's start")
    T.eq(stops[1].before, 1, "before Woolen Cape")
    T.eq(stops[1].fee, guide.recipes[BOLT].fee, "its fee counts")
end)

T.test("the bolt rides the visit the player makes anyway", function()
    MapWorld.begin({ zone = 1454, level = 20, side = "Horde" })
    local guide = CP.Guides[TAILORING]
    -- Woolen Bag (50) is trained at 55; the bolt (55) goes with it, not a trip of its own at 64.
    local steps = { { spell = BAG, from = 55, to = 64, crafts = 12 }, { spell = CAPE, from = 64, to = 80, crafts = 47 } }
    local stops = G.TrainStops(guide, steps, { [CAPE] = true }, 55, {})
    T.eq(#stops, 1, "one visit")
    T.eq(stops[1].skill, 55)
    T.eq(names(stops[1]), "Bolt of Woolen Cloth, Woolen Bag")
    -- The cape unlearned too: one visit at 55 still teaches all three.
    stops = G.TrainStops(guide, steps, {}, 55, {})
    T.eq(#teaching(stops, "Bolt of Woolen Cloth"), 1, "trained once")
    T.eq(teaching(stops, "Bolt of Woolen Cloth")[1].skill, 55)
end)

T.test("bolts in the bags and bank that cover the step train nothing", function()
    MapWorld.begin({ zone = 1454, level = 20, side = "Horde" })
    local guide = CP.Guides[TAILORING]
    local steps = { { spell = CAPE, from = 64, to = 80, crafts = 47 } }
    T.eq(#G.TrainStops(guide, steps, { [CAPE] = true }, 64, { [2997] = 47 }), 0, "47 held cover 47 capes")
    T.eq(#G.TrainStops(guide, steps, { [CAPE] = true }, 64, { [2997] = 46 }), 1, "46 do not")
    T.eq(#G.TrainStops(guide, steps, { [CAPE] = true, [BOLT] = true }, 64, {}), 0, "known: nothing to train")
end)

T.test("a step's own maker step later in the plan is trained before the first use", function()
    MapWorld.begin({ zone = 1454, level = 20, side = "Horde" })
    local guide = CP.Guides[TAILORING]
    local steps = { { spell = CAPE, from = 64, to = 70, crafts = 20 }, { spell = BOLT, from = 70, to = 80, crafts = 30 } }
    local stops = G.TrainStops(guide, steps, { [CAPE] = true }, 64, {})
    local bolt = teaching(stops, "Bolt of Woolen Cloth")
    T.eq(#bolt, 1, "one row teaches it")
    T.eq(bolt[1].before, 1, "before the cape, not at its own step")
end)

T.test("made materials of made materials are trained too", function()
    MapWorld.begin({ zone = 1454, level = 40, side = "Horde" })
    local guide = CP.Guides[ENGINEERING]
    local steps = { { spell = FRAG, from = 215, to = 235, crafts = 25 } }
    local stops = G.TrainStops(guide, steps, { [FRAG] = true }, 215, {})
    T.eq(#stops, 1, "one visit")
    T.eq(names(stops[1]), "Mithril Casing, Solid Blasting Powder, Unstable Trigger")
end)

T.test("Silver Contact, sold only in limited stock, is made on demand and trained for Big Iron Bomb", function()
    MapWorld.begin({ zone = 1454, level = 30, side = "Horde" })
    local guide = CP.Guides[ENGINEERING]
    T.eq(guide.prep[4404], CONTACT, "the generator lists it as made on demand")
    local steps = { { spell = 3967, from = 150, to = 160, crafts = 12 } }
    local stops = G.TrainStops(guide, steps, { [3967] = true }, 150, {})
    T.eq(#teaching(stops, "Silver Contact"), 1)
end)

T.test("a schematic maker gets a pattern row of its own, never merged with a trainer visit", function()
    MapWorld.begin({ zone = 1454, level = 40, side = "Horde" })
    local guide = CP.Guides[ENGINEERING]
    local steps = { { spell = DYNAMITE2, from = 200, to = 210, crafts = 15 } }
    local stops = G.TrainStops(guide, steps, { [DYNAMITE2] = true, [POWDER] = true, [CONTACT] = true }, 200, {})
    T.eq(#stops, 1)
    T.ok(stops[1].pattern, "a pattern stop")
    T.eq(names(stops[1]), "EZ-Thro Fireproof Fuse")
    T.eq(stops[1].spells[1], FUSE)
    T.eq(stops[1].fee, 0, "no trainer fee")
    local name, status = G.StopText({ train = stops[1] })
    T.eq(name, "Learn EZ-Thro Fireproof Fuse")
    T.ok(status:find("Schematic for 180 Merchant's Favor", 1, true) ~= nil, status)
    -- With Solid Blasting Powder and the fuse's Silver Contact unknown too: a trainer visit and
    -- the pattern row, apart.
    stops = G.TrainStops(guide, steps, { [DYNAMITE2] = true }, 200, {})
    T.eq(#stops, 2, "two stops")
    T.eq(#teaching(stops, "Solid Blasting Powder"), 1)
    T.eq(teaching(stops, "Silver Contact")[1], teaching(stops, "Solid Blasting Powder")[1], "one visit for both")
    T.ok(not teaching(stops, "Solid Blasting Powder")[1].pattern, "the powder at a trainer")
    T.ok(teaching(stops, "EZ-Thro Fireproof Fuse")[1].pattern, "the fuse on its own row")
    local keys = {}
    for _, row in ipairs(G.WithStops(guide, steps, { [DYNAMITE2] = true }, 200, 225, 40, {})) do
        if row.key then
            T.ok(not keys[row.key], "one row per key: " .. tostring(row.key))
            keys[row.key] = true
        end
    end
end)

T.test("the Train row stands before Woolen Cape in the step list", function()
    MapWorld.begin({ zone = 1454, level = 20, side = "Horde" })
    local guide = CP.Guides[TAILORING]
    local steps = { { spell = CAPE, from = 64, to = 80, crafts = 47 } }
    local rows = G.WithStops(guide, steps, { [CAPE] = true }, 64, 75, 20, {})
    local trainAt, capeAt
    for i, row in ipairs(rows) do
        if row.train and names(row.train) == "Bolt of Woolen Cloth" then trainAt = i end
        if row.spell == CAPE then capeAt = i end
    end
    T.ok(trainAt and capeAt and trainAt < capeAt, ("train row %s, cape %s"):format(tostring(trainAt), tostring(capeAt)))
    T.eq((G.StopText(rows[trainAt])), "Train Bolt of Woolen Cloth")
end)
