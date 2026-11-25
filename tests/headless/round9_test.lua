-- The guide window after the owner's round-9 feedback: the
-- look watch and the overlap scan, the profession window following the guide when the
-- player opens it, the vendor Buy trace and its stepped purchases, and All mode's making
-- strip.

local CP = ProfLost
local W, P, GP, B, Look = CP.Window, CP.Panel, CP.GatherPanel, CP.Buying, CP.Look
local LW, TAILOR = 165, 197
local DUROTAR = 1411
local FINE_THREAD = 2321
local S = CP.Style

-- Leatherworking and Tailoring, each window opened once so its recipes are saved, then
-- shut long enough that the next open counts as the player's own. One mode on `prof`.
local function shut(prof)
    MapWorld.begin({ zone = DUROTAR, level = 20, side = "Horde" })
    CraftWorld.begin({ professions = { [LW] = 100, [TAILOR] = 60 } })
    World.set(CP.db, "hideInCombat", false)
    World.set(CP.db, "windowClosed", nil)
    World.onEnd(function()
        W.CancelPick()
        W.opened = false
        W.Update()
    end)
    CraftWorld.Open(LW)
    CraftWorld.Close()
    CraftWorld.Open(TAILOR)
    CraftWorld.Close()
    World.set(CP.charDB, "guideMode", "one")
    W.Pick(prof)
    P.tabs.guide.button:GetScript("OnClick")()
    T.advance(1)
    return CP.GuideTab.ui
end

local function click(b) b:GetScript("OnClick")(b) end

local function printedSince(from)
    return table.concat(T.prints(), "\n", from + 1)
end

-- 1. The look watch and the overlap scan --------------------------------------------------

T.test("the look watch prints each change of the window's look and who made it", function()
    shut(LW)
    local level = 5
    World.set(P.frame, "GetFrameLevel", function() return level end)
    World.onEnd(function() Look.SetWatch(false, true) end)
    SlashCmdList.PROFLOST("watch look on")
    T.eq(CP.trace.look, true, "on")
    T.ok(Look.watch.ticker ~= nil, "watching")

    local from = #T.prints()
    level = 2
    T.advance(Look.WATCH_EVERY * 2)
    local text = printedSince(from)
    T.ok(text:find("window: ", 1, true) ~= nil, "the window's line changed")
    T.ok(text:find("MEDIUM/5", 1, true) ~= nil or text:find("/5 ", 1, true) ~= nil, "from its old level")
    T.ok(text:find("/2 ", 1, true) ~= nil, "to its new one")

    from = #T.prints()
    P.frame:SetAlpha(0.5)
    text = printedSince(from)
    T.ok(text:find("window:SetAlpha(0.50) from", 1, true) ~= nil, "a hooked call names its caller")

    from = #T.prints()
    T.fire("TRADE_SKILL_SHOW")
    T.ok(printedSince(from):find("event TRADE_SKILL_SHOW", 1, true) ~= nil, "profession events too")
    T.fire("TRADE_SKILL_CLOSE")

    SlashCmdList.PROFLOST("watch look off")
    T.eq(CP.trace.look, nil)
    from = #T.prints()
    level = 7
    P.frame:SetAlpha(1)
    T.advance(Look.WATCH_EVERY * 2)
    T.eq(printedSince(from):find("ProfLost look", 1, true), nil, "nothing while off")
end)

T.test("the snapshot reads every frame under the window and its shells' textures", function()
    shut(LW)
    World.set(P.frame, "GetChildren", function() return P.body, GP.shell, GP.clip end)
    World.set(GP.clip, "GetChildren", function() return GP.sheet end)
    local snap = Look.Snapshot()
    T.ok(snap.window ~= nil, "the window")
    local frames = 0
    for k in pairs(snap) do if k:find("^window/") then frames = frames + 1 end end
    T.eq(frames, 4, "the frames under it, children of children too")
    T.ok(snap["window/3/1"] ~= nil, "the gathering sheet under its clip")
    local changes = Look.Changes({ a = "1", b = "2" }, { a = "1", b = "3", c = "4" })
    T.eq(table.concat(changes, "|"), "b: 2 -> 3|c: nil -> 4")
end)

