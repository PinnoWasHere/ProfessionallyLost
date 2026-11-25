-- Review items 11 and 26: an item a full scan no longer saw stops passing as an auction
-- price, and Buy for guide counts a shared reagent's stock once across professions.

local CP = ProfLost
local Scan, B = CP.Scan, CP.Buying
local LIGHT, MEDIUM = 2318, 2319
local NOW = 1800000000
local THREAD = 2320

-- Item 11 -------------------------------------------------------------------------------------

local function fullScan(listings, at)
    AHWorld.begin({ listings = {}, now = at, replicate = listings })
    AHWorld.Open()
    T.ok(Scan.Start(), "started")
    AHWorld.SendList()
    T.advance(0.1)
    T.advance(1)
    local t = 0
    while Scan.Running() and t < 30 do
        T.advance(0.1)
        t = t + 0.1
    end
    T.ok(not Scan.Running(), "done")
end

T.test("a full scan that no longer sees an item drops its old price from Pricing", function()
    Scan.Stop()
    local panelShown = CP.Panel.frame:IsShown()
    CP.Panel.frame:Hide()
    World.onEnd(function()
        Scan.Stop()
        CP.db.prices, CP.db.priceScans, CP.db.priceAsked = nil, nil, nil
        if panelShown then CP.Panel.frame:Show() end
    end)
    T.advance(1)
    CP.db.prices, CP.db.priceScans, CP.db.priceAsked = nil, nil, nil

    fullScan({
        { itemID = MEDIUM, count = 20, buyout = 3000 },
        { itemID = LIGHT, count = 10, buyout = 450 },
    }, NOW)
    T.eq(select(1, CP.Pricing.Get(MEDIUM, nil)), 150, "first scan prices Medium Leather")

    AHWorld.SetNow(NOW + 3 * 86400)
    T.advance(Scan.config.cooldown + 1)
    fullScan({ { itemID = LIGHT, count = 10, buyout = 400 } }, NOW + 3 * 86400)
    T.eq(Scan.Price(LIGHT), 40, "a seen item is updated")
    T.eq(Scan.Price(MEDIUM), nil, "an unseen item is no longer a current price")
    T.eq(CP.Pricing.Get(MEDIUM, nil), nil, "Pricing.Get has no auction price for it")
    T.eq(CP.Pricing.AuctionAge(MEDIUM), nil, "and no age to show")
end)

-- Item 26 -------------------------------------------------------------------------------------

local function row(crafts)
    return { spell = 1, from = 1, crafts = crafts, recipe = { name = "R", reagents = { { THREAD, 1 } } } }
end

local function wants(held, crafts)
    World.patch("C_Item.GetItemCount", function() return held end)
    local live = function(name) return { prof = { name = name, skill = 100, max = 150 }, guide = { recipes = {}, ranks = {} }, plan = {} } end
    World.set(B, "Targets", function()
        return { { live = live("Tailoring"), row = row(crafts) }, { live = live("Leatherworking"), row = row(crafts) } }
    end)
    World.set(B, "GatherBooks", function() return {} end)
    local stock = { [THREAD] = { index = 1, price = 100, stack = 1 } }
    local lines, total = B.Wants(stock)
    return lines, total
end

T.test("Buy for guide counts a shared reagent's stock once across professions", function()
    local lines = wants(10, 10)
    T.eq(#lines, 1, "10 of the 20 needed are held, so 10 are offered")
    T.eq(lines[1] and lines[1].count, 10)

    lines = wants(5, 10)
    T.eq(lines[1] and lines[1].count, 15, "5 held of 20 needed")

    lines = wants(0, 10)
    T.eq(lines[1] and lines[1].count, 20, "none held")

    lines = wants(25, 10)
    T.eq(#lines, 0, "enough for both")
end)
