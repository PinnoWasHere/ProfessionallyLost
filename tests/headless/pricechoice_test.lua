-- The player picks one auction price addon (Pricing.Choose, saved in CP.db.priceSource) from one
-- Price Addon dropdown: Automatic, Professionally Lost's Own, then each installed addon; the pick's prices are read first and the
-- rest fill gaps in Pricing.config.order; the Scan button acts for the pick; and the question
-- box asks once while no pick is saved (UI/PriceAsk.lua). TSM and Auctioneer are mocks
-- (tsmworld, auctioneerworld) built from documentation, not from their code.

local CP = ProfLost
local Pricing, Scan, SB, S = CP.Pricing, CP.Scan, CP.ScanButton, CP.Style
local LIGHT, MEDIUM, HEAVY, THREAD = 2318, 2319, 4234, 2320
local NOW = 1800000000

-- A test's own pick: saved for the test only, and the options page's redraws counted.
local function picks(key)
    World.set(CP.db, "priceSource", key)
    local redraws = 0
    World.set(CP.Plugin, "RefreshOptions", function() redraws = redraws + 1 end)
    return function() return redraws end
end

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

-- The Prices group's dropdown as Daylight UI's options page gets it.
local function priceRow()
    for _, g in ipairs(CP.Plugin.Pages()[1].groups) do
        if g.label == "Prices" then
            for _, item in ipairs(g.items) do
                if item.type == "dropdown" then return item end
            end
        end
    end
end

-- The dropdown's choices in order: their keys and their words.
local function listed(row)
    local values, order = row.choices()
    local words = {}
    for i, k in ipairs(order) do words[i] = values[k] end
    return order, words
end

-- The game lists these addon folders as present and switched on.
local function installed(set)
    World.set(C_AddOns, "DoesAddOnExist", function(name) return set[name] == true end)
    World.set(C_AddOns, "GetAddOnEnableState", function(name) return set[name] and 2 or 0 end)
end

-- The options dropdown ------------------------------------------------------------------------

T.test("one Price Addon dropdown lists Automatic, Professionally Lost's Own, then each installed addon", function()
    picks(nil)
    scanned({})
    AuctionatorWorld.begin({ prices = { [LIGHT] = 30 } })
    installed({ TradeSkillMaster = true })
    local row = priceRow()
    T.ok(row ~= nil, "the Prices group has a dropdown")
    T.eq(row.label, "Price Addon")
    T.eq(row.key, nil, "kept in CP.db.priceSource through its own get and set")
    local order, words = listed(row)
    T.eq(order, { "automatic", "scan", "tsm", "auctionator" })
    T.eq(words, { "Automatic", "Professionally Lost's Own", "TSM", "Auctionator" })
    T.eq(row.get(), "automatic", "nothing saved reads Automatic")
    T.eq(row.default(), "automatic", "its reset goes back to Automatic")
end)

T.test("Professionally Lost's Own is listed with no other addon installed and with every one loaded", function()
    picks(nil)
    scanned({})
    installed({})
    T.eq((listed(priceRow())), { "automatic", "scan" })
    AuctionatorWorld.begin({})
    TSMWorld.begin({})
    AuctioneerWorld.begin({})
    MogulWorld.begin({})
    GloweyWorld.begin({})
    T.eq((listed(priceRow())), { "automatic", "scan", "tsm", "auctioneer", "auctionator", "daylight", "glowey" })
end)

