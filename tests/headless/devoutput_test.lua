-- Developer traces stay out of a player's chat: switches saved by older builds are cleared
-- at load, and a trace turned on lasts only for its session (Core/Init.lua CP.trace).

local CP = ProfLost
local W, P, B, Scan = CP.Window, CP.Panel, CP.Buying, CP.Scan
local LW, TAILOR = 165, 197
local DUROTAR, BARRENS = 1411, 1413
local FINE_THREAD = 2321
local LIGHT, MEDIUM = 2318, 2319
local NOW = 1800000000

local function click(b) b:GetScript("OnClick")(b) end

-- Trace output in chat: a tagged trace line or one of its indented stack lines.
local function devLines(from)
    local out = {}
    for i = from + 1, #T.prints() do
        local line = tostring(T.prints()[i])
        if line:find("|cff1fb5a6ProfLost ", 1, true) or line:find("^    ") then out[#out + 1] = line end
    end
    return out
end

-- Fails with the lines when `lines` holds any.
local function silent(lines, label)
    T.eq(#lines, 0, (label or "no trace lines") .. ":\n" .. table.concat(lines, "\n"))
end

-- Saved variables from an older build with every trace switch on, then the load.
local function oldSaveLoaded()
    for _, key in ipairs(CP.OLD_TRACE_KEYS) do World.set(CP.db, key, true) end
    CP.LoadSaved()
    for _, key in ipairs(CP.OLD_TRACE_KEYS) do T.eq(CP.db[key], nil, key .. " cleared at load") end
    T.eq(next(CP.trace), nil, "every trace off")
end

-- Tailoring's window opened once and shut; the guide on Tailoring's current step.
local function shutTailoring()
    DaylightWorld.begin({ plugin = true })
    MapWorld.begin({ zone = DUROTAR, level = 20, side = "Horde" })
    CraftWorld.begin({ professions = { [LW] = 100, [TAILOR] = 60 } })
    World.set(CP.db, "hideInCombat", false)
    World.set(CP.db, "windowClosed", nil)
    World.onEnd(function()
        W.CancelPick()
        W.opened = false
        W.Update()
    end)
    CraftWorld.Open(TAILOR)
    CraftWorld.Close()
    World.set(CP.charDB, "guideMode", "one")
    W.Pick(TAILOR)
    P.tabs.guide.button:GetScript("OnClick")()
    local ui = CP.GuideTab.ui
    for _, r in ipairs(ui.rows) do
        if r.spell and r.learned and not (r.rank or r.train or r.side) then CP.GuideTab.Pick(r) break end
    end
    return ui
end

-- An Open click and the window it opens; the trace lines it printed.
local function openClick(ui)
    local from = #T.prints()
    click(ui.details.craftAll)
    CraftWorld.Open(TAILOR)
    T.advance(W.TRACE_AFTER + 1)
    T.fire("ADDON_ACTION_BLOCKED", CP.name, "UNKNOWN()")
    return devLines(from)
end

T.test("old saved trace switches: an Open click prints no trace", function()
    oldSaveLoaded()
    local ui = shutTailoring()
    silent(openClick(ui))
end)

T.test("old saved trace switches: a vendor Buy prints no trace", function()
    oldSaveLoaded()
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
    World.set(CP.charDB, "guideMode", "one")
    W.Pick(LW)
    P.tabs.guide.button:GetScript("OnClick")()
    T.advance(1)
    World.patch("GetMoney", function() return 1000000 end)
    local slots = { { 2320, 10 }, { FINE_THREAD, 100 } }
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
    local bought = {}
    World.patch("BuyMerchantItem", function(i, n) bought[#bought + 1] = { i, n } end)
    World.set(_G, "MerchantFrame", CreateFrame("Frame", nil, UIParent))
    World.onEnd(function()
        if B.open then T.fire("MERCHANT_CLOSED") end
    end)
    local from = #T.prints()
    T.fire("MERCHANT_SHOW")
    T.advance(B.CHECK_EVERY * 2)
    local b = B.Button()
    T.ok(b ~= nil and b:IsShown(), "Buy shows")
    click(b)
    click(B.popup.all)
    T.ok(#bought > 0, "bought")
    T.fire("UI_ERROR_MESSAGE", 1, "You don't have enough money.")
    T.fire("BAG_UPDATE", 0)
    T.advance(B.TRACE_AFTER + 1)
    silent(devLines(from))
end)

T.test("old saved trace switches: an auction scan prints no trace", function()
    oldSaveLoaded()
    Scan.Stop()
    CP.Panel.frame:Hide()
    T.advance(1)
    CP.db.prices, CP.db.priceScans, CP.db.priceAsked = nil, nil, nil
    AHWorld.begin({ listings = {}, now = NOW, replicate = {
        { itemID = MEDIUM, count = 20, buyout = 3000 },
        { itemID = LIGHT, count = 10, buyout = 450 },
    } })
    World.onEnd(function()
        Scan.Stop()
        CP.db.prices, CP.db.priceScans, CP.db.priceAsked = nil, nil, nil
    end)
    AHWorld.Open()
    local from = #T.prints()
    T.ok(Scan.Start(), "the scan starts")
    AHWorld.SendList()
    for _ = 1, 300 do
        if not Scan.Running() then break end
        T.advance(0.1)
    end
    T.ok(not Scan.Running(), "the scan ended")
    silent(devLines(from))
end)

T.test("old saved trace switches: a zone change and the profession window's look print no trace", function()
    oldSaveLoaded()
    MapWorld.begin({ zone = DUROTAR, level = 20, side = "Horde" })
    CraftWorld.begin({ professions = { [LW] = 100 } })
    local from = #T.prints()
    MapWorld.Move(BARRENS, 0.5, 0.5)
    CraftWorld.Open(LW)
    CraftWorld.Close()
    T.fire("BAG_UPDATE", 0)
    T.advance(CP.Look.WATCH_EVERY * 4)
    silent(devLines(from))
end)

T.test("/proflost trace open on prints this session only; a reload turns it off and leaves nothing saved", function()
    CP.LoadSaved()
    World.onEnd(function() CP.SetTracing("open", false) end)
    local ui = shutTailoring()
    SlashCmdList.PROFLOST("trace open on")
    T.eq(CP.trace.open, true, "on for the session")
    T.eq(CP.db.traceOpen, nil, "nothing saved")
    local lines = openClick(ui)
    T.ok(#lines > 0, "the trace prints")
    T.ok(table.concat(lines, "\n"):find("Open profession 197", 1, true) ~= nil, table.concat(lines, "\n"))
    CraftWorld.Close()

    -- The reload reads the saved variables again; the scene keeps its character.
    local char = CP.charDB
    CP.LoadSaved()
    CP.charDB = char
    T.eq(CP.trace.open, nil, "off after the reload")
    silent(openClick(ui), "silent after the reload")
end)
