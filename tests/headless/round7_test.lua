-- The guide window after the owner's 0.2.11-beta test: the
-- free window's look after a profession window closes and /proflost dump look, row clicks
-- switching an open profession window, All mode's craft buttons, Buy in the vendor's
-- window, and the solver preferring a known recipe over a held pattern.

local CP = ProfLost
local W, P, Host, GP, B, Look = CP.Window, CP.Panel, CP.Host, CP.GatherPanel, CP.Buying, CP.Look
local LW, TAILOR, COOKING = 165, 197, 185
local DUROTAR = 1411

local function shutTailoring()
    MapWorld.begin({ zone = DUROTAR, level = 20, side = "Horde" })
    -- Max 150: the first step that uses Fine Thread (Woolen Cape, from 85 after the bolt row) is
    -- inside the cap, so Buy for guide offers its thread.
    CraftWorld.begin({ professions = { [LW] = 100, [TAILOR] = { rank = 60, max = 150 } } })
    World.set(CP.db, "hideInCombat", false)
    World.set(CP.db, "windowClosed", nil)
    World.set(CP.db, "windowLocked", nil)
    World.set(CP.db, "windowPoint", CP.db.windowPoint)
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
    -- The guide keeps an earlier test's pick on the same profession: start on the current step.
    for _, r in ipairs(CP.GuideTab.ui.rows or {}) do
        if r.current then
            CP.GuideTab.Pick(r)
            break
        end
    end
    return CP.GuideTab.ui
end

local function click(b) b:GetScript("OnClick")(b) end
local function isOn(b) return CP.Style.IsOn(b) end

