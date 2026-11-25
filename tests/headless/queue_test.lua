-- Queue model against the generated Leatherworking and First Aid guides.

local CP = ProfLost
local Q = CP.Queue
local lw, fa = CP.Guides[165], CP.Guides[129]

T.test("default target is the player's current cap", function()
    T.eq(Q.DefaultTarget(lw, 80, 150), 150)
    T.eq(Q.DefaultTarget(lw, 160, 225), 225, "after training Artisan")
    T.eq(Q.DefaultTarget(lw, 150, 150), 225, "at the cap: the next rank, so the queue shows the training")
    T.eq(Q.DefaultTarget(lw, 290, 300), 300)
end)

T.test("a typed target is clamped to the guide", function()
    T.eq(Q.Clamp(lw, 80, 50), nil, "below skill")
    T.eq(Q.Clamp(lw, 80, 80), nil, "at skill")
    T.eq(Q.Clamp(lw, 80, 999), Q.End(lw))
    T.eq(Q.Clamp(lw, 80, "120"), 120)
end)

T.test("the queue runs from skill to target without holes", function()
    local q = Q.Build(lw, 80, 150, 150, lw.steps)
    T.ok(#q > 0)
    T.eq(q[1].from, 80)
    T.eq(q[#q].to, 150)
    for i = 2, #q do T.eq(q[i].from, q[i - 1].to) end
    for _, e in ipairs(q) do T.ok(e.crafts > 0, "crafts at " .. e.from) end
end)

T.test("the Expert book joins the queue only when the target passes 150", function()
    local function books(q)
        local n = 0
        for _, e in ipairs(q) do if e.kind == "rank" then n = n + 1 end end
        return n
    end
    T.eq(books(Q.Build(fa, 100, 150, 225, fa.steps)), 1)
    T.eq(books(Q.Build(fa, 100, 150, 150, fa.steps)), 0)
    T.eq(books(Q.Build(fa, 160, 225, 225, fa.steps)), 0, "already read")
end)

T.test("materials sum every craft in the queue", function()
    local q = Q.Build(lw, 80, 150, 150, lw.steps)
    local want = {}
    for _, e in ipairs(q) do
        for _, pair in ipairs(e.recipe.reagents) do
            want[pair[1]] = (want[pair[1]] or 0) + pair[2] * e.crafts
        end
    end
    local mats = Q.Materials(q)
    for i, m in ipairs(mats) do
        T.eq(m.need, want[m.itemID], "item " .. m.itemID)
        if i > 1 then T.ok(mats[i - 1].first <= m.first, "queue order") end
        want[m.itemID] = nil
    end
    T.eq(next(want), nil, "every material listed")
end)

T.test("short materials come first, soonest needed first; complete ones last", function()
    local mats = {
        { itemID = 1, need = 10, have = 10, first = 1 },  -- complete
        { itemID = 2, need = 20, have = 5, first = 3 },   -- short, needed later
        { itemID = 3, need = 4, have = 0, first = 1 },    -- short, needed now
        { itemID = 4, need = 8, have = 2, first = 1 },    -- short, needed now, bigger gap
        { itemID = 5, need = 3, have = 9, first = 2 },    -- complete
    }
    Q.SortMaterials(mats)
    local order = {}
    for i, m in ipairs(mats) do order[i] = m.itemID end
    T.eq(table.concat(order, ","), "4,3,2,1,5")
end)

T.test("materials record the first queue entry that uses them", function()
    local q = Q.Build(lw, 80, 150, 150, lw.steps)
    for _, m in ipairs(Q.Materials(q)) do
        local e = q[m.first]
        local uses = false
        for _, pair in ipairs(e.recipe.reagents) do if pair[1] == m.itemID then uses = true end end
        T.ok(uses, "entry " .. m.first .. " uses " .. m.itemID)
        for i = 1, m.first - 1 do
            for _, pair in ipairs(q[i].recipe.reagents) do T.ok(pair[1] ~= m.itemID, "no earlier use") end
        end
    end
end)

T.test("Target keeps a picked target ahead of skill, else the current cap", function()
    T.eq(Q.Target(lw, 80, 120, 150), 120)
    T.eq(Q.Target(lw, 80, 60, 150), 150, "below skill")
    T.eq(Q.Target(lw, 80, nil, 150), 150)
    T.eq(Q.Target(lw, 160, nil, 225), 225)
    T.eq(Q.Target(lw, 160, 999, 225), 300, "never past 300")
end)


T.test("vendor buys cover every unlearned vendor pattern and pending rank books", function()
    local vendorPatterns = 0
    for _, r in pairs(lw.recipes) do
        local sold = r.src == "vendor" or (r.src == "reputation" and r.faction)
        if sold and r.pattern and r.npcs then vendorPatterns = vendorPatterns + 1 end
    end
    T.ok(vendorPatterns > 0)
    local buys = CP.Guide.VendorBuys(lw, {}, 150)
    T.eq(#buys, vendorPatterns, "every vendor pattern, regardless of the queue")
    for i = 2, #buys do T.ok(buys[i - 1].skill <= buys[i].skill, "lowest skill first") end

    local first
    for spell, r in pairs(lw.recipes) do
        if r.src == "vendor" and r.pattern then first = spell break end
    end
    T.eq(#CP.Guide.VendorBuys(lw, { [first] = true }, 150), vendorPatterns - 1, "learned pattern drops out")

    local function hasBook(list)
        for _, b in ipairs(list) do if b.item == 16084 then return true end end
        return false
    end
    T.ok(hasBook(CP.Guide.VendorBuys(fa, {}, 150)), "book while capped at 150")
    T.ok(not hasBook(CP.Guide.VendorBuys(fa, {}, 225)), "no book once read")
end)

T.test("vendor watch lists every buy sold in the zone in one popup", function()
    local inZone, describe = CP.Waypoint.InZone, CP.Waypoint.Describe
    CP.Waypoint.InZone = function(npcs, _, zone)
        if zone ~= 70 then return nil end
        if npcs[1] == 13476 then return { name = "Balai Lok'Wein", continent = 1, x = 0, y = 0 } end
        if npcs[1] == 7 then return { name = "Pattern Vendor", continent = 1, x = 1, y = 1 } end
    end
    CP.Waypoint.Describe = function() return "Dustwallow Marsh (36.2, 31.4)" end
    World.patch("C_Item.GetItemCount", function() return 0 end)
    CP.charDB.vendorWatch = {
        [129] = { { name = "Expert First Aid - Under Wraps", item = 16084, skill = 125, npcs = { 13476 } } },
        [165] = { { name = "Pattern Thing", item = 9001, skill = 90, npcs = { 7 } } },
    }
    local found = CP.VendorWatch.Find(70)
    T.eq(#found, 2)
    T.eq(found[1].buy.item, 9001, "lowest skill first")
    local text = CP.VendorWatch.Text(found)
    T.ok(text:find("Pattern Thing (skill 90)", 1, true) ~= nil, "lists the pattern")
    T.ok(text:find("Expert First Aid", 1, true) ~= nil, "lists the book")
    T.ok(text:find("Dustwallow Marsh (36.2, 31.4)", 1, true) ~= nil, "names the zone and spot")
    T.ok(text:find("for future crafts", 1, true) ~= nil)
    T.eq(#CP.VendorWatch.Find(12), 0, "other zone")
    World.patch("C_Item.GetItemCount", function() return 1 end)
    T.eq(#CP.VendorWatch.Find(70), 0, "already bought")
    CP.Waypoint.InZone, CP.Waypoint.Describe = inZone, describe
    CP.charDB.vendorWatch = nil
end)

T.test("reputation patterns are watched with their faction and standing", function()
    local found
    for _, b in ipairs(CP.Guide.VendorBuys(CP.Guides[197], {}, 300)) do
        if b.item == 17018 then found = b end  -- Pattern: Flarecore Gloves (Tailoring)
    end
    T.ok(found ~= nil, "Flarecore Gloves is watched")
    T.eq(found.faction, 59)
    T.eq(found.standing, 5, "Friendly")
end)

T.test("a reputation pattern is offered only with the standing", function()
    local inZone, describe = CP.Waypoint.InZone, CP.Waypoint.Describe
    CP.Waypoint.InZone = function(_, _, zone)
        return zone == 70 and { name = "Lokhtos Darkbargainer", continent = 0, x = 0, y = 0 } or nil
    end
    CP.Waypoint.Describe = function() return "Blackrock Depths (50, 50)" end
    World.patch("C_Item.GetItemCount", function() return 0 end)
    CP.charDB.vendorWatch = { [165] = { { name = "Flarecore Gloves", item = 17018, skill = 300, npcs = { 12944 },
                                          faction = 59, standing = 5 } } }
    World.patch("C_Reputation.GetFactionDataByID", function() return { name = "Thorium Brotherhood", reaction = 4 } end)
    T.eq(#CP.VendorWatch.Find(70), 0, "Neutral is not enough")
    World.patch("C_Reputation.GetFactionDataByID", function() return { name = "Thorium Brotherhood", reaction = 5 } end)
    local found = CP.VendorWatch.Find(70)
    T.eq(#found, 1, "Friendly is")
    T.ok(CP.VendorWatch.Text(found):find("Thorium Brotherhood", 1, true) ~= nil, "names the faction")
    CP.Waypoint.InZone, CP.Waypoint.Describe = inZone, describe
    CP.charDB.vendorWatch = nil
end)

T.test("the queue puts a trainer visit before the crafts it unlocks", function()
    local bandages = function(id) return fa.recipes[id].name:find("Bandage") ~= nil end
    local steps = CP.Solver.Plan(fa, 100, { [3277] = true }, function(_, g) return g and g[1] > 0 and g[1] or nil end, bandages)
    local q = Q.Build(fa, 100, 150, 150, steps, { [3277] = true })
    local trainAt, heavyAt
    for i, e in ipairs(q) do
        if e.kind == "train" and e.train.skill == 115 then trainAt = trainAt or i end
        if e.kind == "craft" and e.spell == 3278 then heavyAt = heavyAt or i end
    end
    T.ok(trainAt ~= nil and heavyAt ~= nil)
    T.eq(trainAt + 1, heavyAt, "train, then craft")
    local function crafts(list)
        local n = 0
        for _, e in ipairs(list) do if e.kind == "craft" then n = n + e.crafts end end
        return n
    end
    T.eq(crafts(q), crafts(Q.Build(fa, 100, 150, 150, steps)), "train rows add no crafts")
end)

T.test("limited patterns say so, and a vendor without one marks it sold out", function()
    local bracers
    for _, b in ipairs(CP.Guide.VendorBuys(lw, {}, 150)) do
        if b.item == 18949 then bracers = b end  -- Pattern: Barbaric Bracers
    end
    T.ok(bracers and bracers.limited, "Barbaric Bracers pattern is limited")

    local inZone, describe = CP.Waypoint.InZone, CP.Waypoint.Describe
    CP.Waypoint.InZone = function(_, _, zone) return zone == 70 and { name = "Joseph Moore", continent = 0, x = 0, y = 0 } or nil end
    CP.Waypoint.Describe = function() return "Undercity (70.2, 58.0)" end
    World.patch("C_Item.GetItemCount", function() return 0 end)
    CP.charDB.vendorWatch = { [165] = { { name = "Barbaric Bracers", item = 18949, skill = 130, npcs = { 4589 }, limited = true } } }
    local found = CP.VendorWatch.Find(70)
    T.eq(#found, 1)
    T.ok(CP.VendorWatch.Text(found):find("limited stock", 1, true) ~= nil)

    CP.VendorWatch.CheckMerchant(4589, { [7451] = true })  -- Joseph Moore, without the pattern
    T.eq(#CP.VendorWatch.Find(70), 0, "sold out for the session")
    CP.Waypoint.InZone, CP.Waypoint.Describe = inZone, describe
    CP.charDB.vendorWatch = nil
end)

T.test("an unlearned limited pattern lists what to craft instead", function()
    -- A limited vendor pattern from the Leatherworking guide, as if it were a step.
    local spell, recipe
    for id, r in pairs(lw.recipes) do
        if r.limited and r.pattern and r.src == "vendor" and (not spell or id < spell) then spell, recipe = id, r end
    end
    T.ok(spell ~= nil, "the guide has a limited vendor pattern")
    local step = { spell = spell, recipe = recipe, from = recipe.learn, to = math.min(recipe.learn + 10, recipe.grey) }
    local live = { guide = lw, learned = {}, recipes = {} }
    -- A Horde skinner-leatherworker, set here rather than left over from another file.
    local faction = { UnitFactionGroup("player") }
    World.patch("UnitFactionGroup", function() return "Horde", "Horde" end)
    World.patch("GetProfessions", function() return 1, 2 end)
    World.patch("GetProfessionInfo", function(i) return nil, nil, nil, nil, nil, nil, i == 1 and 393 or 165 end)

    local alts = CP.Plan.Alternatives(live, step)
    T.ok(#alts > 0, "something else covers " .. step.from .. "-" .. step.to)
    for _, a in ipairs(alts) do T.ok(a.spell ~= spell, "never the limited pattern itself") end

    local text = CP.Plan.AlternativesText(live, step)
    T.ok(text and text:find("If sold out: ", 1, true) ~= nil, text)
    T.eq(CP.Plan.AlternativesText({ guide = lw, learned = { [spell] = true }, recipes = {} }, step), nil,
        "nothing to say once it's learned")
    World.patch("UnitFactionGroup", function() return unpack(faction) end)
end)

T.test("the queue's gold cost counts materials still to buy and training", function()
    local g = { items = { [1] = { 10, true }, [2] = { 50, false } } }
    local entries = {
        { kind = "train", train = { fee = 100 } },
        { kind = "craft" },
        { kind = "train", train = { fee = 0 } },
    }
    local mats = { { itemID = 1, need = 10, have = 4 }, { itemID = 2, need = 2, have = 5 } }
    local price = function(_, item) return item and item[1] end
    local total, materials, training, missing = Q.Cost(g, entries, mats, price)
    T.eq(materials, 60, "6 short at 10, the other covered")
    T.eq(training, 100)
    T.eq(total, 160)
    T.ok(not missing)
    local _, _, _, gap = Q.Cost(g, entries, { { itemID = 9, need = 1, have = 0 } }, price)
    T.ok(gap, "a material with no price is flagged")
end)
