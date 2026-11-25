-- A disenchant value with an unpriced material is a floor: the priced outcomes summed,
-- shown with "at least", the unpriced materials named in the row tooltip. With nothing priced
-- there is no value; with everything priced the value is unchanged.

local CP = ProfLost
local DE, DT = CP.Disenchant, CP.DisenchantTab
local DUST, LESSER = 10940, 10938

local function near(a, b) return math.abs(a - b) <= 1e-6 end

-- Group 1 yields 1.2 Strange Dust and 0.3 Lesser Magic Essence.
local ALL = { [DUST] = 1000, [LESSER] = 2000 }
local ONLY_DUST = { [DUST] = 1000 }
local function priced(t) return function(id) return t[id] end end

T.test("value: all priced is unchanged and not a floor", function()
    local v, missing = DE.Value(1, priced(ALL))
    T.ok(near(v, 1800))
    T.eq(missing, nil)
    local a = DE.Advice({ group = 1, vendor = 500 }, priced(ALL))
    T.eq(a.floor, nil)
    T.ok(near(a.de, 1800))
    T.eq(DT.ValueText(a):find("at least", 1, true), nil, "no floor mark")
end)

T.test("value: one unpriced outcome gives the priced sum and lists the rest", function()
    local v, missing = DE.Value(1, priced(ONLY_DUST))
    T.ok(near(v, 1200), "1.2 x 10s")
    T.eq(#missing, 1)
    T.eq(missing[1], LESSER)
end)

T.test("value: nothing priced is no value", function()
    local v, missing = DE.Value(1, priced({}))
    T.eq(v, nil)
    T.eq(#missing, 2)
    local a = DE.Advice({ group = 1, vendor = 4500 }, priced({}))
    T.eq(a.verdict, "unknown")
    T.eq(a.de, nil)
    T.eq(a.floor, nil)
end)

T.test("advice: a floor value is marked and used in the comparison", function()
    local a = DE.Advice({ group = 1, vendor = 500 }, priced(ONLY_DUST))
    T.eq(a.verdict, "de")
    T.eq(a.floor, true)
    T.eq(a.missing[1], LESSER)
    T.ok(near(a.de, 1200))
    T.ok(a.text:find("at least 12s", 1, true), a.text)
    T.ok(DT.ValueText(a):find("Disenchant at least 12s", 1, true), DT.ValueText(a))

    -- 20s beats the 12s floor by more than 10%, so it reads "sell".
    local sell = DE.Advice({ group = 1, vendor = 2000 }, priced(ONLY_DUST))
    T.eq(sell.verdict, "sell")
    T.ok(sell.text:find("at least 12s", 1, true), sell.text)
end)

T.test("the row tooltip names each unpriced material", function()
    local lines = {}
    World.set(CP, "ItemName", function(id) return id == LESSER and "Lesser Magic Essence" or "Strange Dust" end)
    World.set(GameTooltip, "SetOwner", function() end)
    World.set(GameTooltip, "SetHyperlink", function() end)
    World.set(GameTooltip, "AddLine", function(_, text) lines[#lines + 1] = tostring(text) end)
    World.set(GameTooltip, "Show", function() end)
    local item = { itemID = 1, advice = DE.Advice({ group = 1, vendor = 500 }, priced(ONLY_DUST)) }
    DT.RowTip({ item = item })
    T.eq(#lines, 1)
    T.eq(lines[1], "No price for Lesser Magic Essence")

    lines = {}
    item.advice = DE.Advice({ group = 1, vendor = 500 }, priced(ALL))
    DT.RowTip({ item = item })
    T.eq(#lines, 0, "nothing missing, nothing added")
end)

T.test("Money: a floor reads with the at-least mark", function()
    T.eq(DE.Money({ de = 1200 }), CP.Pricing.Format(1200))
    T.eq(DE.Money({ de = 1200, floor = true }), "at least " .. CP.Pricing.Format(1200))
    T.eq(DE.Money({ floor = true }, 500), "at least " .. CP.Pricing.Format(500))
end)