-- A frame for the overlap scan: `spec` gives strata, level, rect (l, b, w, h), parent,
-- alpha, name and textures ({ r, g, b, a }).
local function fake(spec)
    local textures = {}
    for _, c in ipairs(spec.textures or {}) do
        textures[#textures + 1] = {
            GetObjectType = function() return "Texture" end,
            IsShown = function() return true end,
            GetAlpha = function() return 1 end,
            GetVertexColor = function() return c[1], c[2], c[3], c[4] end,
            GetTexture = function() return "Interface\\Buttons\\WHITE8X8" end,
        }
    end
    local r = spec.rect
    return {
        IsVisible = function() return spec.shown ~= false end,
        GetEffectiveAlpha = function() return spec.alpha or 1 end,
        GetAlpha = function() return spec.alpha or 1 end,
        GetFrameStrata = function() return spec.strata or "MEDIUM" end,
        GetFrameLevel = function() return spec.level or 1 end,
        GetRect = function() return r[1], r[2], r[3], r[4] end,
        GetEffectiveScale = function() return 1 end,
        GetParent = function() return spec.parent or UIParent end,
        GetDebugName = function() return spec.name end,
        GetRegions = function() return unpack(textures) end,
        GetChildren = function() end,
    }
end

T.test("the overlap scan lists what draws over the window, largest first", function()
    shut(LW)
    World.set(P.frame, "GetRect", function() return 100, 100, 310, 400 end)
    World.set(P.frame, "GetEffectiveScale", function() return 1 end)
    World.set(P.frame, "GetFrameStrata", function() return "MEDIUM" end)
    World.set(P.frame, "GetFrameLevel", function() return 5 end)
    World.set(P.frame, "IsVisible", function() return true end)
    World.set(P.body, "GetFrameLevel", function() return 6 end)
    World.set(GP.shell, "GetRect", function() return nil end)
    local frames = {
        fake({ name = "Veil", strata = "MEDIUM", level = 30, rect = { 120, 120, 100, 100 }, textures = { { 0, 0, 0, 0.6 } } }),
        fake({ name = "BigDark", strata = "HIGH", level = 1, rect = { 0, 0, 2000, 2000 }, textures = { { 0, 0, 0, 0.5 } } }),
        fake({ name = "Below", strata = "MEDIUM", level = 2, rect = { 100, 100, 310, 400 } }),
        fake({ name = "Elsewhere", strata = "HIGH", level = 9, rect = { 900, 900, 50, 50 } }),
        fake({ name = "Clear", strata = "HIGH", level = 9, rect = { 100, 100, 50, 50 }, alpha = 0 }),
        fake({ name = "OwnBack", parent = P.frame, level = 9, rect = { 100, 100, 300, 300 }, textures = { { 0.1, 0.1, 0.1, 0.9 } } }),
        fake({ name = "OwnUnder", parent = P.frame, level = 4, rect = { 100, 100, 310, 400 }, textures = { { 0.1, 0.1, 0.1, 0.9 } } }),
    }
    local over = Look.Over(frames)
    local names = {}
    for _, o in ipairs(over) do names[#names + 1] = o.frame.GetDebugName() end
    T.eq(table.concat(names, " "), "BigDark OwnBack Veil",
        "higher strata, or same strata and level, by overlap; our own only above the content")
    local lines = Look.OverLines(frames)
    T.eq(lines[1], "drawn over the window: 3 frames")
    T.ok(lines[2]:find("BigDark [UIParent] HIGH/1", 1, true) ~= nil, lines[2])
    T.ok(lines[2]:find("rgba 0.00,0.00,0.00,0.50", 1, true) ~= nil, "with its texture's colour")
    T.ok(lines[3]:find("(ours) OwnBack", 1, true) ~= nil, lines[3])

    local many = {}
    for i = 1, Look.OVER_LINES + 5 do many[i] = fake({ name = "F" .. i, strata = "HIGH", rect = { 100, 100, 10 + i, 10 } }) end
    lines = Look.OverLines(many)
    T.eq(#lines, Look.OVER_LINES + 2, "capped, with a count of the rest")
    T.ok(lines[2]:find("F" .. (Look.OVER_LINES + 5), 1, true) ~= nil, "largest first")
end)

T.test("the overlap scan and the dump skip frames that answer with secrets, and count them", function()
    shut(LW)
    local saved = issecretvalue
    issecretvalue = function(v) return v == "SECRET" end
    World.onEnd(function() issecretvalue = saved end)
    World.set(P.frame, "GetRect", function() return 100, 100, 310, 400 end)
    World.set(P.frame, "GetEffectiveScale", function() return 1 end)
    World.set(P.frame, "GetFrameStrata", function() return "MEDIUM" end)
    World.set(P.frame, "GetFrameLevel", function() return 5 end)
    World.set(P.frame, "IsVisible", function() return true end)
    World.set(P.body, "GetFrameLevel", function() return 6 end)
    World.set(GP.shell, "GetRect", function() return nil end)
    local good = fake({ name = "Good", strata = "HIGH", level = 1, rect = { 100, 100, 50, 50 } })
    local width = fake({ name = "SecretWidth", strata = "HIGH", level = 1, rect = { 100, 100, 50, 50 } })
    width.GetRect = function() return 100, 100, "SECRET", 50 end
    local alpha = fake({ name = "SecretAlpha", strata = "HIGH", level = 1, rect = { 100, 100, 50, 50 } })
    alpha.GetEffectiveAlpha = function() return "SECRET" end
    local level = fake({ name = "SecretLevel", strata = "HIGH", level = 1, rect = { 100, 100, 50, 50 } })
    level.GetFrameLevel = function() return "SECRET" end
    local erring = fake({ name = "Erring", strata = "HIGH", level = 1, rect = { 100, 100, 50, 50 } })
    erring.GetRect = function() error("secret rect") end
    local frames = { good, width, alpha, level, erring }
    local lines = Look.OverLines(frames)
    T.eq(lines[1], "drawn over the window: 2 frames", "the readable frames only (Good, and Erring's pcall'd read gives none)")
    T.ok(lines[#lines]:find("skipped 3 frames", 1, true) ~= nil, tostring(lines[#lines]))

    World.set(P.frame, "GetAlpha", function() return "SECRET" end)
    World.set(P.frame, "GetScale", function() return "SECRET" end)
    local from = #T.prints()
    World.set(_G, "EnumerateFrames", function() return nil end)
    SlashCmdList.PROFLOST("dump look")
    T.ok(printedSince(from):find("window: ", 1, true) ~= nil, "the dump still prints")
    Look.Snapshot()
end)

T.test("dump look ends with the overlap scan", function()
    shut(LW)
    World.set(_G, "EnumerateFrames", function() return nil end)
    local from = #T.prints()
    SlashCmdList.PROFLOST("dump look")
    T.ok(printedSince(from):find("drawn over the window", 1, true) ~= nil)
end)

-- 3. The guide follows the open profession window (round 11: the guide changes, never the window)

T.test("the player opening another profession moves the guide to it; no switch outside a click", function()
    shut(LW)
    local asked = #CraftWorld.Asked()
    CraftWorld.Open(TAILOR)
    T.advance(0.5)
    T.eq(#CraftWorld.Asked(), asked, "no OpenTradeSkill from an event (the game blocks it)")
    T.eq(W.ChosenID(), TAILOR, "the guide follows to Tailoring")
    T.eq(CP.charDB.guideProf, TAILOR, "its chosen profession changes")
    CraftWorld.Close()
    T.eq(W.ChosenID(), TAILOR, "and stays there once the window shuts")
end)

T.test("the follow: every profession, a tab switch inside the window, never in All mode", function()
    shut(LW)
    CraftWorld.Open(LW)
    T.eq(CP.charDB.guideProf, LW, "the guide's own profession: nothing changes")
    -- A tab switch inside the open window, with no close between.
    CraftWorld.Open(TAILOR)
    T.advance(0.1)
    T.eq(CP.charDB.guideProf, TAILOR, "a tab switch moves the guide too")
    CraftWorld.Close()
    T.advance(1)

    W.SetMode("all")
    W.Pick(LW)
    W.SetMode("all")
    CraftWorld.Open(TAILOR)
    T.advance(0.1)
    T.eq(CP.charDB.guideProf, LW, "All mode: the One view's pick stays")
    CraftWorld.Close()
end)

-- 4. The vendor Buy ---------------------------------------------------------------------

local bought

local function merchant(slots)
    World.patch("GetMerchantNumItems", function() return #slots end)
    World.patch("GetMerchantItemID", function(i) return slots[i] and slots[i][1] or nil end)
    World.patch("GetMerchantItemLink", function(i)
        return slots[i] and ("|cffffffff|Hitem:%d::::::::20:::::|h[x]|h|r"):format(slots[i][1])
    end)
    World.patch("C_MerchantFrame.GetItemInfo", function(i)
        local s = slots[i]
        return s and { price = s[2], stackCount = 1, numAvailable = -1, isPurchasable = true }
    end)
    World.patch("GetMerchantItemMaxStack", function() return 20 end)
    bought = {}
    World.patch("BuyMerchantItem", function(i, n) bought[#bought + 1] = { i, n } end)
    local f = CreateFrame("Frame", nil, UIParent)
    World.set(_G, "MerchantFrame", f)
    World.onEnd(function()
        if B.open then T.fire("MERCHANT_CLOSED") end
    end)
    T.fire("MERCHANT_SHOW")
    T.advance(B.CHECK_EVERY * 2)
end

T.test("the buy trace prints the slots, the offer, each purchase and the game's answers", function()
    shut(LW)
    World.set(CP.trace, "buy", nil)
    World.patch("GetMoney", function() return 1000000 end)
    SlashCmdList.PROFLOST("trace buy on")
    T.eq(CP.trace.buy, true, "on")
    merchant({ { 2320, 10 }, { FINE_THREAD, 100 } })
    local b = B.Button()
    T.ok(b ~= nil and b:IsShown(), "Buy shows")
    local from = #T.prints()
    click(b)
    click(B.popup.all)
    T.fire("UI_ERROR_MESSAGE", 1, "You don't have enough money.")
    local text = printedSince(from)
    for _, want in ipairs({ "Buy for guide clicked", "merchant: 2 slots", "slot 2: id 2321", "price 100",
        "isPurchasable true", "max 20", "confirmation: ", "Buy on", "confirmation Buy clicked",
        "BuyMerchantItem(2, 20) -> true", "UI_ERROR_MESSAGE 1 You don't have enough money." }) do
        T.ok(text:find(want, 1, true) ~= nil, "the trace has " .. want)
    end
    SlashCmdList.PROFLOST("trace buy off")
    T.eq(CP.trace.buy, nil)
end)

-- Daylight UI's vendor window shown, the game's MerchantFrame hidden, Fine Thread in stock.
local function daylightShop()
    local game = CreateFrame("Frame", nil, UIParent)
    game:Hide()
    World.set(_G, "MerchantFrame", game)
    local npc = CreateFrame("Frame", nil, UIParent)
    local page = CreateFrame("Frame", nil, npc)
    local foot = CreateFrame("Frame", nil, page)
    npc.pages = { shop = page }
    page.foot = { frame = foot }
    World.set(_G, "DaylightUINpc", npc)
    return npc, foot
end

T.test("Daylight's vendor window with MerchantFrame hidden: Buy is on for Fine Thread, and the trace opens with the vendor", function()
    shut(LW)
    World.patch("GetMoney", function() return 1000000 end)
    World.set(CP.trace, "buy", nil)
    SlashCmdList.PROFLOST("trace buy on")
    local npc, foot = daylightShop()
    local from = #T.prints()
    merchant({ { 2320, 10 }, { FINE_THREAD, 100 } })
    MerchantFrame:Hide()
    T.advance(B.CHECK_EVERY * 2)
    local text = printedSince(from)
    T.ok(not MerchantFrame:IsShown(), "the game's window is hidden")
    local b = B.Button()
    T.ok(b ~= nil and b:IsShown(), "Buy shows")
    T.ok(S.IsOn(b), "and is on: " .. tostring(B.Reason()))
    T.eq(B.Reason(), nil)
    T.eq(select(2, b:GetPoint(1)), foot, "at Daylight's footer")
    for _, want in ipairs({ "merchant: 2 slots", "slot 2: id 2321", "offered", "need item 2321", "have 0",
        "sold here", "offer Fine Thread", "money 1000000", "Daylight footer: button ON" }) do
        T.ok(text:find(want, 1, true) ~= nil, "the trace has " .. want .. " in:\n" .. text)
    end
    SlashCmdList.PROFLOST("trace buy off")
end)

T.test("Buy is off with its reason when the player can't pay, and the trace says why", function()
    shut(LW)
    World.patch("GetMoney", function() return 5 end)
    World.set(CP.trace, "buy", nil)
    SlashCmdList.PROFLOST("trace buy on")
    daylightShop()
    local from = #T.prints()
    merchant({ { FINE_THREAD, 100 } })
    local b = B.Button()
    T.ok(b ~= nil and b:IsShown() and not S.IsOn(b), "shown, off")
    T.ok(B.Reason():find("Costs", 1, true) ~= nil and B.Reason():find("you have", 1, true) ~= nil, tostring(B.Reason()))
    T.ok(printedSince(from):find("button OFF, Costs", 1, true) ~= nil, "the trace gives the reason")
    GameTooltip:Hide()
    b:GetScript("OnEnter")(b)
    SlashCmdList.PROFLOST("trace buy off")
end)

T.test("Buy says so when the vendor's items aren't readable yet", function()
    shut(LW)
    daylightShop()
    merchant({ { FINE_THREAD, 100 } })
    World.patch("GetMerchantItemID", function() return nil end)
    World.patch("GetMerchantItemLink", function() return nil end)
    T.fire("MERCHANT_UPDATE")
    T.eq(B.Reason(), "Can't read this vendor's items yet")
    T.ok(not S.IsOn(B.Button()), "off")
end)

T.test("buying spaces its purchases, stops when the merchant closes, and survives a missing cap call", function()
    shut(LW)
    merchant({ { FINE_THREAD, 100 } })
    local lines = { { itemID = FINE_THREAD, name = "Fine Thread", count = 45, index = 1, cost = 4500, stack = 1 } }
    B.Buy(lines)
    T.eq(#bought, 1, "the first purchase inside the click")
    T.eq(bought[1][2], 20)
    T.advance(B.STEP)
    T.eq(#bought, 2, "the next one a step later")
    T.fire("MERCHANT_CLOSED")
    T.advance(B.STEP * 3)
    T.eq(#bought, 2, "nothing once the merchant closes")

    T.fire("MERCHANT_SHOW")
    World.patch("GetMerchantItemMaxStack", nil)
    bought = {}
    local calls = B.Calls(lines)
    T.eq(#calls, 45, "one at a time without the cap call")
    T.eq(calls[1].quantity, 1)
end)

-- 5. All mode's making strip ------------------------------------------------------------

T.test("All mode: a batch from the open profession's card swaps its buttons for the making strip", function()
    local ui = shut(TAILOR)
    CraftWorld.Open(TAILOR)
    T.advance(0.2)
    local row
    for _, r in ipairs(ui.rows) do
        if r.spell and r.learned and not (r.rank or r.train or r.side) then row = r break end
    end
    T.ok(row ~= nil, "a learned step")
    for _, pair in ipairs(row.recipe.reagents) do CraftWorld.SetBag(pair[1], pair[2] * 3) end
    T.fire("BAG_UPDATE_DELAYED")
    CP.GuideTab.Pick(row)
    W.SetMode("all")
    World.onEnd(function() W.SetMode("one") end)   -- All mode folds the window
    local card
    for _, c in ipairs(ui.cardList) do if c.key == TAILOR then card = c end end
    local btn = CreateFrame("Button", nil, UIParent)
    btn:SetSize(P.WIDTH, 62)
    CP.GuideTab.InitCard(btn, card)
    T.ok(btn.one:IsShown(), "Craft 1 before the batch")
    click(btn.avail)
    T.ok(CP.Crafting.ShowStrip(), "our batch runs")
    CP.GuideTab.InitCard(btn, card)
    T.ok(btn.making ~= nil and btn.making:IsShown(), "the making strip shows")
    T.ok(not btn.one:IsShown() and not btn.avail:IsShown() and not btn.craft:IsShown(), "the buttons hide")
    T.ok(not btn.need:IsShown(), "the need line gives way")
    T.ok(btn.making.text:GetText():find("Making", 1, true) ~= nil, btn.making.text:GetText())
    T.eq(btn.making:GetHeight(), CP.GuideTab.CARD_STRIP.height, "as tall as the card's buttons")
    T.eq(btn.making.stop.label:GetText(), "Stop")

    while CraftWorld.Cast() do end
    T.advance(1)
    T.ok(not CP.Crafting.Busy(), "the batch ended")
    CP.GuideTab.InitCard(btn, card)
    T.ok(not btn.making:IsShown(), "the strip goes")
    T.ok(btn.one:IsShown() and btn.need:IsShown(), "the buttons come back")
end)

-- 6. Skin shells stay under their content ---------------------------------------------------

T.test("a skin's shell and caps return to their place after the window's level moves", function()
    DaylightWorld.begin({ plugin = true })
    MapWorld.begin()
    CraftWorld.begin({ professions = { [LW] = 100 } })
    World.set(CP.db, "hideInCombat", false)
    World.set(CP.db, "windowClosed", nil)
    World.onEnd(function() W.opened = false; W.Update() end)

    -- The harness keeps no levels. The window's follow its SetFrameLevel calls, and a stand-in
    -- skin whose shell clamps to 10000 on every move shows the squash a high level causes.
    local plevel = 5
    local shells = {}
    World.set(P.frame, "GetFrameLevel", function() return plevel end)
    World.set(P.frame, "SetFrameLevel", function(_, n)
        plevel = n
        for _, s in ipairs(shells) do s.level, s.over.level = 10000, 10000 end
    end)
    local function standIn(frame)
        local s = { level = 0, over = { level = 0 } }
        function s:SetFrameLevel(n) self.level = n end
        function s.over:SetFrameLevel(n) self.level = n end
        shells[#shells + 1] = s
        World.set(frame, "GetFrameLevel", function() return plevel end)
        return s
    end
    World.set(S.Daylight(), "Skin", function(frame) return frame.__standIn end)
    local f = CreateFrame("Frame", nil, P.frame)
    f.__standIn = standIn(f)
    S.Popup(f)
    local function under(where)
        T.ok(f.__standIn.level < plevel, where .. ": the shell is under the content")
        T.ok(f.__standIn.over.level > plevel, where .. ": the caps are over it")
    end

    CraftWorld.Open(LW)
    under("with Daylight UI's window open")
    CraftWorld.Close()
    under("after it closes")
    W.Place()
    under("placed again")
end)
