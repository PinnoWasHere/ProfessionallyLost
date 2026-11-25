-- The guide window after the owner's 0.2.12-beta test: its own
-- fade area, the vendor button's label, Fine Thread offered when the game leaves a slot's
-- item id empty, and the minimap button while a profession window holds the window.

local CP = ProfLost
local W, P, B, Look = CP.Window, CP.Panel, CP.Buying, CP.Look
local LW, TAILOR = 165, 197
local DUROTAR = 1411
local FINE_THREAD = 2321

local function shut(prof, skill)
    MapWorld.begin({ zone = DUROTAR, level = 20, side = "Horde" })
    CraftWorld.begin({ professions = { [LW] = skill or 100, [TAILOR] = 60 } })
    World.set(CP.db, "hideInCombat", false)
    World.set(CP.db, "windowClosed", nil)
    World.onEnd(function()
        W.CancelPick()
        W.opened = false
        W.Update()
    end)
    CraftWorld.Open(prof)
    CraftWorld.Close()
    World.set(CP.charDB, "guideMode", "one")
    W.Pick(prof)
end

-- 1. The fade area ------------------------------------------------------------------------

T.test("the guide window registers its own fade key, with no saved choice and no float", function()
    DaylightWorld.begin({ plugin = true })
    local fades = DaylightWorld.state.fades
    local spec = fades.guidewindow
    T.ok(spec ~= nil, "registered as guidewindow")
    T.eq(fades.checklist, nil, "not under the old checklist key")
    T.eq(spec.scope, "ProfLost")
    T.eq(spec.path, "guideFade")
    T.eq(spec.path, CP.Plugin.FADE_PATH)
    T.eq(spec.float, false, "General > Fade's Float everything leaves it alone")
    T.eq(spec.frames()[1], P.frame)
    T.eq(CP.Plugin.Defaults().guideFade, nil, "no default table: Daylight UI's own default is full alpha")
    T.ok(W.managed.fade, "the window knows Daylight UI fades it")
    T.eq(Look.FADE_KEY, "plugin.ProfLost." .. CP.Plugin.FADE_KEY)
end)

-- 2. The vendor button ------------------------------------------------------------------

local bought

