-- Auction prices come from DaylightMogul, Daylight UI's Auction House, Auctionator,
-- ProfLost's own scan, then Glowey's Recipes (Pricing/Provider.lua), and the Scan button and the Shop tab's status
-- line step back while another addon has prices.

local CP = ProfLost
local Pricing, Scan, SB, S = CP.Pricing, CP.Scan, CP.ScanButton, CP.Style
local LIGHT, MEDIUM, HEAVY, THREAD = 2318, 2319, 4234, 2320
local NOW = 1800000000

-- ProfLost's scan as a plain table of { price, seenAt }; the clock at NOW.
local function scanned(prices)
    World.set(Scan, "Price", function(id)
        local e = prices[id]
        if not e then return nil end
        return e[1], e[2]
    end)
    World.set(Scan, "HasData", function() return next(prices) ~= nil end)
    World.patch("GetServerTime", function() return NOW end)
end

-- Counts Plan.Invalidate calls.
local function invalidations()
    local n = 0
    World.set(CP.Plan, "Invalidate", function() n = n + 1 end)
    return function() return n end
end

T.test("prices come from DaylightMogul, then Daylight UI's Auction House, then Auctionator, then our scan", function()
    scanned({ [LIGHT] = { 10, NOW }, [MEDIUM] = { 11, NOW }, [HEAVY] = { 12, NOW }, [THREAD] = { 13, NOW } })
    T.eq(select(2, Pricing.AuctionFrom(THREAD)), "scan", "our scan alone")

    AuctionatorWorld.begin({ prices = { [LIGHT] = 30, [MEDIUM] = 31, [HEAVY] = 32 } })
    T.eq({ Pricing.AuctionFrom(HEAVY) }, { 32, "auctionator" }, "Auctionator before our scan")
    T.eq(Pricing.Auction(THREAD), 13, "our scan fills what Auctionator lacks")

    DUIAHWorld.begin({ prices = { [LIGHT] = { 40, NOW }, [MEDIUM] = { 41, NOW } }, scannedAt = NOW })
    T.eq({ Pricing.AuctionFrom(MEDIUM) }, { 41, "daylight", 0 }, "Daylight UI's Auction House before Auctionator")
    T.eq(Pricing.Auction(HEAVY), 32, "Auctionator fills what Daylight UI lacks")

    MogulWorld.begin({ prices = { [LIGHT] = 50 } })
    T.eq({ Pricing.AuctionFrom(LIGHT) }, { 50, "mogul" }, "DaylightMogul first")
    T.eq(Pricing.Auction(MEDIUM), 41, "Daylight UI fills what Mogul lacks")

    local price, source = Pricing.Get(LIGHT, { 60, false })
    T.eq(price, 50)
    T.eq(source, "auction", "Get still calls it an auction price")
    T.eq(select(2, Pricing.Get(THREAD, { 10, true })), "vendor", "a vendor good stays at the vendor")
    T.eq(select(2, Pricing.SaleValue(MEDIUM)), math.floor(41 * 0.95), "sale value reads the same order")
end)

