-- Materials shared between guides: cloth for First Aid and Tailoring, and Tailoring
-- greens disenchanted for Enchanting.

local CP = ProfLost
local Sh = CP.Shared
local TAILORING, FIRST_AID, ENCHANTING = 197, 129, 333
local LINEN, STRANGE_DUST, LESSER_MAGIC = 2589, 10940, 10938
local BROWN_LINEN_ROBE = 7623   -- makes a green that disenchants

local function withChar(fields, fn)
    local saved = {}
    for k, v in pairs(fields) do
        saved[k] = CP.charDB[k]
        CP.charDB[k] = v
    end
    local ok, err = pcall(fn)
    for k in pairs(fields) do CP.charDB[k] = saved[k] end
    if not ok then error(err, 0) end
end

T.test("each guide sees the other's need for the same cloth", function()
    withChar({ gatherNeeds = { [TAILORING] = { [LINEN] = 160 }, [FIRST_AID] = { [LINEN] = 80 } } }, function()
        T.eq(Sh.Tag(TAILORING, LINEN), "+80 First Aid")
        T.eq(Sh.Tag(FIRST_AID, LINEN), "+160 Tailoring")
        T.eq(Sh.Tag(TAILORING, 4306), nil, "Silk isn't wanted by First Aid here")
        local others = Sh.Others(TAILORING, LINEN)
        T.eq(#others, 1)
        T.eq(others[1].need, 80)
    end)
end)

T.test("three guides wanting one item sum into 'other guides'", function()
    withChar({ gatherNeeds = { [TAILORING] = { [LINEN] = 160 }, [FIRST_AID] = { [LINEN] = 80 },
                               [165] = { [LINEN] = 20 } } }, function()
        T.eq(Sh.Tag(TAILORING, LINEN), "+100 other guides")
    end)
end)

T.test("a green's disenchant yield scales with what one craft makes", function()
    local r = CP.Guides[TAILORING].recipes[BROWN_LINEN_ROBE]
    local y = Sh.DEYield(r)
    T.ok(#y >= 2, "dust and essence")
    local dust = 0
    for _, m in ipairs(y) do if m.item == STRANGE_DUST then dust = m.count end end
    T.ok(dust > 0.5, "mostly Strange Dust")
    T.eq(#Sh.DEYield({ name = "Linen Bandage", makes = 1251 }), 0, "a bandage doesn't disenchant")
end)

T.test("a crafted green the game made of a classic white is credited as the Disenchant tab disenchants it", function()
    -- Copper Chain Belt: green (quality 2, item level 11, armour) in the client, white with no group in
    -- classic-db. The data gives it its band's group, so the plan's credit is the tab's yield.
    local BELT = 2851
    local band = CP.DisenchantData.bands[2].armor
    local want
    for _, b in ipairs(band) do
        if 11 <= b[1] then want = b[2] break end
    end
    T.eq(CP.DisenchantData.items[BELT], want, "the data's group is its band's")
    T.eq(CP.Disenchant.Group(BELT, 2, 11, 4), want, "the tab finds the same group")
    local y = Sh.DEYield(CP.Guides[164].recipes[2661])
    local tab = CP.Disenchant.Yield(want)
    T.eq(#y, #tab, "the credit's materials are the tab's")
    for i, m in ipairs(tab) do
        T.eq(y[i] and y[i].item, m.item)
        T.eq(y[i] and y[i].count, m.count)
    end
    -- Copper Bracers stay white in the client: no group.
    T.eq(CP.DisenchantData.items[2853], nil, "a white bracer disenchants into nothing")
end)

-- Enchanting's needs as a test states them (Shared.EnchantingNeeds reads its current plan).
local function needsOf() return CP.charDB.gatherNeeds[ENCHANTING] end

T.test("credit only with Enchanting, only for materials it still needs", function()
    local r = CP.Guides[TAILORING].recipes[BROWN_LINEN_ROBE]
    withChar({ gatherNeeds = { [ENCHANTING] = { [STRANGE_DUST] = 50 } } }, function()
        T.eq(Sh.CreditFor(TAILORING, true, {}, needsOf()), nil, "no Enchanting, no credit")
        T.eq(Sh.CreditFor(ENCHANTING, true, { [ENCHANTING] = true }, needsOf()), nil, "Enchanting doesn't credit itself")
        local credit = Sh.CreditFor(TAILORING, true, { [ENCHANTING] = true, [TAILORING] = true }, needsOf())
        local cost = credit(BROWN_LINEN_ROBE, r, 10)
        T.ok(cost < 10, "a robe costs less when its dust is needed")
        T.ok(cost >= 2.5, "but never under a quarter of its materials")
        T.eq(credit(3915, CP.Guides[TAILORING].recipes[3915] or { reagents = {} }, 10), 10, "a white item gets nothing")
    end)
    withChar({ gatherNeeds = { [ENCHANTING] = { [LESSER_MAGIC] = 0 } } }, function()
        local credit = Sh.CreditFor(TAILORING, true, { [ENCHANTING] = true }, needsOf())
        T.eq(credit(BROWN_LINEN_ROBE, r, 10), 10, "Enchanting needs none of it")
    end)
end)

T.test("Level-as-you-go Tailoring picks more disenchantable greens with Enchanting", function()
    local guide = CP.Guides[TAILORING]
    local function greens(opts)
        local n = 0
        for _, st in ipairs(CP.Solver.Plan(guide, 1, {}, CP.Pricing.GetCollect, nil, nil, {}, opts)) do
            if st.spell and #Sh.DEYield(guide.recipes[st.spell]) > 0 then n = n + (st.to - st.from) end
        end
        return n
    end
    withChar({ gatherNeeds = { [ENCHANTING] = { [STRANGE_DUST] = 200, [LESSER_MAGIC] = 40, [10939] = 30,
                                                [10998] = 20, [11083] = 100, [11134] = 20 } } }, function()
        local plain = greens({ rareFromStock = true })
        local credited = greens({ rareFromStock = true,
                                  credit = Sh.CreditFor(TAILORING, true, { [ENCHANTING] = true }, needsOf()) })
        T.ok(credited > plain, ("skill points on greens: %d with Enchanting, %d without"):format(credited, plain))
    end)
end)

T.test("the Enchanting guide counts dust coming from Tailoring's planned greens", function()
    -- No committed plan, so the guide counts by its last solve.
    withChar({ committed = {}, lastPlan = { [TAILORING] = { { 25, 45, BROWN_LINEN_ROBE } } } }, function()
        local n, from = Sh.DEIncoming(STRANGE_DUST)
        T.ok(n > 5, "about a dust per robe")
        T.eq(from[1], "Tailoring")
        T.eq((Sh.DEIncoming(11083)), 0, "no Soul Dust from linen robes")
    end)
end)