T.test("picking Professionally Lost's Own over a loaded addon saves it and the Scan button runs ProfLost's scan", function()
    local redraws = picks("glowey")
    scanned({ [LIGHT] = { 10, NOW } })
    GloweyWorld.begin({ prices = { [LIGHT] = 70 }, has = true })
    local row = priceRow()
    T.eq(row.get(), "glowey")
    T.eq(SB.Mode(), "how", "Glowey's Recipes picked: the button says how to scan there")
    T.ok(row.set("scan") ~= false, "the pick is taken")
    T.eq(CP.db.priceSource, "scan")
    T.eq(row.get(), "scan")
    T.ok(redraws() >= 1, "the page redraws so the note follows")
    T.eq(Pricing.Active(), "scan")
    T.eq(select(2, Pricing.AuctionFrom(LIGHT)), "scan", "ProfLost's scan is read first")
    T.eq(SB.Mode(), "own", "the Scan button runs ProfLost's scan")
    T.eq(row.set("nothing"), false, "an unknown key is refused")
    T.eq(CP.db.priceSource, "scan")
end)

T.test("Automatic is saved, never asks again, and follows the order", function()
    picks(nil)
    scanned({ [THREAD] = { 13, NOW } })
    AuctionatorWorld.begin({ prices = { [LIGHT] = 30, [2589] = 20 } })
    TSMWorld.begin({ market = { [LIGHT] = 20 } })
    local row = priceRow()
    row.set("tsm")
    T.ok(row.set("automatic") ~= false)
    T.eq(CP.db.priceSource, "automatic", "Automatic is a saved answer")
    T.eq(row.get(), "automatic")
    T.eq(Pricing.Active(), nil, "no pick is read first")
    T.eq(Pricing.FellBack(), nil)
    T.eq(select(2, Pricing.AuctionFrom(LIGHT)), "auctionator", "the order decides: Auctionator ahead of TSM")
    T.eq(select(2, Pricing.AuctionFrom(THREAD)), "scan")
    T.eq(CP.PriceAsk.Due(), false, "the one-time question is answered")
    T.ok(Pricing.ChoiceNote():find("Automatic", 1, true) ~= nil, Pricing.ChoiceNote())
    T.ok(Pricing.ChoiceNote():find("Auctionator", 1, true) ~= nil, Pricing.ChoiceNote())
end)

T.test("a pick saved before the dropdown carries over unchanged", function()
    picks("auctioneer")
    scanned({})
    installed({})
    local row = priceRow()
    T.eq(row.get(), "auctioneer", "the saved pick shows")
    T.eq(CP.db.priceSource, "auctioneer", "nothing is rewritten")
    local order, words = listed(row)
    T.eq(order, { "automatic", "scan", "auctioneer" }, "a saved pick whose addon is gone stays listed")
    T.eq(words[3], "Auctioneer (not installed)")
    T.eq(Pricing.FellBack(), "Auctioneer")
    World.set(CP.db, "priceSource", "nonsense")
    T.eq(row.get(), "automatic", "an unknown saved value reads Automatic")
end)

-- The order ---------------------------------------------------------------------------------

T.test("the pick is read first and the others fill gaps in today's order", function()
    picks("tsm")
    scanned({ [LIGHT] = { 10, NOW }, [THREAD] = { 13, NOW } })
    AuctionatorWorld.begin({ prices = { [LIGHT] = 30, [MEDIUM] = 31 } })
    TSMWorld.begin({ market = { [LIGHT] = 20 }, minBuyout = { [HEAVY] = 22 } })
    T.eq({ Pricing.AuctionFrom(LIGHT) }, { 20, "tsm" }, "TSM first, ahead of Auctionator")
    T.eq({ Pricing.AuctionFrom(HEAVY) }, { 22, "tsm" }, "its lowest buyout when it has no market value")
    T.eq(select(2, Pricing.AuctionFrom(MEDIUM)), "auctionator", "Auctionator fills what TSM lacks")
    T.eq(select(2, Pricing.AuctionFrom(THREAD)), "scan", "then ProfLost's scan")

    Pricing.Choose("scan")
    T.eq(select(2, Pricing.AuctionFrom(LIGHT)), "scan", "ProfLost's scan picked: ahead of every addon")
    T.eq(select(2, Pricing.AuctionFrom(MEDIUM)), "auctionator", "the addons fill in today's order")
    T.eq(select(2, Pricing.AuctionFrom(HEAVY)), "tsm")

    MogulWorld.begin({ prices = { [MEDIUM] = 50 } })
    Pricing.Choose("auctionator")
    T.eq(select(2, Pricing.AuctionFrom(MEDIUM)), "auctionator", "Auctionator picked: ahead of DaylightMogul")
    Pricing.Choose("daylight")
    T.eq(select(2, Pricing.AuctionFrom(MEDIUM)), "mogul", "Daylight UI picked reads DaylightMogul")
end)

