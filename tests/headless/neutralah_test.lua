-- A neutral auction house (Booty Bay, Gadgetzan, Everlook) feeds no prices; a faction one does.

local CP = ProfLost
local Scan = CP.Scan
local LIGHT, MEDIUM = 2318, 2319
local NOW = 1800000000
local STRANGLETHORN, ELWYNN = 1434, 1429
local NEUTRAL_LINE = "Neutral auction house: prices not recorded"

-- Opens the auction house on `map`, with `replicate` as its full list.
local function visit(map, listings, replicate)
    Scan.Stop()
    local panelShown = CP.Panel.frame:IsShown()
    CP.Panel.frame:Hide()
    World.onEnd(function()
        if panelShown then CP.Panel.frame:Show() end
    end)
    T.advance(1)
    CP.db.prices, CP.db.priceScans, CP.db.priceAsked = nil, nil, nil
    World.onEnd(function()
        Scan.Stop()
        CP.db.prices, CP.db.priceScans, CP.db.priceAsked = nil, nil, nil
    end)
    World.set(C_Map, "GetBestMapForUnit", function() return map end)
    AHWorld.begin({ listings = listings, now = NOW, replicate = replicate })
    AHWorld.Open()
end

local function list()
    return {
        { itemID = MEDIUM, count = 20, buyout = 3000 },
        { itemID = LIGHT, count = 10, buyout = 450 },
    }
end

local function runOut()
    local t = 0
    while Scan.Running() and t < 30 do T.advance(0.1); t = t + 0.1 end
end

T.test("a full scan at a neutral auction house records nothing and says so", function()
    visit(STRANGLETHORN, {}, list())
    CP.db.prices = { [Scan.RealmKey()] = { [LIGHT] = { 99, NOW - 100 } } }
    T.ok(Scan.neutral, "Booty Bay's zone is neutral")
    local ok, why = Scan.Start()
    T.ok(not ok, "no scan starts")
    T.eq(why, NEUTRAL_LINE)
    T.ok(not Scan.Running(), "nothing runs")
    T.eq(#AHWorld.state.asks, 0, "the list is never asked for")
    T.eq(Scan.Price(LIGHT), 99, "the saved price stays")
    T.eq(Scan.Price(MEDIUM), nil, "nothing new was kept")
    T.eq(Scan.LastTime(), nil, "no scan is dated")
end)

T.test("a neutral auction house says so even on a client without the full list", function()
    visit(STRANGLETHORN, {})
    World.set(C_AuctionHouse, "ReplicateItems", nil)
    local ok, why = Scan.Start()
    T.ok(not ok, "nothing starts")
    T.eq(why, NEUTRAL_LINE)
    T.ok(not Scan.Running())
    T.eq(#AHWorld.state.sent, 0, "no item searches")
    T.eq(Scan.Price(LIGHT), nil)
end)

T.test("the neutral line comes back from every Scan click at a neutral house, and the flag clears when it closes", function()
    visit(STRANGLETHORN, {}, list())
    T.eq(select(2, Scan.Start()), NEUTRAL_LINE, "first click")
    T.eq(select(2, Scan.Start()), NEUTRAL_LINE, "second click")
    AHWorld.Close()
    T.ok(not Scan.neutral, "the flag clears on close")
    World.set(C_Map, "GetBestMapForUnit", function() return ELWYNN end)
    AHWorld.Open()
    T.ok(not Scan.neutral, "a faction house on the next visit")
    T.ok(Scan.Start(), "scans again")
end)

T.test("a faction auction house scans and records as before", function()
    visit(ELWYNN, {}, list())
    T.ok(not Scan.neutral, "Elwynn is not neutral")
    T.ok(Scan.Start(), "started")
    AHWorld.SendList()
    runOut()
    T.eq(Scan.Price(MEDIUM), 150)
    T.eq(Scan.Price(LIGHT), 45)
    T.eq(Scan.LastTime(), NOW)
end)
