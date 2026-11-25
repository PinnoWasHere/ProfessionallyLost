-- Live planner, pricing and waypoint choice against the generated Leatherworking guide.

local CP = ProfLost
local lw = CP.Guides[165]

local function listPrice(itemID, guideItem)
    return guideItem and guideItem[1] > 0 and guideItem[1] or nil
end

T.test("plan from skill 1 covers to the end without holes", function()
    local steps = CP.Solver.Plan(lw, 1, {}, listPrice)
    T.eq(steps[1].from, 1)
    for i = 2, #steps do T.eq(steps[i].from, steps[i - 1].to) end
    for _, st in ipairs(steps) do T.ok(st.spell ~= nil, "no gap at " .. st.from) end
end)

T.test("plan starts at the player's skill", function()
    local steps = CP.Solver.Plan(lw, 75, {}, listPrice)
    T.eq(steps[1].from, 75)
end)

-- At 80 Embossed Leather Gloves (3 Light Leather, 2 Coarse Thread) are yellow, 67%
-- skill-up; Fine Leather Belt (6 Light Leather, 2 Coarse Thread) is orange.
local both = { [3756] = true, [3763] = true }
local onlyBoth = function(id) return both[id] == true end

T.test("a cheap yellow recipe beats an expensive orange one", function()
    local market = function(itemID)
        if itemID == 2318 then return 60 end    -- Light Leather
        if itemID == 2320 then return 10 end    -- Coarse Thread
        return 1000000                          -- keep other recipes out
    end
    local steps = CP.Solver.Plan(lw, 80, both, market)
    T.eq(steps[1].spell, 3756)
end)

T.test("prices change the pick", function()
    -- Thread dear, leather nearly free: fewer crafts wins, so the orange belt.
    local market = function(itemID)
        if itemID == 2318 then return 1 end
        if itemID == 2320 then return 100000 end
        return 10000000
    end
    local steps = CP.Solver.Plan(lw, 80, both, market, onlyBoth)
    T.eq(steps[1].spell, 3763)
end)

T.test("Guide.Current follows a live plan", function()
    local steps = CP.Solver.Plan(lw, 60, {}, listPrice)
    local cur = CP.Guide.Current(lw, 60, {}, steps)
    T.eq(cur.step, steps[1])
    T.eq(cur.from, 60)
end)

T.test("pricing prefers an always-stocked vendor, then DaylightMogul, then list price", function()
    T.eq(select(2, CP.Pricing.Get(2320, { 10, true })), "vendor")
    T.eq(select(2, CP.Pricing.Get(2318, { 60, false })), "estimate")
    DaylightMogul = { API = { Price = function(id) return id == 2318 and 45 or nil end } }
    local price, source = CP.Pricing.Get(2318, { 60, false })
    T.eq(price, 45)
    T.eq(source, "auction")
    DaylightMogul = nil
end)

T.test("auction data needs Mogul's market prices, not just Mogul loaded", function()
    T.eq(CP.Pricing.HasAuctionData(), false, "no DaylightMogul")
    local priced = {}
    DaylightMogul = { API = { Price = function(id, source)
        T.eq(source, "market")
        return priced[id]
    end } }
    T.eq(CP.Pricing.HasAuctionData(), false, "loaded, never scanned")
    priced[2589] = 30
    T.eq(CP.Pricing.HasAuctionData(), true, "a staple priced")
    DaylightMogul = { API = { Price = function() error("boom") end } }
    T.eq(CP.Pricing.HasAuctionData(), false, "an error reads as no data")
    DaylightMogul = nil
end)

T.test("Level-as-you-go counts materials to collect, not gold", function()
    DaylightMogul = { API = { Price = function() return 1 end } }
    local leather, hide = CP.Pricing.GetCollect(2319, lw.items[2319]), CP.Pricing.GetCollect(4232, lw.items[4232])
    T.ok(leather > 0 and leather < 2, "Medium Leather: about a skin each")
    T.eq(hide, leather, "Medium Hide comes with the same skins, so it costs the same")
    T.eq(CP.Pricing.GetCollect(9999, { 200, false }), 1, "no loot data: one to collect")
    T.eq(select(2, CP.Pricing.GetCollect(2320, { 10, true })), "vendor")
    T.ok(CP.Pricing.GetCollect(2320, { 10, true }) < 1, "vendor thread is a short trip")
    T.eq(CP.Pricing.Get(2318, { 60, false }), 1, "Buy-and-power-level still uses the auction price")
    DaylightMogul = nil
end)