T.test("nothing saved keeps today's order", function()
    picks(nil)
    scanned({ [THREAD] = { 13, NOW } })
    AuctionatorWorld.begin({ prices = { [LIGHT] = 30 } })
    TSMWorld.begin({ market = { [LIGHT] = 20 } })
    T.eq(select(2, Pricing.AuctionFrom(LIGHT)), "auctionator", "Auctionator ahead of TSM")
    T.eq(Pricing.config.order, { "mogul", "daylight", "auctionator", "tsm", "auctioneer", "scan", "glowey" })
    T.eq(Pricing.Best(), "auctionator")
end)

T.test("a pick whose addon isn't loaded falls back to the order, and the Shop line says so", function()
    picks("tsm")
    scanned({})
    AuctionatorWorld.begin({ prices = { [LIGHT] = 30, [2589] = 20 } })
    T.eq(select(2, Pricing.AuctionFrom(LIGHT)), "auctionator")
    T.eq(Pricing.FellBack(), "TSM")
    T.ok(Pricing.ChoiceNote():find("TSM isn't loaded, so prices come from Auctionator first.", 1, true) ~= nil,
        Pricing.ChoiceNote())
    World.set(CP.db, "collect", false)
    CP.ShopTab.Changed()
    T.eq(CP.ShopTab.ui.scanText:GetText(), "TSM isn't loaded  ·  Prices from Auctionator")
end)

T.test("TSM is asked through GetCustomPriceValue with its item string, and errors read as no price", function()
    picks("tsm")
    scanned({})
    TSMWorld.begin({ market = { [LIGHT] = 20 } })
    T.eq(Pricing.Auction(LIGHT), 20)
    T.eq(TSMWorld.state.asked[1], { "DBMarket", "i:" .. LIGHT })
    World.set(TSM_API, "GetCustomPriceValue", function() error("boom") end)
    T.eq(Pricing.Auction(LIGHT), nil, "an error reads as no price")
end)

T.test("Auctioneer is asked for its market value by item link, and errors read as no price", function()
    picks("auctioneer")
    scanned({})
    AuctioneerWorld.begin({ prices = { [LIGHT] = 25 } })
    T.eq({ Pricing.AuctionFrom(LIGHT) }, { 25, "auctioneer" }, "its count of sightings is no age")
    T.eq(AuctioneerWorld.state.asked[1], "item:" .. LIGHT)
    World.set(AucAdvanced.API, "GetMarketValue", function() error("boom") end)
    T.eq(Pricing.Auction(LIGHT), nil)
end)

T.test("Auctioneer's prices count as new when the auction house closes", function()
    picks("auctioneer")
    scanned({})
    AuctioneerWorld.begin({})
    local n = 0
    World.set(CP.Plan, "Invalidate", function() n = n + 1 end)
    T.fire("AUCTION_HOUSE_CLOSED")
    T.eq(n, 1)
end)

T.test("TSM's prices, loaded in its own login handler, count as new once login ends", function()
    picks("tsm")
    scanned({})
    TSMWorld.begin({ market = { [LIGHT] = 20 }, login = false })
    local n = 0
    World.set(CP.Plan, "Invalidate", function() n = n + 1 end)
    Pricing.Listen()
    T.eq(Pricing.Auction(LIGHT), nil, "no data before TSM's login handler")
    TSMWorld.Login()
    T.eq(n, 0, "nothing yet: login is still going on")
    T.advance(0.1)
    T.eq(n, 1, "prices count as new once")
    T.eq(Pricing.Auction(LIGHT), 20)
end)

