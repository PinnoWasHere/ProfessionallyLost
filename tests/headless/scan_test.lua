-- ProfLost's own auction price scan (Pricing/Scan.lua), the ProfLost Scan button on the auction
-- house window (UI/ScanButton.lua) and their place in pricing.

local CP = ProfLost
local Scan, SB, S = CP.Scan, CP.ScanButton, CP.Style
local LIGHT, MEDIUM, THREAD, HEAVY = 2318, 2319, 2320, 4234
local ARMOR_KIT = 2304    -- made by Leatherworking, used by no recipe
local SWORD = 19019       -- in no guide
local NOW = 1800000000

-- Item searches sent, as item IDs, and when. The scan sends none.
local sent

local function setup(spec)
    spec = spec or {}
    Scan.Stop()    -- an earlier test can leave one running

    -- An earlier file can leave the panel open; its refreshes aren't under test here.
    local panelShown = CP.Panel.frame:IsShown()
    CP.Panel.frame:Hide()
    World.onEnd(function()
        if panelShown then CP.Panel.frame:Show() end
    end)
    T.advance(1)   -- clear the pacing gap left by an earlier test
    CP.db.prices, CP.db.priceScans, CP.db.priceAsked = nil, nil, nil
    AHWorld.begin({ listings = {}, now = NOW, replicate = spec.replicate })
    sent = AHWorld.state.sent
    World.onEnd(function()
        Scan.Stop()
        CP.db.prices, CP.db.priceScans, CP.db.priceAsked = nil, nil, nil
    end)
    if spec.open ~= false then AHWorld.Open() end
end

-- A full list: commodities, an item, vendor stock, an item no guide uses, a bid-only
-- row and a row whose item comes later.
local function market1()
    return {
        { itemID = MEDIUM, count = 20, buyout = 3000 },    -- 150 each
        { itemID = MEDIUM, count = 5, buyout = 1000 },     -- 200 each
        { itemID = LIGHT, count = 10, buyout = 450 },      -- 45 each
        { itemID = LIGHT, count = 1, buyout = 0 },         -- bid only
        { itemID = LIGHT, count = 4, buyout = 160 },       -- 40 each
        { itemID = ARMOR_KIT, count = 1, buyout = 900 },
        { itemID = THREAD, count = 20, buyout = 20 },      -- vendor stock: 1 each
        { itemID = SWORD, count = 1, buyout = 5000000 },
        { itemID = HEAVY, count = 2, buyout = 1300, blank = true },
    }
end

-- Runs the timers and frames until the full scan ends, at most `seconds`.
local function runOut(seconds)
    local t = 0
    while Scan.Running() and t < (seconds or 30) do
        T.advance(0.1)
        t = t + 0.1
    end
end

-- Gives the button an alpha the harness keeps, and returns a reader for it.
local function alphaOf(b)
    local a = 1
    World.set(b, "SetAlpha", function(_, v) a = v end)
    World.set(b, "GetAlpha", function() return a end)
    return function() return a end
end

-- The button, made by a first visit if none was. The scene's auction house is shut.
local function button()
    if not SB.button then
        AHWorld.Open()
        AHWorld.Close()
    end
    return SB.button
end

-- The profession item set ---------------------------------------------------------------------

-- True when some guide says a vendor always stocks the item.
local function isVendor(id)
    for _, g in pairs(CP.Guides) do
        local item = g.items and g.items[id]
        if item and item[2] == true then return true end
    end
    return false
end