T.test("Level-as-you-go picks the kit over the belt: fewer materials per point", function()
    -- Owner: 6 Light Leather per craft is harder to gather than 4 Medium Leather.
    local learned = { [2165] = true, [3763] = true }
    local kitOrBelt = function(id) return id == 2165 or id == 3763 end
    local steps = CP.Solver.Plan(lw, 94, learned, CP.Pricing.GetCollect, kitOrBelt)
    T.eq(steps[1].spell, 2165, "Medium Armor Kit at 94")
    T.eq(CP.Solver.Plan(lw, 94, learned, listPrice, kitOrBelt)[1].spell, 3763,
        "Buy-and-power-level, by gold, still takes the cheaper belt")
end)

T.test("sale value compares vendor and auction after the cut", function()
    World.patch("C_Item.GetItemInfo", function()
        return "Embossed Leather Gloves", "", 1, 15, 5, "", "", 1, "", 0, 120
    end)
    T.eq(select(1, CP.Pricing.SaleValue(4239)), 120)
    T.eq(select(2, CP.Pricing.SaleValue(4239)), nil, "no DaylightMogul, no auction price")
    DaylightMogul = { API = { Price = function() return 1000 end } }
    T.eq(select(2, CP.Pricing.SaleValue(4239)), 950)
    DaylightMogul = nil
end)

T.test("price format", function()
    T.eq(CP.Pricing.Format(12345), "1g 23s")
    T.eq(CP.Pricing.Format(4500), "45s")
    T.eq(CP.Pricing.Format(8), "8c")
end)

T.test("waypoint picks the nearest friendly NPC on the same continent", function()
    local npcs = {
        [1] = { "Horde Trainer", "H", { { 0, 100, 100 } } },
        [2] = { "Far Alliance", "A", { { 0, 5000, 5000 } } },
        [3] = { "Near Alliance", "A", { { 0, 200, 200 } } },
        [4] = { "Other Continent", "N", { { 1, 0, 0 } } },
    }
    T.eq(CP.Waypoint.Nearest({ 1, 2, 3, 4 }, npcs, "A", 0, 0, 0).name, "Near Alliance")
    T.eq(CP.Waypoint.Nearest({ 1, 4 }, npcs, "A", 0, 0, 0).name, "Other Continent")
    T.eq(CP.Waypoint.Nearest({ 1 }, npcs, "A", 0, 0, 0), nil)
end)