local function merchant(slots, links)
    World.patch("GetMerchantNumItems", function() return #slots end)
    World.patch("GetMerchantItemID", function(i) return not links and slots[i] and slots[i][1] or nil end)
    World.patch("GetMerchantItemLink", function(i)
        return slots[i] and ("|cffffffff|Hitem:%d::::::::20:::::|h[x]|h|r"):format(slots[i][1])
    end)
    World.patch("C_MerchantFrame.GetItemInfo", function(i)
        local s = slots[i]
        return s and { price = s[2], stackCount = 1, numAvailable = -1, isPurchasable = true }
    end)
    World.patch("GetMerchantItemMaxStack", function() return 20 end)
    World.patch("GetMoney", function() return 100000000 end)
    bought = {}
    World.patch("BuyMerchantItem", function(i, n) bought[#bought + 1] = { i, n } end)
    World.set(B, "open", true)
    World.onEnd(function()
        if B.open then T.fire("MERCHANT_CLOSED") end
    end)
end

local function gameVendor()
    local f = CreateFrame("Frame", nil, UIParent)
    World.set(_G, "MerchantFrame", f)
    return f
end

T.test("the vendor button reads ProfLost Buy in the title's gradient", function()
    shut(LW)
    gameVendor()
    merchant({ { 2320, 10 }, { FINE_THREAD, 100 } })
    T.fire("MERCHANT_SHOW")
    T.advance(B.CHECK_EVERY * 2)
    local b = B.Button()
    T.ok(b ~= nil and b:IsShown(), "shows")
    T.eq(B.LABEL, "Buy for guide")
    T.eq(b.label:GetText(), CP.Gradient("Buy for guide"))
    T.ok(b.label:GetText():find("|cff1fb5a6B", 1, true) ~= nil, "starts teal")
    T.ok(b.label:GetText():find("|cffe0b43ce", 1, true) ~= nil, "ends brass")
    T.eq(b:GetObjectType(), "Button")
end)

-- 3. Fine Thread -------------------------------------------------------------------------

T.test("Fine Thread is offered at a vendor whose slots give no item id, only a link", function()
    shut(LW)
    gameVendor()
    merchant({ { 2320, 10 }, { FINE_THREAD, 100 }, { 159, 5 } }, true)
    T.fire("MERCHANT_SHOW")
    T.advance(B.CHECK_EVERY * 2)
    local ids = {}
    for _, l in ipairs(B.vendor.lines) do ids[l.itemID] = l end
    T.ok(ids[FINE_THREAD] ~= nil, "Fine Thread is on the list")
    T.eq(ids[FINE_THREAD].index, 2)
    T.eq(ids[159], nil, "water isn't")
    local b = B.Button()
    b:GetScript("OnClick")(b)
    B.popup.all:GetScript("OnClick")(B.popup.all)
    T.advance(B.STEP * 10)
    local took = 0
    for _, call in ipairs(bought) do
        T.eq(call[1], 2, "from Fine Thread's slot")
        took = took + call[2]
    end
    T.eq(took, ids[FINE_THREAD].count, "all of it bought")
end)

T.test("a slot with no item id yet is looked at again until the game gives it", function()
    shut(LW)
    gameVendor()
    local known = false
    World.patch("GetMerchantNumItems", function() return 1 end)
    World.patch("GetMerchantItemID", function() return known and FINE_THREAD or nil end)
    World.patch("GetMerchantItemLink", function() return nil end)
    World.patch("C_MerchantFrame.GetItemInfo", function()
        return { price = 100, stackCount = 1, numAvailable = -1, isPurchasable = true }
    end)
    World.patch("GetMerchantItemMaxStack", function() return 20 end)
    World.set(B, "open", true)
    World.onEnd(function() if B.open then T.fire("MERCHANT_CLOSED") end end)
    T.fire("MERCHANT_SHOW")
    T.advance(B.CHECK_EVERY * 2)
    T.ok(B.unresolved, "the unknown slot is noted")
    T.eq(#B.vendor.lines, 0)
    known = true
    T.advance(B.CHECK_EVERY * 2)
    T.eq(#B.vendor.lines, 1, "found once the id arrives")
    T.eq(B.vendor.lines[1].itemID, FINE_THREAD)
    T.ok(not B.unresolved)
end)

T.test("Fine Thread's need is the selected step's crafts, less what the bags hold", function()
    shut(LW)
    local row = CP.GuideTab.Selected(W.LiveFor(LW), false)
    local per
    for _, r in ipairs(row.recipe.reagents) do
        if r[1] == FINE_THREAD then per = r[2] end
    end
    local need = per * row.crafts
    T.ok(need > 4, "the step needs a few")
    CraftWorld.SetBag(FINE_THREAD, need - 4)
    T.fire("BAG_UPDATE_DELAYED")
    gameVendor()
    merchant({ { FINE_THREAD, 100 } })
    local lines = B.Wants()
    T.eq(#lines, 1)
    T.eq(lines[1].itemID, FINE_THREAD)
    T.eq(lines[1].count, 4, "only what this step is short, not the whole guide's")
end)

-- 4. The minimap button ------------------------------------------------------------------

T.test("toggling with a profession window open closes and opens the guide window, saved", function()
    shut(TAILOR)
    CraftWorld.Open(TAILOR)
    T.advance(0.2)
    T.ok(P.frame:IsShown(), "shown")
    local from = #T.prints()
    W.Toggle()
    T.ok(not P.frame:IsShown() and W.Closed(), "closed, saved")
    W.Toggle()
    T.ok(P.frame:IsShown() and not W.Closed(), "open again")
    T.eq(#T.prints(), from, "no chat line: the screen shows it")
end)

T.test("toggling says nothing and opens or closes the window", function()
    shut(TAILOR)
    T.advance(0.2)
    T.ok(P.frame:IsShown())
    local from = #T.prints()
    W.Toggle()
    T.ok(not P.frame:IsShown(), "closed")
    W.Toggle()
    T.ok(P.frame:IsShown(), "open")
    T.eq(#T.prints(), from, "no chat line")
end)

T.test("selling the Fine Thread to the open vendor brings it onto the offer", function()
    shut(LW)
    gameVendor()
    CraftWorld.SetBag(FINE_THREAD, 500)
    merchant({ { 2320, 10 }, { FINE_THREAD, 100 } })
    T.fire("MERCHANT_SHOW")
    T.advance(B.CHECK_EVERY * 2)
    local function wants()
        for _, l in ipairs(B.vendor.lines) do
            if l.itemID == FINE_THREAD then return l end
        end
    end
    T.eq(wants(), nil, "held enough: not offered")
    CraftWorld.SetBag(FINE_THREAD, 0)
    T.fire("BAG_UPDATE_DELAYED")
    T.fire("MERCHANT_UPDATE")
    T.advance(B.CHECK_EVERY * 2)
    T.ok(wants() ~= nil, "sold: offered at once")
    CraftWorld.SetBag(FINE_THREAD, 500)
    T.fire("BAG_UPDATE_DELAYED")
    T.advance(B.CHECK_EVERY * 2)
    T.eq(wants(), nil, "bought back: gone again")
end)

T.test("a sale the events miss still refreshes the offer within a moment", function()
    shut(LW)
    gameVendor()
    CraftWorld.SetBag(FINE_THREAD, 500)
    merchant({ { FINE_THREAD, 100 } })
    T.fire("MERCHANT_SHOW")
    T.advance(B.CHECK_EVERY * 2)
    T.eq(#B.vendor.lines, 0, "held enough")
    CraftWorld.SetBag(FINE_THREAD, 0)
    T.advance(B.HELD_EVERY + B.CHECK_EVERY * 2)
    T.eq(#B.vendor.lines, 1, "offered with no event at all")
end)

T.test("Leatherworking 121, no Fine Thread held: ProfLost Buy shows and offers it", function()
    shut(LW, { rank = 121, max = 150 })
    gameVendor()
    merchant({ { FINE_THREAD, 100 } })
    T.fire("MERCHANT_SHOW")
    T.advance(1)
    local b = B.Button()
    T.ok(b ~= nil and b:IsShown(), "the button shows")
    T.eq(#B.vendor.lines, 1)
    local l = B.vendor.lines[1]
    T.eq(l.itemID, FINE_THREAD)
    T.ok(l.count >= 16, ("the selected step needs %d Fine Thread"):format(l.count))
    T.eq(l.cost, l.count * 100)
end)

T.test("the same when this client has no GetMerchantItemID at all", function()
    shut(LW, { rank = 121, max = 150 })
    gameVendor()
    merchant({ { 2320, 10 }, { FINE_THREAD, 100 } }, true)
    World.set(_G, "GetMerchantItemID", nil)
    T.fire("MERCHANT_SHOW")
    T.advance(1)
    local b = B.Button()
    T.ok(b ~= nil and b:IsShown(), "the button shows")
    local got
    for _, l in ipairs(B.vendor.lines) do if l.itemID == FINE_THREAD then got = l end end
    T.ok(got ~= nil and got.index == 2, "Fine Thread from its slot")
end)