-- Alpha the harness doesn't keep: `f` remembers what it was given, and still runs what
-- was hooked onto its SetAlpha (Look's record of who set it).
local function keepAlpha(f, start)
    local a = start or 1
    local own = f.SetAlpha
    World.set(f, "SetAlpha", function(self, v)
        a = v
        return own(self, v)
    end)
    World.set(f, "GetAlpha", function() return a end)
    World.set(f, "GetEffectiveAlpha", function() return a end)
end

local function learnedRow(ui)
    for _, r in ipairs(ui.rows) do
        if r.spell and r.learned and not (r.rank or r.train or r.side) then return r end
    end
end

-- Picks the first guide row of profession `id` whose reagents include `item`; the row.
local function pickUsing(id, item)
    for _, row in ipairs(CP.GuideTab.RowsOf(W.LiveFor(id))) do
        for _, r in ipairs(row.recipe and row.spell and row.recipe.reagents or {}) do
            if r[1] == item then
                CP.GuideTab.Pick(row)
                return row
            end
        end
    end
end

-- 1. The free window's look ------------------------------------------------------------

-- What a part's look must match: shown, alpha, parent, strata and level.
local LOOK_FIELDS = { "shown", "alpha", "effective", "parent", "strata", "level" }

local function sameLook(before, after, why)
    for _, label in ipairs(Look.ORDER) do
        local a, b = before[label], after[label]
        T.eq(b == nil, a == nil, ("%s: %s present both times"):format(why, label))
        if a and b then
            for _, k in ipairs(LOOK_FIELDS) do
                T.eq(b[k], a[k], ("%s: %s %s"):format(why, label, k))
            end
        end
    end
end

T.test("after Daylight UI's window opens and closes, the free window looks as it did before", function()
    DaylightWorld.begin({ plugin = true })
    shutTailoring()
    keepAlpha(P.frame)
    T.advance(0.5)
    local fresh = Look.State()
    T.ok(fresh.window.shown, "standing free")
    CraftWorld.Open(TAILOR)
    T.ok(Host.DaylightWindow(), "Daylight UI's window is up")
    sameLook(fresh, Look.State(), "with Daylight UI's window open")
    CraftWorld.Close()
    T.advance(0.5)
    sameLook(fresh, Look.State(), "after Daylight UI's window")
end)

T.test("while the game's window opens, fades and closes, the free window looks as it did before", function()
    shutTailoring()
    keepAlpha(P.frame)
    T.advance(0.5)
    local fresh = Look.State()
    CraftWorld.Open(TAILOR)
    local host = CraftWorld.state.frame
    World.set(host, "GetAlpha", function() return 0.3 end)
    T.advance(0.1)
    sameLook(fresh, Look.State(), "with the game's window open")
    CraftWorld.Close()
    T.advance(0.5)
    sameLook(fresh, Look.State(), "after the game's window")
end)

T.test("the dump names who set the window's alpha, and nothing puts it back", function()
    shutTailoring()
    keepAlpha(P.frame)
    T.advance(0.5)
    local function dimmer() P.frame:SetAlpha(0.25) end
    dimmer()
    T.advance(2)
    T.eq(P.frame:GetAlpha(), 0.25, "left as set: no guard resets it")
    T.eq(Look.Guard, nil)
    T.eq(Look.EVERY, nil)
    local from = #T.prints()
    SlashCmdList.PROFLOST("dump look")
    local text = table.concat(T.prints(), "\n", from + 1)
    for _, want in ipairs({ "window: ", "shell: ", "shellSkin", "gatherBody", "alpha 0.25", "Daylight fade" }) do
        T.ok(text:find(want, 1, true) ~= nil, "the dump has " .. want)
    end
    T.ok(text:find("put back", 1, true) == nil, "no put-back line")
    T.ok(text:find("alpha 0.25 at [%d.]+ s ago from %S") ~= nil, "and where each alpha came from")
end)

T.test("the fade state the dump reads is the window's own key", function()
    shutTailoring()
    World.set(W.managed, "fade", true)
    World.set(_G, "DaylightUI", { Fade = { State = function(key)
        T.eq(key, "plugin.ProfLost.guidewindow")
        return 1, 1
    end } })
    local now, goal = Look.FadeState()
    T.eq(now, 1)
    T.eq(goal, 1)
end)

-- 2. Row clicks with a profession window open on another profession -------------------

T.test("a row click with the game's window on another profession opens the row's and selects there", function()
    local ui = shutTailoring()
    CraftWorld.Open(LW)
    W.Pick(TAILOR)
    T.eq(W.ChosenID(), TAILOR, "the guide shows Tailoring over Leatherworking's window")
    local row = learnedRow(ui)
    T.ok(row ~= nil, "a learned Tailoring step")
    local asked = #CraftWorld.Asked()
    CP.GuideTab.Pick(row)
    T.eq(#CraftWorld.Asked(), asked + 1, "one window asked for")
    T.eq(CraftWorld.Asked()[#CraftWorld.Asked()], TAILOR, "Tailoring's")
    CraftWorld.Open(TAILOR)
    T.advance(0.5)
    T.eq(CraftWorld.Selected(), row.spell, "the row's recipe selected")
    T.eq(ui.details.title:GetText(), row.recipe.name, "the guide keeps the clicked row")
end)

T.test("a row click with Daylight UI's window on another profession switches it and selects there", function()
    DaylightWorld.begin({ plugin = true })
    local ui = shutTailoring()
    CraftWorld.Open(LW)
    W.Pick(TAILOR)
    local row = learnedRow(ui)
    CP.GuideTab.Pick(row)
    T.eq(CraftWorld.Asked()[#CraftWorld.Asked()], TAILOR, "Tailoring asked for")
    CraftWorld.Open(TAILOR)
    T.advance(0.5)
    T.eq(DaylightWorld.state.selected, row.spell, "selected in Daylight UI's window")
    T.eq(CraftWorld.Selected(), nil, "nothing spent on the game's hidden window")
end)

T.test("with no profession window open a row click still opens nothing", function()
    local ui = shutTailoring()
    local asked = #CraftWorld.Asked()
    CP.GuideTab.Pick(learnedRow(ui))
    T.eq(#CraftWorld.Asked(), asked, "no window asked for")
    T.eq(W.PendingPick(), nil)
end)

-- 3. All mode's craft buttons -----------------------------------------------------------

T.test("All mode: the open profession's card has Craft 1, Available and Craft all, on as the step card's", function()
    local ui = shutTailoring()
    CraftWorld.Open(TAILOR)
    T.advance(0.2)
    local row = learnedRow(ui)
    T.ok(row ~= nil and row.current, "the current step is learned")
    -- Bags for some crafts but not the whole step.
    local some = math.max(1, math.floor(row.crafts / 2))
    for _, pair in ipairs(row.recipe.reagents) do CraftWorld.SetBag(pair[1], pair[2] * some) end
    T.fire("BAG_UPDATE_DELAYED")
    CP.GuideTab.Pick(row)
    local d = ui.details
    W.SetMode("all")
    local card
    for _, c in ipairs(ui.cardList) do if c.key == TAILOR then card = c end end
    T.ok(card ~= nil and card.open, "Tailoring's card, open")
    local btn = CreateFrame("Button", nil, UIParent)
    CP.GuideTab.InitCard(btn, card)
    local L = CP.GuideTab.CARD_LABELS
    T.ok(btn.one:IsShown() and btn.avail:IsShown() and btn.craft:IsShown(), "three buttons")
    T.eq(btn.one.label:GetText(), L.one)
    T.eq(btn.avail.label:GetText(), d.craftAvail.count > 0 and L.avail:format(d.craftAvail.count) or L.availNone)
    T.eq(btn.craft.label:GetText(), L.all:format(row.crafts))
    T.eq(btn.avail.count, d.craftAvail.count, "Available crafts what the step card's does")
    T.eq(btn.craft.count, d.craftAll.count, "Craft all too")
    T.eq(isOn(btn.one), isOn(d.craftOne), "Craft 1 on as the step card's")
    T.eq(isOn(btn.avail), isOn(d.craftAvail), "Available on as the step card's")
    T.eq(isOn(btn.craft), isOn(d.craftAll), "Craft all on as the step card's")
    T.ok(isOn(btn.one) and isOn(btn.avail), "the bags make some: Craft 1 and Available on")
    T.ok(not isOn(btn.craft) or some >= row.crafts, "not the whole step: Craft all off")
    local w = btn.one:GetWidth() + btn.avail:GetWidth() + btn.craft:GetWidth()
    T.ok(w < P.WIDTH - 2 * P.BODY_PAD - 60, ("the buttons leave the need line room (%d px)"):format(w))
    click(btn.avail)
    T.eq(CraftWorld.state.casts[1] and CraftWorld.state.casts[1].count or btn.avail.count, btn.avail.count)
end)

T.test("All mode: a shut profession's card keeps one Open button", function()
    local ui = shutTailoring()
    CraftWorld.Open(LW)
    W.SetMode("all")
    local btn = CreateFrame("Button", nil, UIParent)
    for _, c in ipairs(ui.cardList) do
        if c.key == TAILOR then CP.GuideTab.InitCard(btn, c) end
    end
    T.eq(btn.craft.label:GetText(), "Open")
    T.ok(not btn.one:IsShown() and not btn.avail:IsShown(), "one button")
end)

-- 4. Buy in the vendor's window ---------------------------------------------------------

local bought

-- A merchant stocking `slots` ({ id, price, stack }); BuyMerchantItem is recorded.
local function merchant(slots)
    World.patch("GetMerchantNumItems", function() return #slots end)
    World.patch("GetMerchantItemID", function(i) return slots[i] and slots[i][1] end)
    World.patch("C_MerchantFrame.GetItemInfo", function(i)
        local s = slots[i]
        return s and { price = s[2], stackCount = s[3] or 1, numAvailable = -1, isPurchasable = true }
    end)
    World.patch("GetMerchantItemMaxStack", function() return 20 end)
    World.patch("GetMoney", function() return 100000000 end)
    bought = {}
    World.patch("BuyMerchantItem", function(i, n) bought[#bought + 1] = { i, n } end)
    World.set(B, "open", B.open)
    World.onEnd(function()
        if B.open then T.fire("MERCHANT_CLOSED") end
    end)
end

-- A stand-in for a vendor window: the game's MerchantFrame, or Daylight UI's with its
-- shop page and footer.
local function gameVendor()
    local f = CreateFrame("Frame", nil, UIParent)
    World.set(_G, "MerchantFrame", f)
    return f
end

local function daylightVendor()
    local f = CreateFrame("Frame", nil, UIParent)
    local page = CreateFrame("Frame", nil, f)
    local foot = CreateFrame("Frame", nil, page)
    f.pages = { shop = page }
    page.foot = { frame = foot }
    World.set(_G, "DaylightUINpc", f)
    return f, foot
end

-- What the Tailoring guide wants that a vendor sells: its Shop list's thread and dye.
local THREAD = 2321

T.test("the step card has no Buy; its Sells line stays", function()
    local ui = shutTailoring()
    CP.GuideTab.Pick(learnedRow(ui))
    T.eq(ui.details.buyBtn, nil, "no Buy on the card")
    T.ok(ui.details.sale:IsShown(), "the Sells line")
end)

T.test("a merchant selling what the guides need: Buy shows in the game's vendor window and asks first", function()
    shutTailoring()
    pickUsing(TAILOR, THREAD)
    gameVendor()
    merchant({ { 2320, 10 }, { THREAD, 100 }, { 159, 5 } })
    T.fire("MERCHANT_SHOW")
    T.advance(B.CHECK_EVERY * 2)
    local b = B.Button()
    T.ok(b ~= nil and b:IsShown(), "Buy shows")
    T.eq(b.label:GetText(), CP.Gradient(B.LABEL))
    local _, rel = b:GetPoint(1)
    T.eq(rel, MerchantFrame, "on the game's vendor window")
    local lines = B.vendor.lines
    local ids = {}
    for _, l in ipairs(lines) do ids[l.itemID] = l end
    T.ok(ids[THREAD] ~= nil, "Fine Thread is wanted")
    T.eq(ids[159], nil, "water isn't")
    b:GetScript("OnEnter")(b)
    b:GetScript("OnLeave")(b)
    click(b)
    T.ok(B.popup:IsShown(), "the confirmation first")
    T.eq(#bought, 0, "nothing bought yet")
    T.ok(B.popup.lines[1]:GetText():find("Fine Thread", 1, true) ~= nil, B.popup.lines[1]:GetText())
    click(B.popup.all)
    T.ok(#bought > 0, "bought on the confirmation's click")
    T.eq(bought[1][1], ids[THREAD].index or bought[1][1])
    T.fire("MERCHANT_CLOSED")
    T.ok(not b:IsShown(), "gone with the merchant")
end)

T.test("a merchant selling nothing the guides need: no Buy", function()
    shutTailoring()
    gameVendor()
    merchant({ { 159, 5 }, { 4540, 25 } })
    T.fire("MERCHANT_SHOW")
    T.advance(B.CHECK_EVERY * 2)
    local b = B.Button()
    T.ok(b ~= nil and b:IsShown() and not CP.Style.IsOn(b), "Buy shows, off")
    T.eq(B.Reason(), "Nothing here " .. B.SelectedText() .. " needs")
end)

T.test("Daylight UI's vendor window: Buy sits at its footer's left end, and waits for the window", function()
    shutTailoring()
    local game = gameVendor()
    game:Hide()
    local npc, foot = daylightVendor()
    npc:Hide()
    merchant({ { THREAD, 100 } })
    T.fire("MERCHANT_SHOW")
    local b = B.Button()
    T.ok(b == nil or not b:IsShown(), "not before Daylight UI's window shows")
    npc:Show()
    T.advance(B.CHECK_EVERY * 2)
    b = B.Button()
    T.ok(b and b:IsShown(), "shows with it")
    local point, rel, relPoint = b:GetPoint(1)
    T.eq(rel, foot, "beside its footer")
    T.eq(point, "LEFT")
    T.eq(relPoint, "LEFT", "at the footer's left end; Sell junk and Goodbye sit right")
    T.eq(b:GetParent(), foot, "a child of Daylight UI's footer, so it rises with the window")
    npc:Hide()
    T.advance(B.CHECK_EVERY * 2)
    T.ok(not b:IsShown(), "goes with the window")
end)

T.test("Daylight UI's vendor window is toplevel and raises on a click: Buy rises with it and the click lands", function()
    shutTailoring()
    pickUsing(TAILOR, THREAD)
    local game = gameVendor()
    game:Hide()
    local npc, foot = daylightVendor()
    merchant({ { THREAD, 100 } })
    T.fire("MERCHANT_SHOW")
    T.advance(B.CHECK_EVERY * 2)
    local b = B.Button()
    T.ok(b and b:IsShown(), "shows")
    -- Frame levels modelled per frame; a toplevel raise moves the window and everything under it.
    local tree, level = { npc, npc.pages.shop, foot, b }, {}
    for n, f in ipairs(tree) do
        level[f] = n
        World.set(f, "GetFrameLevel", function() return level[f] end)
        World.set(f, "SetFrameLevel", function(_, v) level[f] = v end)
    end
    B.vendor.host = nil
    T.advance(B.CHECK_EVERY * 2)   -- placed again against the modelled levels
    local function raise()
        for _, f in ipairs(tree) do level[f] = level[f] + 100 end
    end
    local function under(f, root)
        while f do
            if f == root then return true end
            f = f:GetParent()
        end
        return false
    end
    raise()
    T.ok(under(b, npc), "the button is the window's descendant")
    T.ok(b:GetFrameLevel() > npc:GetFrameLevel(), "still above the window after the raise")
    click(b)
    T.ok(B.popup:IsShown(), "the click runs the confirmation")
    B.popup:Hide()
end)

T.test("a pattern the plan still needs, sold here and not in the bags, is on the list", function()
    shutTailoring()
    gameVendor()
    local found
    for _, id in ipairs({ TAILOR, LW }) do
        local live = W.LiveFor(id)
        for _, st in ipairs(live and live.plan or {}) do
            local r = st.spell and live.guide.recipes[st.spell]
            if not found and r and r.pattern and r.src == "vendor" and not live.learned[st.spell] then
                found = r
            end
        end
    end
    T.ok(found ~= nil, "a plan step on a vendor pattern")
    merchant({ { found.pattern, 500 } })
    T.fire("MERCHANT_SHOW")
    local mats, _, lines = B.Wants()
    T.eq(#mats, 0, "never among the materials")
    T.ok(lines[1] and lines[1].itemID == found.pattern and lines[1].pattern, "the pattern, once")
    T.eq(lines[1].count, 1)
    CraftWorld.SetBag(found.pattern, 1)
    T.eq(#select(3, B.Wants()), 0, "not once it's in the bags")
end)

-- 5. A known recipe over a held pattern --------------------------------------------------

T.test("the solver drops a held pattern for a known recipe that costs no more", function()
    local guide = CP.Guides[COOKING]
    local price = function() return 10 end
    local prefer = CP.Plan.Expand({ { 5, 20, 7752 }, { 20, 50, 7751 } })
    local plan = CP.Solver.Plan(guide, 5, { [7751] = true }, price, nil, prefer, {}, {})
    local first
    for _, st in ipairs(plan) do if st.spell then first = first or st end end
    T.eq(first.spell, 7751, "Brilliant Smallfish, known, from 5")
    -- Neither known: the last plan's pick holds, as before.
    plan = CP.Solver.Plan(guide, 5, {}, price, nil, prefer, {}, {})
    first = nil
    for _, st in ipairs(plan) do if st.spell then first = first or st end end
    T.eq(first.spell, 7752, "the last plan's Slitherskin Mackerel holds")
end)