T.test("the profession items the tooltip counts: every guide's reagents and made items, alternatives too, vendor stock left out", function()
    Scan.ResetInterest()
    local set = Scan.Interest()
    T.ok(set[LIGHT] and set[MEDIUM] and set[HEAVY], "reagents")
    T.ok(set[ARMOR_KIT], "an item a recipe makes")
    T.ok(not set[THREAD], "Coarse Thread is vendor stock")
    T.ok(not set[SWORD], "an item no profession uses")
    local missing = 0
    for _, g in pairs(CP.Guides) do
        for _, step in ipairs(g.steps or {}) do
            for _, alt in ipairs(step.alt or {}) do
                for _, re in ipairs(g.recipes[alt] and g.recipes[alt].reagents or {}) do
                    if not set[re[1]] and not isVendor(re[1]) then missing = missing + 1 end
                end
            end
        end
        for _, r in pairs(g.recipes or {}) do
            if r.makes and not set[r.makes] and not isVendor(r.makes) then missing = missing + 1 end
        end
    end
    T.eq(missing, 0, "every alternative's materials and every made item")
    T.ok(Scan.InterestCount() > 300, "all professions, not only the player's")
end)

-- The full scan --------------------------------------------------------------------------------

T.test("the Scan button asks for the whole list once and sends no item searches", function()
    setup({ replicate = market1() })
    local b = button()
    b:GetScript("OnClick")(b)
    T.ok(Scan.Running(), "started")
    T.eq(#AHWorld.state.asks, 1, "one ask for the whole list")
    AHWorld.SendList()
    AHWorld.Fill(8)
    runOut()
    T.eq(#AHWorld.state.asks, 1, "still one ask")
    T.eq(#sent, 0, "no item searches")
end)

T.test("a client without the full list sends no item searches and says why", function()
    setup()
    World.set(C_AuctionHouse, "ReplicateItems", nil)
    T.ok(not Scan.FullAvailable())
    local b = button()
    b:GetScript("OnClick")(b)
    T.advance(Scan.config.answerWait)
    T.ok(not Scan.Running(), "nothing runs")
    T.eq(#sent, 0, "no item searches")
    local prints = T.prints()
    T.ok(prints[#prints]:find("This game client can't read the whole auction house, so it can't scan prices.", 1, true) ~= nil,
        prints[#prints])
end)

T.test("a full scan asks once and keeps the lowest unit buyout of every item on the list", function()
    setup({ replicate = market1() })
    T.ok(Scan.FullAvailable(), "the client has the full list")
    T.ok(Scan.Start(), "started")
    T.eq(#AHWorld.state.asks, 1, "one ask for the whole list")
    T.eq(#sent, 0, "no item searches")
    T.eq(Scan.ProgressText(), "Asking the auction house")
    T.eq(CP.db.priceAsked[Scan.RealmKey()], NOW, "the ask is dated: the cooldown starts there")
    AHWorld.SendList()
    T.advance(0.1)
    T.eq(Scan.ProgressText(), "Reading 9 / 9")
    T.advance(1)
    T.ok(Scan.Running(), "the list settles before the scan ends")
    AHWorld.Fill(8)
    runOut()
    T.ok(not Scan.Running(), "done")
    T.eq(Scan.Price(MEDIUM), 150, "the cheaper stack's unit price")
    T.eq(Scan.Price(LIGHT), 40, "lowest of three stacks; bid only skipped")
    T.eq(Scan.Price(ARMOR_KIT), 900, "a made item")
    T.eq(Scan.Price(HEAVY), 650, "a row whose item came later")
    T.eq(Scan.Price(THREAD), 1, "vendor stock is priced too")
    T.eq(Scan.Price(SWORD), 5000000, "and an item no profession uses")
    T.eq(select(2, Scan.Price(MEDIUM)), NOW)
    T.eq(Scan.LastTime(), NOW, "a finished scan is dated")
    local prints = T.prints()
    T.ok(prints[#prints]:find("Price scan done: 6 items priced (4 profession items), 9 auctions read", 1, true) ~= nil,
        "the done line: " .. prints[#prints])
end)

local function bigList()
    local rows = {}
    for i = 1, 1200 do rows[i] = { itemID = (i % 2 == 0) and LIGHT or SWORD, count = 1, buyout = 100 + i } end
    return rows
end

T.test("reading spreads over frames: at most a slice of rows a frame", function()
    setup({ replicate = bigList() })
    T.eq(Scan.config.slice, 500)
    Scan.Start()
    AHWorld.SendList()
    T.eq(AHWorld.state.reads, 0, "nothing read inside the event")
    local perFrame = {}
    for _ = 1, 3 do
        local before = AHWorld.state.reads
        T.advance(0.1)
        perFrame[#perFrame + 1] = AHWorld.state.reads - before
    end
    T.eq(perFrame, { 500, 500, 200 }, "a slice a frame")
    runOut()
    T.eq(Scan.Price(LIGHT), 102)
    T.eq(Scan.Price(SWORD), 101)
end)

T.test("reading stops early in a frame once its time budget is spent", function()
    setup({ replicate = bigList() })
    -- Each look at the clock costs 1 ms here.
    local ms = 0
    World.set(_G, "debugprofilestop", function()
        ms = ms + 1
        return ms
    end)
    Scan.Start()
    AHWorld.SendList()
    local before = AHWorld.state.reads
    T.advance(0.1)
    local n = AHWorld.state.reads - before
    T.eq(n, 200, ("rows read until %d ms had gone, a look every %d rows"):format(Scan.config.budgetMs, Scan.config.clockEvery))
    T.eq(Scan.ProgressText(), "Reading 200 / 1,200")
    Scan.Stop()
end)

T.test("blank rows past the first slice are read again once they fill", function()
    local rows = {}
    for i = 1, 1200 do rows[i] = { itemID = SWORD, count = 1, buyout = 5000, blank = true } end
    rows[1200] = { itemID = LIGHT, count = 2, buyout = 70, blank = true }
    setup({ replicate = rows })
    Scan.Start()
    AHWorld.SendList()
    T.advance(1)
    AHWorld.Fill(1199)
    runOut(60)
    T.ok(not Scan.Running(), "done")
    T.eq(Scan.Price(LIGHT), 35, "the last row, filled late, is priced")
end)

T.test("a row whose item isn't cached asks for the item and is read again once it loads", function()
    local rows = market1()
    rows[1] = { itemID = MEDIUM, count = 20, buyout = 2000, uncached = true }   -- 100 each
    setup({ replicate = rows })
    T.reset_calls()
    Scan.Start()
    AHWorld.SendList()
    T.advance(0.1)
    local asked = false
    for _, c in ipairs(T.calls("C_Item.RequestLoadItemDataByID")) do
        if c[1] == MEDIUM then asked = true end
    end
    T.ok(asked, "asked the client to load the item")
    local before = AHWorld.state.reads
    AHWorld.Load(0)
    AHWorld.Fill(8)
    runOut()
    T.ok(AHWorld.state.reads > before, "read again")
    T.eq(Scan.Price(MEDIUM), 100)
end)

T.test("a second full scan within 15 minutes is refused with the time left", function()
    setup({ replicate = market1() })
    T.ok(Scan.Start())
    AHWorld.SendList()
    runOut()
    T.eq(Scan.config.cooldown, 900, "15 minutes")
    T.eq(Scan.CooldownLeft(), Scan.config.cooldown)
    local ok, why = Scan.Start()
    T.ok(not ok, "refused")
    T.eq(why, "A full scan is allowed again in 15 min.")
    T.eq(#AHWorld.state.asks, 1, "nothing asked")
    T.ok(SB.Label():find("15 min", 1, true) ~= nil, "the button shows the minutes left")
    T.ok(not S.IsOn(SB.button), "and is off")
    AHWorld.SetNow(NOW + 6 * 60)
    T.eq(select(2, Scan.Start()), "A full scan is allowed again in 9 min.")
    T.eq(#sent, 0, "no item searches in its place")
    AHWorld.SetNow(NOW + 600)
    T.eq(Scan.CooldownLeft(), 300)
    AHWorld.SetNow(NOW + Scan.config.cooldown)
    T.eq(Scan.CooldownLeft(), 0)
    T.ok(Scan.Start(), "allowed again")
    T.eq(#AHWorld.state.asks, 2)
    Scan.Stop()
end)

T.test("the cooldown is kept per server and faction", function()
    setup({ replicate = market1() })
    T.ok(Scan.Start())
    AHWorld.SendList()
    runOut()
    T.ok(Scan.CooldownLeft() > 0)
    local other = UnitFactionGroup("player") == "Horde" and "Alliance" or "Horde"
    World.set(_G, "UnitFactionGroup", function() return other, other end)
    T.eq(Scan.CooldownLeft(), 0, "the other faction's auction house is free")
end)

T.test("the realm key works when GetRealmName answers nothing, and old prices under its spelling are found", function()
    setup()
    World.set(_G, "UnitFactionGroup", function() return "Horde", "Horde" end)
    World.set(_G, "UnitGUID", function() return "Player-1234-0A1B2C3D" end)
    World.set(_G, "GetNormalizedRealmName", function() return "" end)
    World.set(_G, "GetRealmName", function() return "" end)
    CP.db.prices = { ["Area 52-Horde"] = { [MEDIUM] = { 150, NOW } }, ["Area 52-Alliance"] = { [MEDIUM] = { 99, NOW } },
                     ["Stormscale-Horde"] = { [MEDIUM] = { 77, NOW } } }
    CP.db.priceScans = { ["Area 52-Horde"] = NOW - 3600 }
    T.eq(Scan.RealmKey(), "Server-1234-Horde", "the key needs no realm name")
    T.eq(Scan.Price(MEDIUM), nil, "two old Horde keys and no realm name: the old prices wait")
    T.eq(CP.db.prices["Stormscale-Horde"][MEDIUM][1], 77, "both left alone")

    World.set(_G, "GetRealmName", nil)
    World.set(_G, "GetNormalizedRealmName", function() return "Area52" end)
    T.eq(Scan.RealmKey(), "Server-1234-Horde")
    T.eq(Scan.Price(MEDIUM), 150, "the price saved under the spaced spelling moves to the new key")
    T.eq(Scan.LastTime(), NOW - 3600, "and so does its last scan time")
    T.eq(CP.db.prices["Area 52-Alliance"][MEDIUM][1], 99, "the other faction's prices are left alone")
    T.eq(CP.db.prices["Area 52-Horde"], nil, "the old key is gone")
    T.eq(CP.db.prices["Stormscale-Horde"][MEDIUM][1], 77, "the other realm's prices stay where they were")

    local ok, why = Scan.Start()
    T.ok(ok, "the scan starts: " .. tostring(why))
    Scan.Stop()
end)

T.test("with no realm name, the one old key for the player's faction moves to the server key once", function()
    setup()
    World.set(_G, "UnitFactionGroup", function() return "Horde", "Horde" end)
    World.set(_G, "UnitGUID", function() return "Player-6935-007319DC" end)
    World.set(_G, "GetNormalizedRealmName", function() return "" end)
    World.set(_G, "GetRealmName", function() return "" end)
    World.set(_G, "UnitFullName", function() return "Someone", "" end)
    CP.db.prices = { ["Area 52-Horde"] = { [MEDIUM] = { 150, NOW } }, ["Area 52-Alliance"] = { [MEDIUM] = { 99, NOW } },
                     ["Server-512-Horde"] = { [MEDIUM] = { 55, NOW } } }
    CP.db.priceScans = { ["Area 52-Horde"] = NOW - 3600 }
    CP.db.priceAsked = { ["Area 52-Horde"] = NOW - 3600 }
    T.eq(Scan.RealmKey(), "Server-6935-Horde")
    T.eq(Scan.Price(MEDIUM), 150, "the only old Horde key moved over")
    T.eq(Scan.LastTime(), NOW - 3600, "with its last scan time")
    T.eq(CP.db.priceAsked["Server-6935-Horde"], NOW - 3600, "and its last ask")
    T.eq(CP.db.prices["Area 52-Horde"], nil, "the old key is gone")
    T.eq(CP.db.prices["Area 52-Alliance"][MEDIUM][1], 99, "the other faction's old key stays")
    T.eq(CP.db.prices["Server-512-Horde"][MEDIUM][1], 55, "another server's new-style key isn't an old key")

    -- Once moved, an old key that shows up later is not pulled in.
    CP.db.prices["Stormscale-Horde"] = { [HEAVY] = { 9, NOW } }
    T.eq(Scan.RealmKey(), "Server-6935-Horde")
    T.eq(Scan.Price(HEAVY), nil, "moved once only")
end)

T.test("a zero server id keys prices by faction alone, and prices follow the key both ways", function()
    setup({ replicate = market1() })
    World.set(_G, "UnitFactionGroup", function() return "Horde", "Horde" end)
    World.set(_G, "GetNormalizedRealmName", function() return "" end)
    World.set(_G, "GetRealmName", function() return "" end)
    World.set(_G, "UnitFullName", function() return "Someone", "" end)
    World.set(_G, "UnitGUID", function() return "Player-0-007319DC" end)
    CP.db.prices = { ["Server-6935-Horde"] = { [MEDIUM] = { 150, NOW } }, ["Server-6935-Alliance"] = { [MEDIUM] = { 99, NOW } } }
    CP.db.priceScans = { ["Server-6935-Horde"] = NOW - 3600 }
    T.eq(Scan.RealmKey(), "Forever-Horde", "no server id: the faction's Forever key")
    T.eq(Scan.Price(MEDIUM), 150, "the one server key for the faction moved over")
    T.eq(Scan.LastTime(), NOW - 3600)
    T.eq(CP.db.prices["Server-6935-Alliance"][MEDIUM][1], 99, "the other faction's stays")
    local ok, why = Scan.Start()
    T.ok(ok, "the scan starts: " .. tostring(why))
    Scan.Stop()

    World.set(_G, "UnitGUID", function() return "Player-6935-007319DC" end)
    T.eq(Scan.RealmKey(), "Server-6935-Horde", "the id is back")
    T.eq(Scan.Price(MEDIUM), 150, "the Forever key moved back")
    T.eq(CP.db.prices["Forever-Horde"], nil)

    -- Two server keys for the faction: nothing tells which is this one.
    CP.db.prices["Server-512-Horde"] = { [HEAVY] = { 9, NOW } }
    World.set(_G, "UnitGUID", function() return "Player-0-007319DC" end)
    T.eq(Scan.RealmKey(), "Forever-Horde")
    T.eq(Scan.Price(MEDIUM), nil, "two candidates: both left alone")
    T.eq(CP.db.prices["Server-512-Horde"][HEAVY][1], 9)
    T.eq(CP.db.prices["Server-6935-Horde"][MEDIUM][1], 150)
end)

T.test("an ask that never gets an answer still starts the cooldown", function()
    setup({ replicate = market1() })
    T.ok(Scan.Start())
    T.advance(Scan.config.answerWait + 0.5)
    T.ok(not Scan.Running(), "gave up")
    local prints = T.prints()
    T.ok(prints[#prints]:find("didn't answer", 1, true) ~= nil, prints[#prints])
    T.eq(Scan.CooldownLeft(), Scan.config.cooldown, "the server clock hasn't moved")
    T.eq(Scan.LastTime(), nil, "no finished scan")
end)

T.test("closing the auction house mid-read keeps nothing", function()
    local rows = {}
    for i = 1, 1200 do rows[i] = { itemID = LIGHT, count = 1, buyout = 50 } end
    setup({ replicate = rows })
    Scan.Start()
    AHWorld.SendList()
    T.advance(0.1)
    AHWorld.Close()
    T.ok(not Scan.Running())
    T.eq(Scan.Price(LIGHT), nil, "half a list says nothing about the lowest price")
    T.eq(Scan.LastTime(), nil)
end)

T.test("an empty list ends the scan with a line about the cooldown", function()
    setup({ replicate = {} })
    Scan.Start()
    AHWorld.SendList()
    runOut()
    local prints = T.prints()
    T.ok(prints[#prints]:find("sent no auctions", 1, true) ~= nil, prints[#prints])
end)

-- Pricing --------------------------------------------------------------------------------------

T.test("a scan that stores prices re-ranks plans", function()
    setup({ replicate = market1() })
    local invalidate, calls = CP.Plan.Invalidate, 0
    CP.Plan.Invalidate = function() calls = calls + 1 end
    Scan.Start()
    AHWorld.SendList()
    runOut()
    CP.Plan.Invalidate = invalidate
    T.eq(calls, 1)
end)

T.test("pricing order: vendor stock, then DaylightMogul, then our scan, then list price", function()
    setup({ replicate = market1() })
    T.eq(select(2, CP.Pricing.Get(LIGHT, { 60, false })), "estimate", "no auction data yet")
    T.eq(CP.Pricing.HasAuctionData(), false)
    Scan.Start()
    AHWorld.SendList()
    AHWorld.Fill(8)
    runOut()
    T.eq(CP.Pricing.HasAuctionData(), true, "our own scan counts")
    local price, source = CP.Pricing.Get(LIGHT, { 60, false })
    T.eq(price, 40)
    T.eq(source, "auction")
    AHWorld.SetNow(NOW + 7200)
    T.eq(CP.Pricing.AuctionAge(LIGHT), 7200)
    T.eq(CP.Pricing.FormatAge(7200), "2 h")
    T.eq(select(2, CP.Pricing.Get(LIGHT, { 10, true })), "vendor", "a vendor good is priced at the vendor")
    T.eq(CP.Pricing.Get(THREAD, { 10, true }), 10, "vendor stock listed for less at auction: still the vendor price")
    T.eq(select(2, CP.Pricing.Get(THREAD, { 10, true })), "vendor")
    T.eq(select(2, CP.Pricing.Get(THREAD, { 1, true })), "vendor", "a vendor at the same price wins")

    MogulWorld.begin({ prices = { [LIGHT] = 45 } })
    T.eq(CP.Pricing.Get(LIGHT, { 60, false }), 45, "Mogul's price comes first, even above ours")
    T.eq(CP.Pricing.AuctionAge(LIGHT), nil, "Mogul's price has no scan age")
    T.eq(CP.Pricing.Get(MEDIUM, { 300, false }), 150, "ours fill what Mogul has no price for")
    MogulWorld.SetPrice(LIGHT, nil)
    T.eq(CP.Pricing.Get(LIGHT, { 60, false }), 40, "Mogul without a price: our scan")
end)

-- The ProfLost Scan button -----------------------------------------------------------------------

T.test("ProfLost Scan sits on the auction house window in the plugin's gradient, fades in, and pulses until clicked", function()
    setup({ replicate = market1(), open = false })
    local b = button()
    local alpha = alphaOf(b)
    AHWorld.Open()
    T.ok(b:IsShown(), "shown with the auction house")
    T.eq(b:GetParent(), AHWorld.window, "a child of the auction house window, so clicks land")
    T.eq({ b:GetPoint(1) }, { "TOPRIGHT", AHWorld.window, "BOTTOMRIGHT", 0, -SB.GAP }, "under its bottom right corner")
    T.eq(b.label:GetText(), CP.Gradient("Scan prices"), "the plugin's gradient")
    T.eq(alpha(), 0, "starts clear")
    T.advance(0.3)
    T.eq(alpha(), 1, "faded in")
    T.ok(S.Pulsing(b), "pulsing")
    T.advance(S.PULSE + 0.5)
    T.ok(alpha() < 1, "dips")
    T.advance(S.PULSE)
    T.ok(alpha() > S.PULSE_LOW, "and comes back")

    b:GetScript("OnClick")(b)
    T.ok(not S.Pulsing(b), "a click stops the pulse")
    T.ok(Scan.Running(), "and starts the scan")
    T.eq(b.label:GetText(), "Asking the auction house")
    AHWorld.SendList()
    T.advance(0.1)
    T.eq(b.label:GetText(), "Reading 9 / 9", "the progress on the button")
    T.eq(CP.ShopTab.ui.scan, nil, "no Scan button in the Shop tab")
    runOut()
    T.ok(b.label:GetText():find("15 min", 1, true) ~= nil, "then the cooldown")
    T.ok(not S.Pulsing(b))

    -- Back within the cooldown: no pulse.
    AHWorld.Close()
    T.ok(not b:IsShown(), "gone with the auction house")
    AHWorld.Open()
    T.ok(b:IsShown())
    T.ok(not S.Pulsing(b), "a scan within the cooldown: no pulse")
end)

T.test("with Daylight UI the button fades with its API.Fade", function()
    setup({ open = false })
    local b = button()
    DaylightWorld.begin()
    AHWorld.Open()
    local fades = DaylightWorld.state.alphaFades
    T.ok(#fades >= 1, "API.Fade called")
    T.eq(fades[1].region, b)
    T.eq(fades[1].alpha, 1)
    T.eq(fades[1].speed, "NORMAL")
    T.advance(S.PULSE + 0.05)
    -- The button's own last fade: other frames fade through the same call.
    local last
    for _, f in ipairs(fades) do if f.region == b then last = f end end
    T.eq(last.alpha, S.PULSE_LOW, "the pulse is API.Fade too")

    -- Daylight UI's motion switched off: its fades jump, so no pulse.
    AHWorld.Close()
    World.set(DaylightWorld.state.addon, "Motion", { On = function() return false end, Tween = function() end })
    AHWorld.Open()
    T.ok(b:IsShown())
    T.ok(not S.Pulsing(b), "motion off: no pulse")
end)

T.test("DaylightMogul's window takes the button while it stands in; a parked game window doesn't", function()
    setup({ open = false })
    local b = button()
    local before = rawget(_G, "DaylightMogulMain")
    local mogul = CreateFrame("Frame", "DaylightMogulMain", UIParent)
    rawset(_G, "DaylightMogulMain", before)
    World.set(_G, "DaylightMogulMain", mogul)
    World.set(mogul, "GetEffectiveAlpha", function() return 1 end)
    mogul:Show()
    AHWorld.Park(true)
    AHWorld.Open()
    T.eq(b:GetParent(), mogul, "on Mogul's window")
    T.ok(b:IsShown())
    mogul:Hide()
    T.advance(SB.CHECK_EVERY + 0.05)
    T.ok(not b:IsShown(), "no visible auction house window: no button")
    AHWorld.Park(false)
    T.advance(SB.CHECK_EVERY + 0.05)
    T.eq(b:GetParent(), AHWorld.window, "the game's window once it is back in sight")
    T.ok(b:IsShown())
end)

T.test("the Shop tab's status line follows the scan and says where to scan", function()
    setup({ replicate = market1() })
    local ui = CP.ShopTab.ui
    World.set(CP.db, "collect", false)
    CP.ShopTab.Changed()
    T.eq(ui.scanText:GetText(), "No price scan yet")
    Scan.Start()
    T.eq(ui.scanText:GetText(), "Asking the auction house")
    AHWorld.SendList()
    runOut()
    T.eq(ui.scanText:GetText(), "Last scan 1 min ago")
    AHWorld.Close()
    T.eq(ui.scanText:GetText(), "Last scan 1 min ago  ·  " .. CP.ShopTab.SCAN_HINT)
end)

T.test("/proflost trace scan prints the phases, counts and timings", function()
    setup({ replicate = market1() })
    SlashCmdList.PROFLOST("trace scan on")
    T.eq(CP.trace.scan, true)
    local from = #T.prints()
    Scan.Start()
    AHWorld.SendList()
    AHWorld.Fill(8)
    runOut()
    local out = {}
    for i = from + 1, #T.prints() do out[#out + 1] = T.prints()[i] end
    local text = table.concat(out, "\n")
    for _, want in ipairs({ "start: full scan", "asked for the full list", "list arrived: 9 rows",
                            "read 9 rows in 1 frames", "stored 6 prices", "finish: done, 6 priced" }) do
        T.ok(text:find(want, 1, true) ~= nil, "trace says: " .. want)
    end
    SlashCmdList.PROFLOST("trace scan off")
    T.eq(CP.trace.scan, nil)
end)