T.test("trainer recipes in guides carry NPC locations", function()
    local r = lw.recipes[3756]
    T.ok(#r.npcs > 0)
    for _, n in ipairs(r.npcs) do T.ok(lw.npcs[n] ~= nil, "npc " .. n) end
end)

T.test("a waypoint inside a zone lands on the zone map (values from an in-game error)", function()
    local function vec(x, y) return { GetXY = function() return x, y end } end
    World.patch("C_Map.GetMapPosFromWorldPos", function(_, _, override)
        if override == 1413 then return 1413, vec(0.458942, 0.356958) end
        return 1414, vec(0.518870, 0.554314)
    end)
    World.patch("C_Map.GetMapInfoAtPosition", function() return { mapType = 3, mapID = 1413, name = "The Barrens", parentMapID = 1414 } end)
    World.patch("C_Map.GetMapInfo", function(id)
        return id == 1413 and { mapType = 3, mapID = 1413, name = "The Barrens", parentMapID = 1414 }
            or { mapType = 2, mapID = 1414, name = "Kalimdor", parentMapID = 947 }
    end)
    T.eq(CP.Waypoint.Describe({ name = "Trainer", continent = 1, x = -799.2, y = -2027.7 }), "The Barrens (45.9, 35.7)")

    World.patch("C_Map.GetMapInfoAtPosition", function() return nil end)
    T.eq(CP.Waypoint.Describe({ name = "Trainer", continent = 1, x = -799.2, y = -2027.7 }), "Kalimdor (51.9, 55.4)",
        "no zone under the point falls back to the continent")
end)

local function spells(steps, n)
    local out = {}
    for i = 1, math.min(n, #steps) do out[i] = (steps[i].spell or 0) .. "@" .. steps[i].from end
    return table.concat(out, " ")
end

-- Cost per expected point of `spell` at skill `s`, at list prices, valued the way the
-- planner does: crafted gear from earlier steps is already paid for, prep materials
-- cost their recipe's materials.
local function unit(guide, item)
    local maker = guide.prep and guide.prep[item] and guide.recipes[guide.prep[item]]
    if maker then
        local t = 0
        for _, pair in ipairs(maker.reagents) do t = t + pair[2] * (listPrice(pair[1], guide.items[pair[1]]) or 50000) end
        return t
    end
    if guide.craftOnly and guide.craftOnly[item] then return 0 end
    return listPrice(item, guide.items[item]) or 50000
end

local function perPoint(guide, spell, s)
    local r = guide.recipes[spell]
    local p = CP.Guide.Chance(r, s) * (r.ups or 1)
    if p <= 0 then return math.huge end
    local total = 0
    for _, pair in ipairs(r.reagents) do total = total + pair[2] / p * unit(guide, pair[1]) end
    -- Greens cost double: the solver steers off crafts that often give nothing.
    if s >= math.floor((r.yellow + r.grey) / 2) then total = total * 2 end
    return total
end

T.test("each step is the cheapest skill-up there, within the stickiness band", function()
    -- The owner's rule: the guide always takes the more efficient path. A step may
    -- hold on to its recipe only while it costs at most 15% more than the best.
    local learned = { [2160] = true, [2164] = true, [2165] = true, [3756] = true, [3763] = true, [2152] = true }
    local steps = CP.Solver.Plan(lw, 85, learned, listPrice)
    for _, st in ipairs(steps) do
        if st.from >= 150 then break end
        local best = math.huge
        for id, r in pairs(lw.recipes) do
            if (r.step or learned[id]) and (learned[id] or r.learn <= st.from) then
                -- A recipe that turns green within MIN_RUN points is a run too short to plan.
                local short = not CP.Solver.IsGreen(r, st.from) and CP.Solver.IsGreen(r, st.from + CP.Solver.MIN_RUN - 1)
                if not short and perPoint(lw, id, st.from) < best then best = perPoint(lw, id, st.from) end
            end
        end
        T.ok(perPoint(lw, st.spell, st.from) <= best * 1.15 + 1e-9,
            ("%s at %d is within 15%% of the cheapest"):format(lw.recipes[st.spell].name, st.from))
    end
end)

T.test("a green recipe never beats an orange one that costs less per point", function()
    local learned = { [2160] = true, [2164] = true, [2165] = true }
    local steps = CP.Solver.Plan(lw, 85, learned, listPrice)
    T.ok(steps[1].spell ~= 2160, "not the Embossed Leather Vest at 85")
end)

local fa = CP.Guides[129]
-- The bandage examples below keep to bandages; Forever's potions and poultices
-- (from GUIDZ) would otherwise win and change the story.
local bandages = function(id) return fa.recipes[id].name:find("Bandage") ~= nil end

T.test("the plan switches to a newly trainable recipe where it unlocks", function()
    -- Heavy Wool Bandage (3278) is learned at 115; Wool Bandage (3277) is known.
    local steps = CP.Solver.Plan(fa, 100, { [3277] = true }, listPrice, bandages)
    local heavy
    for _, st in ipairs(steps) do if st.spell == 3278 then heavy = heavy or st end end
    T.ok(heavy ~= nil, "Heavy Wool Bandage is in the plan")
    T.eq(heavy.from, 115, "and starts at its learn level")
    local stops = CP.Guide.TrainStops(fa, steps, { [3277] = true }, 100)
    local stop
    for _, s in ipairs(stops) do if s.skill == 115 then stop = s end end
    T.ok(stop ~= nil, "a trainer visit at 115")
    T.eq(stop.recipes[1].name, "Heavy Wool Bandage")
    T.eq(stop.fee, 1000, "10s")
    T.eq(steps[stop.before].spell, 3278, "placed just before the Heavy Wool step")
end)

T.test("past the learn level, an untrained better recipe leads now with a train stop", function()
    -- In-game report: First Aid 118, Heavy Wool Bandage not trained, Wool Bandage kept going.
    local learned = { [3277] = true }
    local last = CP.Plan.Expand({ { 118, 133, 3277 } })
    local steps = CP.Solver.Plan(fa, 118, learned, listPrice, bandages, last)
    T.eq(steps[1].spell, 3278, "Heavy Wool Bandage first")
    local rows = CP.Guide.WithStops(fa, steps, learned, 118, 150)
    T.ok(rows[1].train ~= nil, "a Train row leads the list")
    T.eq(rows[1].train.skill, 118)
end)

T.test("once trained, a cheaper recipe from the same materials takes over", function()
    -- In-game report: after training Heavy Wool Bandage, Wool Bandage stayed first.
    local learned = { [3277] = true, [3278] = true }
    local steps = CP.Solver.Plan(fa, 118, learned, listPrice, bandages, CP.Plan.Expand({ { 118, 133, 3277 } }))
    T.eq(steps[1].spell, 3278)
    T.eq(#CP.Guide.TrainStops(fa, { steps[1] }, learned, 118), 0, "nothing left to train for it")
end)

T.test("a trainer visit sits right before the step that first needs it", function()
    -- In-game report: "Train Nimble Leather Gloves" appeared at 95, its learn level,
    -- while the guide still had Medium Armor Kits to craft.
    local learned = { [2165] = true, [2152] = true, [2160] = true, [3756] = true, [3763] = true }
    local steps = CP.Solver.Plan(lw, 94, learned, listPrice)
    for _, stop in ipairs(CP.Guide.TrainStops(lw, steps, learned, 94)) do
        local st = steps[stop.before]
        T.ok(st ~= nil and st.from == stop.skill, ("train stop at %d starts its step"):format(stop.skill))
        T.eq(lw.recipes[st.spell].name, stop.recipes[1].name)
    end
end)

T.test("a recipe used by two steps is trained once, before the first", function()
    local learned = { [2165] = true, [2152] = true, [2160] = true, [3756] = true, [3763] = true }
    local steps = CP.Solver.Plan(lw, 94, learned, listPrice)
    local seen = {}
    for _, stop in ipairs(CP.Guide.TrainStops(lw, steps, learned, 94)) do
        for _, r in ipairs(stop.recipes) do
            T.ok(not seen[r.name], r.name .. " trained once")
            seen[r.name] = true
        end
    end
end)

T.test("the same skill and recipes give the same guide, refresh after refresh", function()
    -- In-game report: Leatherworking 99, crafts without a skill point reshuffled the list
    -- every time. The plan no longer reads bag counts, so only skill and recipes move it.
    local learned = { [2165] = true, [2152] = true, [2160] = true, [3756] = true, [3763] = true, [20648] = true }
    local first = CP.Solver.Plan(lw, 99, learned, listPrice)
    local last = CP.Plan.Expand(CP.Plan.Pack(first))
    for _ = 1, 3 do
        local again = CP.Solver.Plan(lw, 99, learned, listPrice, nil, last)
        T.eq(spells(again, 10), spells(first, 10))
        last = CP.Plan.Expand(CP.Plan.Pack(again))
    end
end)

T.test("a saved plan round-trips through Pack and Expand", function()
    local steps = { { spell = 1, from = 10, to = 12 }, { spell = nil, from = 12, to = 13 }, { spell = 2, from = 13, to = 15 } }
    local map = CP.Plan.Expand(CP.Plan.Pack(steps))
    T.eq(map[10], 1)
    T.eq(map[11], 1)
    T.eq(map[12], nil, "gaps stay empty")
    T.eq(map[14], 2)
    T.eq(map[15], nil)
end)

-- A two-recipe guide: Belt (from leather) makes item 900; Fancy needs one 900 per craft.
local function chainGuide()
    return {
        recipes = {
            [1] = { name = "Belt", src = "trainer", learn = 1, yellow = 50, grey = 60, ups = 1, reagents = { { 800, 2 } }, makes = 900, step = true },
            [2] = { name = "Fancy", src = "trainer", learn = 1, yellow = 50, grey = 60, ups = 1, reagents = { { 900, 1 } }, step = true },
        },
        items = { [800] = { 10, false } },
        craftOnly = { [900] = true },
    }
end
local count = function(id, g) return CP.Pricing.GetCollect(id, g) end

T.test("a recipe needing a craft-only material waits for a step that makes it", function()
    local g = chainGuide()
    local onlyFancy = function(id) return id == 2 end
    for _, st in ipairs(CP.Solver.Plan(g, 1, { [2] = true }, count, onlyFancy)) do
        T.eq(st.spell, nil, "without Belt steps, Fancy is never planned")
    end
    local steps = CP.Solver.Plan(g, 1, { [1] = true, [2] = true }, count)
    T.eq(steps[1].spell, 1, "Belt first")
    local fancy
    for _, st in ipairs(steps) do if st.spell == 2 then fancy = st end end
    T.ok(fancy ~= nil, "Fancy once Belts exist")
end)

T.test("Leatherworking never suggests Dark Leather Belt without Fine Leather Belt steps", function()
    -- Owner: Dark Leather Belt (3766) needs a Fine Leather Belt per craft.
    local noBelt = function(id) return id ~= 3763 end
    local learned = { [3766] = true, [2165] = true, [2167] = true, [3817] = true }
    for _, st in ipairs(CP.Solver.Plan(lw, 100, learned, CP.Pricing.GetCollect, noBelt)) do
        T.ok(st.spell ~= 3766, "no Dark Leather Belt at " .. st.from)
    end
    T.ok(lw.craftOnly[4246], "Fine Leather Belt is craft-only")
    T.ok(lw.prep[4233] == 3817, "Cured Medium Hide is prep, made by its own recipe on demand")
    T.ok(not lw.craftOnly[2319], "Medium Leather is skinned, not craft-only")
end)

T.test("steps whose crafts feed later steps say what to keep", function()
    local g = chainGuide()
    local steps = { { spell = 1, from = 1, to = 5, crafts = 10 }, { spell = 2, from = 5, to = 9, crafts = 7 } }
    local keeps = CP.Guide.Keeps(g, steps)
    T.eq(keeps[1].count, 7)
    T.eq(keeps[1].names[1], "Fancy")
    T.eq(keeps[2], nil)
end)

T.test("Level-as-you-go at 103 picks Gray Leather Boots for a leatherworker-skinner", function()
    -- Owner: "at 103, Gray Leather Boots, even though yellow, seem the cheapest".
    local learned = { [2165] = true, [3763] = true, [3817] = true, [2167] = true }
    local steps = CP.Solver.Plan(lw, 103, learned, CP.Pricing.GetCollect, function(id) return id ~= 9074 end)
    T.eq(steps[1].spell, 2167)
end)

T.test("craft-only items already in the bags count as supply", function()
    local g = chainGuide()
    local onlyFancy = function(id) return id == 2 end
    local steps = CP.Solver.Plan(g, 1, { [2] = true }, count, onlyFancy, nil, { [900] = 200 })
    T.eq(steps[1].spell, 2, "Fancy straight away with 200 made earlier")
    local keeps = CP.Guide.Keeps(g, { { spell = 1, from = 1, to = 5, crafts = 10 }, { spell = 2, from = 5, to = 9, crafts = 7 } }, { [900] = 5 })
    T.eq(keeps[1].count, 2, "only what the bags don't cover")
end)

T.test("a recipe needing cured hides is planned without a curing step, curing on demand", function()
    -- Owner: curing hides is ordinary prep; Light Hide's only use is Cured Light Hide.
    local g = {
        recipes = {
            [1] = { name = "Cure", src = "trainer", learn = 1, yellow = 5, grey = 10, ups = 1, reagents = { { 700, 1 } }, makes = 701 },
            [2] = { name = "Vest", src = "trainer", learn = 1, yellow = 50, grey = 60, ups = 1, reagents = { { 701, 2 } }, step = true },
        },
        items = { [700] = { 10, false } },
        prep = { [701] = 1 },
    }
    local steps = CP.Solver.Plan(g, 20, { [1] = true, [2] = true }, CP.Pricing.GetCollect)
    T.eq(steps[1].spell, 2, "Vest is planned; its hides are cured as needed")
    local noCure = CP.Solver.Plan(g, 20, { [2] = true }, CP.Pricing.GetCollect, function(id) return id == 2 end)
    T.eq(noCure[1].spell, 2, "the curing recipe needn't be a step, only known or learnable")
end)

T.test("Level-as-you-go cures only the hides on hand, then carries on with something else", function()
    -- Owner: use 3 Cured Heavy Hides' worth, make something else, cure more as hides turn up.
    T.ok(lw.items[4235][5], "Heavy Hide is a rare byproduct")
    local learned = { [3818] = true, [3780] = true, [9195] = true, [2166] = true }
    local only = function(id) return learned[id] == true end
    local function curing(steps)
        local n = 0
        for _, st in ipairs(steps) do
            if st.spell == 3818 and st.from < 150 then n = n + st.crafts end
        end
        return n
    end
    local opts = { rareFromStock = true }
    local three = CP.Solver.Plan(lw, 125, learned, CP.Pricing.GetCollect, only, nil, { [4235] = 3 }, opts)
    T.ok(curing(three) <= 3, ("cures no more than the 3 hides held (%d)"):format(curing(three)))
    T.ok(#three > 1 and three[1].to < 150, "another recipe carries on")
    local more = CP.Solver.Plan(lw, 125, learned, CP.Pricing.GetCollect, only, nil, { [4235] = 30 }, opts)
    T.ok(curing(more) > curing(three), "more hides, more curing")
    local buy = CP.Solver.Plan(lw, 125, learned, listPrice, only, nil, { [4235] = 3 })
    T.ok(curing(buy) > 3, "Buy-and-power-level isn't held to the bags")
end)

T.test("a maker step makes at least what later steps keep from it", function()
    -- In-game: Cured Rugged Hide made 15, but the Heavy Scorpid Helm later wants 24.
    local g = chainGuide()
    local steps = { { spell = 1, from = 1, to = 5, crafts = 15 }, { spell = 2, from = 5, to = 9, crafts = 24 } }
    T.eq(CP.Guide.Keeps(g, steps)[1].count, 24)
end)

T.test("hide crafts sit beside the main path as side crafts, and the main path doesn't move", function()
    -- Owner: crafts doable "at the same time" mustn't flip positions; mark them interchangeable.
    local learned = { [3818] = true, [3780] = true, [2166] = true }
    local only = function(id) return learned[id] == true end
    local function main(held)
        return CP.Solver.Plan(lw, 125, learned, CP.Pricing.GetCollect, only, nil, held, { rareFromStock = true })
    end
    local none = main({})
    local some = main(CP.Plan.WithoutRare(lw, { [4235] = 30 }))  -- what Plan.Current passes
    T.eq(spells(some, 6), spells(none, 6), "finding 30 hides doesn't move the main path")
    for _, st in ipairs(none) do
        if st.from >= 150 then break end
        T.ok(st.spell ~= 3818, "no curing in the main path at " .. st.from)
    end
    CP.db.collect = true
    local sides = CP.Plan.Sides(lw, none, learned, { [4235] = 3 }, only)
    local found
    for i, side in pairs(sides) do
        if side.spell == 3818 then found = { i = i, side = side } end
    end
    T.ok(found ~= nil, "Cured Heavy Hide offered as a side craft")
    T.eq(found.side.crafts, 3, "as many as the 3 hides cover")
    local count = 0
    for _, side in pairs(sides) do if side.spell == 3818 then count = count + 1 end end
    T.eq(count, 1, "offered once, not under every step")
    T.eq(next(CP.Plan.Sides(lw, none, learned, {}, only)), nil, "no hides in the bags, no side rows")
end)

T.test("a side craft is always a recipe the player knows, never a pattern to buy", function()
    -- In-game: Deviate Scale Gloves (a limited vendor pattern) showed as a side craft.
    CP.db.collect = true
    local learned = { [3780] = true, [2166] = true }  -- Cured Heavy Hide not known
    local steps = CP.Solver.Plan(lw, 125, learned, CP.Pricing.GetCollect, nil, nil, {}, { rareFromStock = true })
    for _, side in pairs(CP.Plan.Sides(lw, steps, learned, { [4235] = 10, [6470] = 10, [6471] = 10 })) do
        T.ok(learned[side.spell], lw.recipes[side.spell].name .. " is known")
    end
end)

T.test("a pattern main step gets a trainer recipe as its 'or' fallback", function()
    -- Owner: if a pattern is more efficient it's the main craft; the 'or' is a trainer
    -- craft for when the pattern can't be bought or found.
    local stepSpell, step
    for id, r in pairs(lw.recipes) do
        if r.src == "vendor" and r.step and (not stepSpell or id < stepSpell) then stepSpell, step = id, r end
    end
    World.patch("UnitFactionGroup", function() return "Horde", "Horde" end)
    World.patch("GetProfessions", function() return 1, 2 end)
    World.patch("GetProfessionInfo", function(i)
        if i == 1 then return "Leatherworking", 0, 130, 225, 0, 0, 165 end
        return "Skinning", 0, 150, 225, 0, 0, 393
    end)
    World.patch("C_Item.GetItemInfoInstant", function(id) return id, "", "", "", 0, 7, 6 end)
    local live = { guide = lw, learned = {}, recipes = {}, sides = {},
                   plan = { { spell = stepSpell, from = step.learn, to = math.min(step.learn + 5, step.grey), crafts = 5 } } }
    CP.Plan.AddFallbacks(live)
    local side = live.sides[1]
    T.ok(side and side.fallback, "fallback added under " .. step.name)
    T.eq(CP.Guide.SourceWord(side.recipe), "trainer")
end)

T.test("held hides don't split a recipe's run in two", function()
    World.patch("GetProfessions", function() return 1, 2 end)
    World.patch("GetProfessionInfo", function(i) return nil, nil, nil, nil, nil, nil, i == 1 and 393 or 165 end)
    World.patch("C_Item.GetItemCount", function(id) return id == 4231 and 4 or 0 end)   -- Cured Medium Hide
    World.patch("C_Item.GetItemInfoInstant", function(id) return id, "", "", "", 0, 7, 6 end)
    local collect = CP.db.collect
    CP.db.collect = true
    local learned = {}
    for id, r in pairs(lw.recipes) do
        if (r.src == "trainer" or r.src == "auto") and r.learn <= 106 then learned[id] = true end
    end
    CP.charDB.lastPlan = nil
    local orders = {}
    for _, skill in ipairs({ 114, 115, 117 }) do
        local live = CP.Plan.Offline(lw, 165, skill, 150, learned)
        CP.charDB.lastPlan[165] = CP.Plan.Pack(live.plan)
        local seen, names = {}, {}
        for _, st in ipairs(live.plan) do
            if st.from < 121 then
                T.ok(not seen[st.spell], ("%s comes back at %d"):format(lw.recipes[st.spell].name, st.from))
                seen[st.spell] = true
                names[#names + 1] = lw.recipes[st.spell].name
            end
        end
        orders[#orders + 1] = table.concat(names, ",")
    end
    T.eq(orders[2], orders[1], "the order holds as skill goes up")
    T.eq(orders[3], orders[1])
    CP.db.collect = collect
end)

T.test("in Buy-and-power-level a trainer fee counts against a recipe", function()
    -- Two recipes, same materials and colors; one costs 50 gold to train.
    local g = { items = { [1] = { 100, true } }, recipes = {
        [1] = { name = "Free", src = "trainer", learn = 1, yellow = 50, grey = 100, reagents = { { 1, 1 } }, step = true, fee = 0 },
        [2] = { name = "Dear", src = "trainer", learn = 1, yellow = 50, grey = 100, reagents = { { 1, 1 } }, step = true, fee = 500000 },
    } }
    local price = function(_, item) return item and item[1] end
    g.recipes[1].reagents = { { 1, 2 } }   -- Free needs twice the materials
    local noFee = CP.Solver.Plan(g, 1, {}, price)
    T.eq(noFee[1].spell, 2, "without fees the cheaper materials win")
    local withFee = CP.Solver.Plan(g, 1, {}, price, nil, nil, nil, { fees = true })
    T.eq(withFee[1].spell, 1, "a 50 gold fee over 99 points outweighs 1 copper a point")
    local known = CP.Solver.Plan(g, 1, { [2] = true }, price, nil, nil, nil, { fees = true })
    T.eq(known[1].spell, 2, "no fee once learned")
end)

T.test("Forever's First Aid potions and poultices come from GUIDZ as trainer recipes", function()
    local minor
    for id, r in pairs(fa.recipes) do if r.name == "Minor Healing Potion" then minor = r end end
    T.ok(minor ~= nil, "Minor Healing Potion is in the guide")
    T.eq(minor.src, "trainer")
    T.eq(minor.learn, 1)
    T.eq(minor.fee, 100, "1s")
    T.ok(#minor.npcs > 0, "taught by First Aid trainers")
    local steps = CP.Solver.Plan(fa, 1, {}, listPrice)
    local names = {}
    for _, st in ipairs(steps) do names[fa.recipes[st.spell].name] = true end
    T.ok(names["Minor Healing Potion"] or names["Simple Poultice"], "the new recipes are used")
end)

T.test("a dropped Forever blueprint says where it drops", function()
    local rack
    for _, r in pairs(lw.recipes) do if r.name == "Tanning Rack" then rack = r end end
    if rack then
        T.eq(rack.src, "pattern")
        T.ok(rack.how and rack.how:find("Razorclaw the Butcher"), rack.how)
        T.ok(rack.how:find("Shadowfang Keep"), "and the zone")
        T.ok(CP.Guide.LearnText(rack):find("Razorclaw"), CP.Guide.LearnText(rack))
    else
        T.ok(true, "Tanning Rack isn't an alternative in this guide")
    end
end)

-- Green is a last resort ------------------------------------------------------------
-- A made-up guide: Yellow Kit is yellow over 100-110, Green Kit green there and cheaper
-- per point; Pattern Kit is a pattern, yellow there and dearest.
local YELLOW, GREEN, PATTERN = 9001, 9002, 9003
local DEAR, CHEAP, DEAREST = 9101, 9102, 9103
local function greenGuide()
    return {
        name = "Green test",
        recipes = {
            [YELLOW] = { name = "Yellow Kit", src = "trainer", learn = 90, yellow = 95, grey = 125, ups = 1,
                         reagents = { { DEAR, 1 } }, step = true },
            [GREEN] = { name = "Green Kit", src = "trainer", learn = 50, yellow = 60, grey = 110, ups = 1,
                        reagents = { { CHEAP, 1 } }, step = true },
            [PATTERN] = { name = "Pattern Kit", src = "pattern", learn = 90, yellow = 120, grey = 140, ups = 1,
                          reagents = { { DEAREST, 1 } }, pattern = 9201, step = true },
        },
        items = { [DEAR] = { 100, true }, [CHEAP] = { 1, true }, [DEAREST] = { 500, true } },
    }
end
local function only(set) return function(id) return set[id] == true end end

T.test("a known yellow recipe takes the points over a cheaper green one", function()
    local g = greenGuide()
    local learned = { [YELLOW] = true, [GREEN] = true }
    T.ok(CP.Professions.DifficultyAt(g.recipes[GREEN], 100) == CP.Professions.GREEN
        and CP.Professions.DifficultyAt(g.recipes[YELLOW], 109) == CP.Professions.YELLOW, "the scene")
    local steps = CP.Solver.Plan(g, 100, learned, listPrice, only(learned))
    T.eq(steps[1].spell, YELLOW, "Yellow Kit leads")
    T.ok(steps[1].to >= 110, "through the green stretch of Green Kit: " .. steps[1].to)
    for _, st in ipairs(steps) do T.ok(st.spell ~= GREEN, "Green Kit never takes a step") end
end)

T.test("an unowned pattern leads over a known green recipe, which stays its or row", function()
    local g = greenGuide()
    g.recipes[YELLOW] = nil   -- no trainer recipe yellow here: the pattern is the only one
    local learned = { [GREEN] = true }
    local allowed = { [GREEN] = true, [PATTERN] = true }
    local steps = CP.Solver.Plan(g, 100, learned, listPrice, only(allowed))
    T.eq(steps[1].spell, PATTERN, "the pattern leads")
    T.eq(steps[1].from, 100)
    local saved = CP.db.collect
    CP.db.collect = false
    local live = { guide = g, learned = learned, dead = {}, plan = { steps[1] }, sides = {}, prof = { max = 300 } }
    local ok, err = pcall(CP.Plan.AddFallbacks, live)
    CP.db.collect = saved
    T.ok(ok, err)
    local row = live.sides[1]
    T.ok(row and row.spell == GREEN and row.fallback, "Green Kit is the or row under the pattern")
    T.ok(CP.Plan.PatternOnly(live, PATTERN), "beside a pattern the player hasn't got")
end)

T.test("only a green recipe covers the points: it takes them, crafts counted at its chance", function()
    local g = greenGuide()
    local learned = { [GREEN] = true }
    local steps = CP.Solver.Plan(g, 100, learned, listPrice, only(learned))
    T.eq(steps[1].spell, GREEN, "no gap")
    T.eq(steps[1].from, 100)
    T.eq(steps[1].to, 110, "to where it greys")
    -- Chance at 100 is (110 - 100) / 50 = 20%, down to 2% at 109.
    local want = 0
    for s = 100, 109 do want = want + 1 / ((110 - s) / 50) end
    T.eq(steps[1].crafts, math.ceil(want), "the craft count follows the green chance")
    T.ok(steps[1].crafts > 40, "far more crafts than points: " .. steps[1].crafts)
end)