T.test("Auctioneer's prices count as new when it turns active and when a scan's prices are stored", function()
    picks("auctioneer")
    scanned({})
    AuctioneerWorld.begin({ prices = { [LIGHT] = 25 }, active = false })
    local n = 0
    World.set(CP.Plan, "Invalidate", function() n = n + 1 end)
    Pricing.Listen()
    T.eq(Pricing.Auction(LIGHT), nil, "no server key before it is active")
    AuctioneerWorld.Message("gameactive")
    T.eq(n, 1, "active: its prices are readable")
    T.eq(Pricing.Auction(LIGHT), 25)
    AuctioneerWorld.Message("scanprogress")
    T.eq(n, 1, "progress is not new prices")
    AuctioneerWorld.Message("scanstats")
    T.eq(n, 2, "a stored scan is")
    T.eq(AuctioneerWorld.state.messages, { "gameactive", "scanprogress", "scanstats" }, "its modules still hear every message")
    Pricing.Listen()
    AuctioneerWorld.Message("scanstats")
    T.eq(n, 3, "listening again hooks once")
end)

-- The Scan button -------------------------------------------------------------------------------

local function ahOpen()
    Scan.Stop()
    local panelShown = CP.Panel.frame:IsShown()
    CP.Panel.frame:Hide()
    World.onEnd(function()
        Scan.Stop()
        if panelShown then CP.Panel.frame:Show() end
    end)
    T.advance(1)
    AHWorld.begin({ listings = {}, now = NOW })
    World.set(Scan, "CooldownLeft", function() return 0 end)
end

T.test("the Scan button runs ProfLost's scan only when ProfLost is the pick", function()
    picks("scan")
    ahOpen()
    scanned({})
    AuctionatorWorld.begin({ prices = { [2589] = 20 } })
    AHWorld.Open()
    local b = SB.button
    T.ok(b:IsShown())
    T.eq(SB.Mode(), "own")
    T.ok(S.Pulsing(b), "ProfLost picked: it pulses, even with Auctionator's prices")

    Pricing.Choose("auctionator")
    SB.Update()
    T.eq(SB.Mode(), "how")
    T.eq(b.label:GetText(), SB.HOW.auctionator, "says how to scan in Auctionator")
    T.ok(not S.Pulsing(b), "no pulse")
    local started = 0
    World.set(Scan, "Start", function() started = started + 1 return true end)
    SB.Click()
    T.eq(started, 0, "never starts ProfLost's own scan")
end)