T.test("Glowey's Recipes prices last, after our own scan, through its public API", function()
    scanned({ [LIGHT] = { 10, NOW - 600 } })
    GloweyWorld.begin({ prices = { [LIGHT] = 70, [MEDIUM] = 71 }, ages = { [LIGHT] = 5, [MEDIUM] = 3600 } })
    T.eq({ Pricing.AuctionFrom(LIGHT) }, { 10, "scan", 600 }, "our scan before Glowey's")
    T.eq({ Pricing.AuctionFrom(MEDIUM) }, { 71, "glowey", 3600 }, "Glowey fills what our scan lacks, with its age")
    AuctionatorWorld.begin({ prices = { [MEDIUM] = 31 } })
    T.eq(select(2, Pricing.AuctionFrom(MEDIUM)), "auctionator", "Auctionator before Glowey")
    DUIAHWorld.begin({ prices = { [MEDIUM] = { 41, NOW } }, scannedAt = NOW })
    T.eq(select(2, Pricing.AuctionFrom(MEDIUM)), "daylight", "Daylight UI before Glowey")
    MogulWorld.begin({ prices = { [MEDIUM] = 50 } })
    T.eq(select(2, Pricing.AuctionFrom(MEDIUM)), "mogul", "DaylightMogul before Glowey")

    T.eq(Pricing.config.order[#Pricing.config.order], "glowey", "Glowey is the last in the one order list")
    T.eq(Pricing.config.names.glowey, "Glowey's Recipes")

    World.set(DaylightRecipes.API, "Price", function() error("boom") end)
    T.eq(Pricing.Auction(THREAD), nil, "an error reads as no price")
    World.set(_G, "DaylightRecipes", {})
    T.eq(Pricing.Auction(THREAD), nil, "an API that is gone reads as no price")
end)

T.test("Glowey's Recipes counts as data but never stops our scan, and its changes re-rank plans", function()
    scanned({})
    GloweyWorld.begin({ prices = { [LIGHT] = 70 } })
    T.eq(Pricing.HasAuctionData(), true, "it holds prices")
    T.eq(Pricing.AddonSource(), nil, "it fills after our scan, so it is not the source that comes first")
    local n = invalidations()
    Pricing.Listen()
    GloweyWorld.Changed()
    T.eq(n(), 1, "Glowey's price event re-ranks")
end)

T.test("Daylight UI's table is absent while DaylightMogul owns the Auction House, and appears when published", function()
    scanned({})
    DUIAHWorld.begin({ prices = { [LIGHT] = { 40, NOW } }, scannedAt = NOW, mogul = true })
    AuctionatorWorld.begin({ prices = { [LIGHT] = 30 } })
    T.eq(select(2, Pricing.AuctionFrom(LIGHT)), "auctionator", "no table: Auctionator")
    DUIAHWorld.Publish()
    T.eq(select(2, Pricing.AuctionFrom(LIGHT)), "daylight", "read per call, so a late table counts")
end)

T.test("Auctionator is asked with ProfLost's caller id, and its errors read as no price", function()
    scanned({ [LIGHT] = { 10, NOW } })
    AuctionatorWorld.begin({ prices = { [LIGHT] = 30 } })
    T.eq(Pricing.Auction(LIGHT), 30)
    T.ok(AuctionatorWorld.state.callers[Pricing.config.caller], "a named caller")
    World.set(Auctionator.API.v1, "GetAuctionPriceByItemID", function() error("boom") end)
    T.eq(select(2, Pricing.AuctionFrom(LIGHT)), "scan", "an error falls through to our scan")
end)

T.test("each source's own age: Daylight's sighting, Auctionator's days, our scan; none for Mogul", function()
    scanned({ [THREAD] = { 13, NOW - 600 } })
    DUIAHWorld.begin({ prices = { [LIGHT] = { 40, NOW - 7200 } }, scannedAt = NOW - 60 })
    AuctionatorWorld.begin({ prices = { [MEDIUM] = 31, [HEAVY] = 32 }, ages = { [MEDIUM] = 2 } })
    T.eq(Pricing.AuctionAge(LIGHT), 7200, "Daylight UI: since its sighting")
    T.eq(Pricing.AuctionAge(MEDIUM), 2 * 86400, "Auctionator: its whole days")
    T.eq(Pricing.AuctionAge(HEAVY), nil, "Auctionator without an age")
    T.eq(Pricing.AuctionAge(THREAD), 600, "our scan")
    MogulWorld.begin({ prices = { [LIGHT] = 50 } })
    T.eq(Pricing.AuctionAge(LIGHT), nil, "Mogul gives no age")
end)

T.test("auction data and the addon source count every source", function()
    scanned({})
    T.eq(Pricing.HasAuctionData(), false, "nothing anywhere")
    T.eq(Pricing.AddonSource(), nil)

    AuctionatorWorld.begin({ prices = { [7777] = 5 } })
    T.eq(Pricing.HasAuctionData(), false, "Auctionator without a staple priced")
    AuctionatorWorld.SetPrice(2589, 20)
    T.eq(Pricing.HasAuctionData(), true, "a staple priced in Auctionator")
    T.eq({ Pricing.AddonSource() }, { "auctionator", "Auctionator" })

    DUIAHWorld.begin({ scannedAt = nil })
    T.eq(Pricing.AddonSource(), "auctionator", "Daylight UI before its first scan holds nothing")
    DUIAHWorld.SetScannedAt(NOW)
    T.eq({ Pricing.AddonSource() }, { "daylight", "Daylight UI's Auction House" })
end)

T.test("Daylight UI's and Auctionator's price updates re-rank plans", function()
    scanned({})
    MogulWorld.begin({})
    DUIAHWorld.begin({ scannedAt = NOW })
    AuctionatorWorld.begin({})
    local n = invalidations()
    Pricing.Listen()
    T.eq(#DUIAHWorld.Handlers("AuctionPricesChanged"), 1, "listens to AuctionPricesChanged")
    DUIAHWorld.Changed()
    T.eq(n(), 1, "Daylight UI's event re-ranks")
    AuctionatorWorld.Updated()
    T.eq(n(), 2, "Auctionator's update re-ranks")
    MogulWorld.PricesChanged()
    T.eq(n(), 3, "Mogul's still does")
    T.fire("AUCTION_HOUSE_CLOSED")
    T.eq(n(), 3, "Auctionator with its callback: closing the auction house adds nothing")
end)

T.test("an Auctionator without its update callback re-ranks plans when the auction house closes", function()
    scanned({})
    AuctionatorWorld.begin({ callback = false })
    local n = invalidations()
    Pricing.Listen()
    T.fire("AUCTION_HOUSE_CLOSED")
    T.eq(n(), 1)
end)

-- The Scan button and the Shop tab's line ------------------------------------------------------

local function ahOpen()
    Scan.Stop()
    local panelShown = CP.Panel.frame:IsShown()
    CP.Panel.frame:Hide()
    World.onEnd(function()
        Scan.Stop()
        if panelShown then CP.Panel.frame:Show() end
        -- The list's route update waits out its quiet time; let it run before the world ends.
        T.advance(CP.GatherList.ROUTE_MOST + 1)
    end)
    T.advance(1)
    AHWorld.begin({ listings = {}, now = NOW })
    World.set(Scan, "CooldownLeft", function() return 0 end)
end

T.test("with Daylight UI's or Auctionator's prices the Scan button stays but doesn't pulse, and says whose prices come first", function()
    ahOpen()
    scanned({})
    AHWorld.Open()
    local b = SB.button
    T.ok(b:IsShown())
    T.ok(S.Pulsing(b), "no other prices: it pulses")

    DUIAHWorld.begin({ scannedAt = nil })
    Pricing.Listen()
    DUIAHWorld.SetScannedAt(NOW)
    DUIAHWorld.Changed()
    T.ok(b:IsShown(), "still on the auction house window")
    T.ok(not S.Pulsing(b), "Daylight UI's prices: no pulse")

    local lines = {}
    World.set(GameTooltip, "AddLine", function(_, text) lines[#lines + 1] = tostring(text) end)
    b:GetScript("OnEnter")(b)
    T.ok(table.concat(lines, "\n"):find("Prices come from Daylight UI's Auction House first; this scan fills the rest.", 1, true) ~= nil,
        "the tooltip names the source")

    AHWorld.Close()
    World.set(DUIAHWorld.state.dui, "AuctionPrices", nil)
    AuctionatorWorld.begin({ prices = { [2589] = 20 } })
    AHWorld.Open()
    T.ok(not S.Pulsing(b), "Auctionator's prices: no pulse")
end)

T.test("the Shop tab's status line names the addon prices come from and stops asking for a scan", function()
    ahOpen()
    scanned({})
    local ui = CP.ShopTab.ui
    World.set(CP.db, "collect", false)
    DUIAHWorld.begin({ scannedAt = NOW - 7200 })
    Pricing.Listen()
    DUIAHWorld.Changed()
    T.eq(ui.scanText:GetText(), "Prices from Daylight UI's Auction House, updated 2 h ago")

    World.set(DUIAHWorld.state.dui, "AuctionPrices", nil)
    AuctionatorWorld.begin({ prices = { [2589] = 20 } })
    CP.ShopTab.Changed()
    T.eq(ui.scanText:GetText(), "Prices from Auctionator", "no scan hint while another addon prices")
end)