T.test("with DaylightMogul picked the button starts Mogul's scan through /mogul scan", function()
    picks("daylight")
    ahOpen()
    scanned({})
    MogulWorld.begin({})
    local asked = {}
    World.set(SlashCmdList, "DAYLIGHTMOGUL", function(msg) asked[#asked + 1] = msg end)
    AHWorld.Open()
    T.eq(SB.Mode(), "mogul")
    local plain = SB.button.label:GetText():gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    T.eq(plain, "Scan with DaylightMogul", "the gradient name")
    SB.Click()
    T.eq(asked, { "scan" })
    World.set(SlashCmdList, "DAYLIGHTMOGUL", nil)
    T.eq(SB.Mode(), "how", "without its command: how to scan")
end)

-- The one-time question -------------------------------------------------------------------------

-- Daylight UI's box and chips, recording each question.
local function box()
    local asked = {}
    local W = { Win = nil }
    W.Ask = function(spec) asked[#asked + 1] = spec end
    W.Chip = function(parent, text)
        local b = CreateFrame("Button", nil, parent)
        b:SetSize(60, 24)
        b.text = b:CreateFontString(nil, "OVERLAY")
        b.text:SetText(text or "")
        function b.SetOn(on) b.on = on and true or nil end
        function b.FitWidth() end
        return b
    end
    World.set(_G, "DaylightUI", { Widgets = W })
    CP.PriceAsk.Reset()
    World.onEnd(CP.PriceAsk.Reset)
    return asked
end

-- The question's chips once its box shows: their words, the lit one's, and the chips.
local function lit(spec)
    local holder = CreateFrame("Frame", nil, UIParent)
    spec.preview.show(holder)
    World.onEnd(function() spec.preview.hide(holder) end)
    local out, on, shown = {}, nil, {}
    for _, b in ipairs(CP.PriceAsk.Chips()) do
        if b:IsShown() then
            shown[#shown + 1] = b
            out[#out + 1] = b.text:GetText()
            if b.on then on = b.text:GetText() end
        end
    end
    return out, on, shown
end

T.test("with no pick saved, one question lists the loaded addons and ProfLost, the best lit, and saves the answer", function()
    picks(nil)
    scanned({})
    local asked = box()
    World.patch("InCombatLockdown", function() return false end)
    AuctionatorWorld.begin({})
    MogulWorld.begin({})
    T.ok(CP.PriceAsk.Run(), "asked")
    T.eq(#asked, 1)
    local spec = asked[1]
    T.eq(spec.title, "Auction prices")
    T.eq(spec.no, false, "one button")
    local labels, on, chips = lit(spec)
    T.eq(labels, { "Auctionator", "Daylight UI", "Professionally Lost's Own" }, "loaded addons and ProfLost, in the options' order")
    T.eq(on, "Daylight UI", "the best by today's order")
    chips[1]:GetScript("OnClick")(chips[1])
    T.eq(select(2, lit(spec)), "Auctionator", "a click lights another")
    spec.onYes()
    T.eq(CP.db.priceSource, "auctionator", "the answer is saved")
    T.eq(CP.PriceAsk.Run(), false, "never asked again")
    T.eq(#asked, 1)
end)

T.test("closing the question keeps the lit pick, and a fight holds the question until it ends", function()
    picks(nil)
    scanned({})
    local asked = box()
    local fighting = true
    World.patch("InCombatLockdown", function() return fighting end)
    AuctionatorWorld.begin({})
    T.eq(CP.PriceAsk.Run(), false, "not in a fight")
    T.eq(#asked, 0)
    fighting = false
    T.fire("PLAYER_REGEN_ENABLED")
    T.eq(#asked, 1, "asked once the fight ended")
    asked[1].onClose()
    T.eq(CP.db.priceSource, "auctionator", "Escape keeps the lit one")
end)

T.test("with only ProfLost's scan to pick, or no question box, nothing is asked or saved", function()
    picks(nil)
    scanned({})
    local asked = box()
    World.patch("InCombatLockdown", function() return false end)
    T.eq(CP.PriceAsk.Run(), false)
    T.eq(#asked, 0)
    T.eq(CP.db.priceSource, nil, "the order decides until there is a choice")
    AuctionatorWorld.begin({})
    World.set(_G, "DaylightUI", nil)
    T.eq(CP.PriceAsk.Run(), false, "no box")
    T.eq(CP.db.priceSource, nil)
end)

T.test("the button's tooltip for another addon names it and says how to change the pick", function()
    picks("auctionator")
    ahOpen()
    scanned({})
    AuctionatorWorld.begin({})
    AHWorld.Open()
    local lines = {}
    World.set(GameTooltip, "SetText", function(_, text) lines[#lines + 1] = tostring(text) end)
    World.set(GameTooltip, "AddLine", function(_, text) lines[#lines + 1] = tostring(text) end)
    SB.button:GetScript("OnEnter")(SB.button)
    local said = table.concat(lines, "\n")
    T.ok(said:find("Scan with Auctionator", 1, true) ~= nil, said)
    T.ok(said:find(SB.HOW.auctionator, 1, true) ~= nil, said)
    T.ok(said:find("under Prices", 1, true) ~= nil, said)
end)
