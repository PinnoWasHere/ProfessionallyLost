local _, CP = ...
if CP.stopped then return end

-- Buying what the guides need from the open merchant. A Buy button sits in the vendor's
-- own window, bottom left: Daylight UI's vendor window, or the game's MerchantFrame
-- without it. It offers what the selected guide row needs from this merchant: the row's
-- materials for its remaining crafts, less what the player holds (the step card's reagent
-- counts). The selected row is the picked one (a main step or an "or" row) in One mode,
-- the current step otherwise; All mode takes each guided profession's current step.
-- Patterns and books are never part of that purchase. Once the materials are bought, a
-- second confirmation lists the patterns this merchant sells for any step of the guides
-- (learnable yet or not) with the skill each needs, and Buy or Skip. With no materials to
-- buy it goes straight to that one. Buying runs only from the player's clicks on the
-- confirmations, which show quantities and cost first.

local S = CP.Style
local Buying = { open = false }
CP.Buying = Buying

-- Trace -----------------------------------------------------------------------------

-- Hidden: /proflost trace buy on|off prints each step of a Buy to chat: on every vendor
-- open and offer rebuild the merchant's slots, the selected row and its needs, the offer,
-- the patterns, the money and whether the button is on and why; then the click, the confirmation, each
-- purchase call and what the game answers. On for this session only.
Buying.TRACE_AFTER = 5   -- seconds the game's answers are printed after the last purchase
local traceUntil = 0

function Buying.Tracing()
    return CP.trace.buy == true
end

function Buying.Trace(fmt, ...)
    if not Buying.Tracing() then return end
    CP.TraceLine("buy", GetTime(), fmt, ...)
end
local trace = Buying.Trace

function Buying.SetTrace(on)
    CP.SetTracing("buy", on)
    Buying.HearBags()
    CP:Print("Buy trace " .. (on and "on: open a vendor, click Buy for guide, then Buy, and paste what follows." or "off."))
end

-- The game's answers to a purchase, while a Buy is fresh.
local function answer(event, ...)
    if not Buying.Tracing() or GetTime() > traceUntil then return end
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
    trace("%s %s", event, table.concat(parts, " "))
end
for _, event in ipairs({ "MERCHANT_UPDATE", "UI_ERROR_MESSAGE", "PLAYER_MONEY" }) do
    CP:On(event, function(_, ...) answer(event, ...) end)
end

-- BAG_UPDATE fires per bag on every change; it is heard only while the trace is on.
local function bagAnswer(_, ...) answer("BAG_UPDATE", ...) end
local bagHeard = false
function Buying.HearBags()
    local on = Buying.Tracing()
    if on == bagHeard then return end
    bagHeard = on
    if on then CP:On("BAG_UPDATE", bagAnswer) else CP:Off("BAG_UPDATE", bagAnswer) end
end
CP:On("PLAYER_LOGIN", Buying.HearBags)

CP:On("MERCHANT_SHOW", function()
    Buying.open = true
    Buying.vendor.lastTrace, Buying.vendor.lastState = nil, nil
    Buying.watch:Show()
    CP.Panel:Refresh()
    Buying.Changed()
end)
CP:On("MERCHANT_UPDATE", function() if Buying.open then Buying.StockChanged() end end)
CP:On("PLAYER_MONEY", function()
    if Buying.open then
        Buying.RefreshPopup()
        Buying.Update()
    end
end)
CP:On("BAG_UPDATE_DELAYED", function() if Buying.open then Buying.Look() end end)
CP:On("ProfLost_ITEM_LOADED", function() if Buying.open then Buying.Changed() end end)
CP:On("MERCHANT_CLOSED", function()
    Buying.open = false
    Buying.ForgetPurse()
    Buying.watch:Hide()
    if Buying.popup then Buying.popup:Hide() end
    Buying.Changed()
    CP.Panel:Refresh()
end)

-- The item in merchant slot `i`. The game can leave GetMerchantItemID empty for a slot
-- whose item it hasn't loaded, while the slot's link already names it.
local function itemAt(i)
    local id = GetMerchantItemID and GetMerchantItemID(i)
    if id then return id end
    local link = GetMerchantItemLink and GetMerchantItemLink(i)
    return type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
end

-- itemID -> { index, price, stack, left } for what the open merchant sells for gold
-- and has in stock. `left` is the stock of a limited item, nil when unlimited. A slot
-- whose item is still unknown sets Buying.unresolved, so the button looks again.
function Buying.Stock()
    local out = {}
    Buying.unresolved = false
    local notes = Buying.Tracing() and {} or nil
    Buying.slotNotes, Buying.numItems = notes, 0
    if not Buying.open then return out end
    local n = GetMerchantNumItems() or 0
    Buying.numItems = n
    for i = 1, n do
        local id = itemAt(i)
        local info = C_MerchantFrame.GetItemInfo(i)
        if not id and info then Buying.unresolved = true end
        local limited = info and info.numAvailable and info.numAvailable >= 0
        local why
        if not id then why = info and "no item id yet" or "no id, no info"
        elseif not info then why = "no slot info"
        elseif info.isPurchasable == false then why = "not purchasable"
        elseif info.hasExtendedCost then why = "extended cost"
        elseif limited and info.numAvailable == 0 then why = "sold out" end
        if not why then
            out[id] = { index = i, price = info.price or 0, stack = math.max(1, info.stackCount or 1),
                        left = limited and info.numAvailable or nil }
        end
        if notes then
            info = info or {}
            notes[#notes + 1] = ("slot %d: id %s, link %s, price %s, stack %s, numAvailable %s, isPurchasable %s, extended %s -> %s"):format(
                i, tostring(id), tostring(GetMerchantItemLink and GetMerchantItemLink(i)), tostring(info.price),
                tostring(info.stackCount), tostring(info.numAvailable), tostring(info.isPurchasable),
                tostring(info.hasExtendedCost), why and ("skipped, " .. why) or "offered")
        end
    end
    return out
end

-- Of `wants` ({ { itemID, name, count } }), what this merchant sells, with cost.
-- Returns { { itemID, name, count, index, cost, stack, pattern } }, total copper.
function Buying.Price(wants, stock)
    local out, total = {}, 0
    for _, w in ipairs(wants) do
        local s = stock[w.itemID]
        if s and w.count > 0 then
            local bundles = math.ceil(w.count / s.stack)
            if s.left then bundles = math.min(bundles, s.left) end  -- limited stock
            local cost = bundles * s.price
            out[#out + 1] = { itemID = w.itemID, name = w.name, count = bundles * s.stack, index = s.index,
                              cost = cost, stack = s.stack, pattern = w.pattern, skill = w.skill, have = w.have }
            total = total + cost
        end
    end
    return out, total
end

-- Seconds between purchases, as Daylight UI's own vendor window spaces its stacks.
Buying.STEP = 0.2

-- Calls one of the game's merchant functions if it exists: ok, results.
local function call(name, ...)
    local fn = rawget(_G, name)
    if type(fn) ~= "function" then return false, "no " .. name end
    return pcall(fn, ...)
end

-- The purchases for `lines`: { { index, quantity, itemID } }. Bundled goods (sold in
-- stacks of `stack`) are bought a bundle at a time; single items in calls of at most
-- the merchant's per-purchase cap.
function Buying.Calls(lines)
    local out = {}
    for _, l in ipairs(lines) do
        if l.stack > 1 then
            for _ = 1, l.count / l.stack do
                out[#out + 1] = { index = l.index, itemID = l.itemID, cost = (l.cost or 0) / (l.count / l.stack) }
            end
        else
            local okMax, max = call("GetMerchantItemMaxStack", l.index)
            max = math.max(1, okMax and tonumber(max) or 1)
            local left = l.count
            while left > 0 do
                local n = math.min(left, max)
                out[#out + 1] = { index = l.index, quantity = n, itemID = l.itemID,
                                  cost = l.count > 0 and (l.cost or 0) * n / l.count or 0 }
                left = left - n
            end
        end
    end
    return out
end

-- True while the merchant is open and slot `c.index` still sells `c.itemID` in stock.
local function stillThere(c)
    if not Buying.open then return false end
    local s = Buying.Stock()[c.itemID]
    return s ~= nil and s.index == c.index and itemAt(c.index) == c.itemID
end

-- The purse the player will have once every purchase sent is paid. The server takes the
-- copper only when it answers, so GetMoney alone still shows it. `expected` is the purse
-- after the sent purchases; it clears once GetMoney has caught up.
local expected

function Buying.ForgetPurse() expected = nil end

function Buying.Money()
    local money = GetMoney and GetMoney() or math.huge
    if expected and money <= expected then expected = nil end
    return expected and math.min(money, expected) or money
end

-- One purchase, logged to the trace with the game's answer.
local function buyOne(c)
    if not stillThere(c) then
        trace("skip slot %d: no longer item %d in stock", c.index, c.itemID)
        return false
    end
    local ok, err = call("BuyMerchantItem", c.index, c.quantity)
    trace("BuyMerchantItem(%d, %s) -> %s%s", c.index, tostring(c.quantity), tostring(ok), ok and "" or (" " .. tostring(err)))
    if ok and (c.cost or 0) > 0 then expected = Buying.Money() - c.cost end
    return ok
end

-- Buy every line. The first purchase runs inside the click; the rest follow one per
-- STEP while the merchant stays open. A purchase is skipped unless its slot still holds
-- that item in stock, so nothing is bought that isn't there. `after`, when given, runs
-- once the last purchase is made and the merchant is still open.
function Buying.Buy(lines, after)
    traceUntil = GetTime() + Buying.TRACE_AFTER
    if not Buying.open then
        trace("Buy: the merchant is closed")
        return
    end
    if CP.Preview and CP.Preview.Refuse("buy") then return end
    local calls = Buying.Calls(lines)
    trace("Buy: %d lines, %d purchases", #lines, #calls)
    local i = 0
    local function finish()
        if after and Buying.open then after() end
    end
    local function step()
        i = i + 1
        local c = calls[i]
        if not c then return finish() end
        buyOne(c)
        traceUntil = GetTime() + Buying.TRACE_AFTER
        if calls[i + 1] and Buying.open then
            C_Timer.After(Buying.STEP, step)
        else
            finish()
        end
    end
    step()
end

-- The trace's look at the merchant: every slot and what the game says of it.
function Buying.TraceSlots()
    if not Buying.Tracing() then return end
    local okN, n = call("GetMerchantNumItems")
    trace("merchant: %s slots", tostring(okN and n))
    for i = 1, (okN and tonumber(n)) or 0 do
        local _, id = call("GetMerchantItemID", i)
        local _, link = call("GetMerchantItemLink", i)
        local _, max = call("GetMerchantItemMaxStack", i)
        local info = C_MerchantFrame.GetItemInfo(i) or {}
        trace("slot %d: id %s, link %s, price %s, stack %s, numAvailable %s, isPurchasable %s, extended %s, max %s",
            i, tostring(id), tostring(link), tostring(info.price), tostring(info.stackCount), tostring(info.numAvailable),
            tostring(info.isPurchasable), tostring(info.hasExtendedCost), tostring(max))
    end
end

-- What the guides want -----------------------------------------------------------

local function nameOf(id, fallback)
    return CP.ItemName(id) or fallback or ("item " .. id)
end

-- The patterns and books profession `live`'s plan still needs, any step of it: patterns
-- of its unlearned steps, learnable yet or not, and rank books for its current cap, none
-- of them held (bags, bank, mail, as the Shop list counts). Each line carries the skill it needs and the player's skill.
-- A profession whose known recipes are unread (Plan.Read) offers no patterns: the player may know them.
local function patternsFor(live)
    local guide, learned = live.guide, live.learned or {}
    local wanted = {}
    for _, st in ipairs(live.unread and {} or live.plan or {}) do
        local r = st.spell and guide.recipes[st.spell]
        if r and r.pattern and not learned[st.spell] then wanted[r.pattern] = true end
    end
    for _, rank in ipairs(guide.ranks or {}) do
        if rank.item then wanted[rank.item] = true end
    end
    local out = {}
    for _, b in ipairs(CP.Guide.VendorBuys(guide, learned, live.prof.max)) do
        if wanted[b.item] and CP.Purchases.Have(b.item) == 0 then
            out[#out + 1] = { itemID = b.item, name = nameOf(b.item, b.name), count = 1, pattern = true,
                              skill = b.skill or 0, have = live.prof.skill or 0 }
        end
    end
    return out
end
Buying.PatternsFor = patternsFor

-- Rank books of the gathering professions, which have no crafting guide: the Expert Fishing
-- book while Fishing sits under the cap it lifts and none is held. Lines as patternsFor's.
function Buying.GatherBooks()
    local F, G = CP.Fishing, CP.Gather
    local skill = G.Skills()[F.SKILL]
    local max = skill and G.MaxRank(F.SKILL)
    local rank = max and F.RankFor(max, UnitFactionGroup("player"))
    if not (rank and rank.kind == "book" and rank.item) or CP.Purchases.Have(rank.item) > 0 then return {} end
    return { { itemID = rank.item, name = nameOf(rank.item, F.RankName(rank)), count = 1, pattern = true,
               skill = rank.at or rank.skill, have = skill } }
end

-- The plans the offer works from: One mode's, else every guided profession's.
function Buying.Lives()
    return CP.Window.Mode() == "one" and { CP.Window.Live() } or CP.Window.AllLives()
end

-- The rows the offer works from: { { live, row } }, one per guided profession. One mode
-- takes the chosen profession's selected row (its pick, else its current step); All mode
-- takes every guided profession's current step.
function Buying.Targets()
    local out = {}
    local one = CP.Window.Mode() == "one"
    local lives = Buying.Lives()
    Buying.lives = lives
    for _, live in ipairs(lives) do
        if live.guide and live.plan then
            out[#out + 1] = { live = live, row = CP.GuideTab.Selected(live, one) }
        end
    end
    return out
end

-- A row as the trace and tooltip name it.
function Buying.RowName(row)
    local r = row and row.recipe
    if not r then return "no step" end
    local n = row.crafts or 0
    return ("%s%s (%d craft%s)"):format(row.side and "or " or "", r.name or ("spell " .. tostring(row.spell)), n, n == 1 and "" or "s")
end

-- What this merchant sells that the selected rows need, priced. Returns the material
-- lines and their total copper, then the pattern lines (any step of the guides) and theirs.
function Buying.Wants(stock)
    stock = stock or Buying.Stock()
    Buying.needs, Buying.guided, Buying.selected, Buying.watched = {}, 0, {}, {}
    Buying.capped = {}
    local targets = Buying.Targets()
    local books = Buying.GatherBooks()
    Buying.guided = #targets + #books
    for _, t in ipairs(targets) do
        Buying.selected[#Buying.selected + 1] = { prof = t.live.prof and t.live.prof.name, row = t.row, name = Buying.RowName(t.row) }
        -- A row past the cap buys nothing: its crafts give no skill until the rank is learned.
        local p = t.live.prof or {}
        local held = t.row and t.live.guide and CP.Guide.PastCap(t.live.guide, t.row.from, p.skill, p.max)
        if held then
            Buying.capped[#Buying.capped + 1] = CP.Guide.CapText(held)
            t.row = nil
        end
    end
    if next(stock) == nil then return {}, 0, {}, 0 end
    local mats, order = {}, {}
    local pool = {}   -- stock of each item not yet claimed by an earlier row
    for _, t in ipairs(targets) do
        local live, row = t.live, t.row
        if row then
            for _, m in ipairs(CP.Professions.Reagents(row.spell, row.recipe.reagents)) do
                local want = m.need * (row.crafts or 0)
                local avail = pool[m.itemID] or m.have
                local short = math.max(0, want - avail)
                pool[m.itemID] = math.max(0, avail - want)
                Buying.watched[#Buying.watched + 1] = m.itemID
                Buying.needs[#Buying.needs + 1] = { itemID = m.itemID, need = m.need * (row.crafts or 0), have = m.have,
                                                    left = short, sold = stock[m.itemID] ~= nil }
                if short > 0 and stock[m.itemID] then
                    local w = mats[m.itemID]
                    if not w then
                        w = { itemID = m.itemID, name = nameOf(m.itemID, m.name), count = 0 }
                        mats[m.itemID] = w
                        order[#order + 1] = w
                    end
                    w.count = w.count + short
                end
            end
        end
    end
    local pats, seen = {}, {}
    local sources = {}
    for _, t in ipairs(targets) do sources[#sources + 1] = patternsFor(t.live) end
    sources[#sources + 1] = books
    for _, list in ipairs(sources) do
        for _, p in ipairs(list) do
            Buying.watched[#Buying.watched + 1] = p.itemID
            Buying.needs[#Buying.needs + 1] = { itemID = p.itemID, need = 1, have = 0, left = 1,
                                                sold = stock[p.itemID] ~= nil, pattern = true }
            if stock[p.itemID] and not seen[p.itemID] then
                seen[p.itemID] = true
                pats[#pats + 1] = p
            end
        end
    end
    table.sort(pats, function(x, y)
        if x.skill ~= y.skill then return x.skill < y.skill end
        return x.itemID < y.itemID
    end)
    local lines, total = Buying.Price(order, stock)
    local patLines, patTotal = Buying.Price(pats, stock)
    return lines, total, patLines, patTotal
end

local function summary(lines)
    local parts = {}
    for _, l in ipairs(lines) do parts[#parts + 1] = ("%d %s"):format(l.count, l.name) end
    return table.concat(parts, ", ")
end

-- A pattern line with the skill it needs: "Name (learnable now)" or "Name (learnable at 160)".
function Buying.PatternText(l)
    local when = (l.skill or 0) > (l.have or 0) and ("learnable at %d"):format(l.skill) or "learnable now"
    return ("%s (%s)"):format(l.name, when)
end

-- The confirmation -----------------------------------------------------------------

Buying.POPUP_W = 340
Buying.POPUP_PAD = 12
Buying.TITLE_H, Buying.TITLE_GAP = 15, 11   -- one title line, and the gap under it

local function popup()
    if Buying.popup then return Buying.popup end
    local f = CreateFrame("Frame", "ProfLost_BuyPopup", UIParent)
    f:SetSize(Buying.POPUP_W, 150)
    f:SetPoint("CENTER", 0, 120)
    f:SetFrameStrata("DIALOG")
    f:EnableMouse(true)
    S.Popup(f)
    local pad = Buying.POPUP_PAD
    f.title = S.Text(f, "head", S.color.title)
    f.title:SetPoint("TOPLEFT", pad, -10)
    f.title:SetPoint("RIGHT", -pad, 0)
    f.title:SetWordWrap(true)
    f.lines = {}
    for i = 1, 2 do
        local t = S.Text(f, "small", S.color.label)
        t:SetWidth(Buying.POPUP_W - 2 * pad)
        t:SetWordWrap(true)
        f.lines[i] = t
    end
    f.lines[1]:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -Buying.TITLE_GAP)
    f.lines[2]:SetPoint("TOPLEFT", f.lines[1], "BOTTOMLEFT", 0, -8)
    f.all = S.Button(f, 104)
    f.all:SetPoint("BOTTOMLEFT", pad, 10)
    f.all:SetScript("OnClick", function(self)
        trace("confirmation Buy clicked: %d lines", self.lines and #self.lines or 0)
        local lines, after = self.lines or {}, self.after
        f:Hide()  -- before Buy, whose follow-up may show this popup again
        Buying.Buy(lines, after)
    end)
    f.cancel = S.Button(f, 70)
    f.cancel:SetPoint("BOTTOMRIGHT", -pad, 10)
    f.cancel.label:SetText("Cancel")
    -- Cancel skips this confirmation only: the patterns' confirmation still follows.
    f.cancel:SetScript("OnClick", function()
        trace("confirmation %s", f.kind == "patterns" and "Skip clicked" or "Cancel clicked")
        local after = f.all.after
        f:Hide()  -- before `after`, which may show this popup again
        if after and Buying.open then after() end
    end)
    tinsert(UISpecialFrames, "ProfLost_BuyPopup")  -- Escape closes it
    Buying.popup = f
    return f
end

-- Asks before buying `lines` for `total`. `kind` "patterns" lists each pattern with its
-- skill and offers Buy or Skip; otherwise the materials, with Buy or Cancel. `after` runs
-- once the purchases are made, or at once on Cancel.
function Buying.Confirm(lines, total, kind, after)
    local f = popup()
    local patterns = kind == "patterns"
    local text = {}
    for _, l in ipairs(lines) do
        text[#text + 1] = patterns and ("%s  %s"):format(Buying.PatternText(l), CP.Pricing.Format(l.cost)) or nil
    end
    f.title:SetText((patterns and "Patterns here" or "Buy for your guide step") .. "  ·  " .. CP.Pricing.Format(total))
    if patterns then
        f.lines[1]:SetText(table.concat(text, "\n"))
    else
        f.lines[1]:SetText(#lines > 0 and ("Materials: " .. summary(lines)) or "Materials: none here")
    end
    f.lines[2]:SetText("")
    f.lines[2]:SetShown(false)
    -- The title may wrap; the materials start below it.
    local title = f.title:GetStringHeight()
    title = type(title) == "number" and title > 0 and title or Buying.TITLE_H
    local h = 10 + title + Buying.TITLE_GAP + (f.lines[1]:GetStringHeight() or 14)
    f:SetHeight(math.max(110, h + 52))
    f.all.label:SetText(("Buy  %s"):format(CP.Pricing.Format(total)))
    f.cancel.label:SetText(patterns and "Skip" or "Cancel")
    f.all.lines, f.all.after, f.kind, f.total = lines, after, kind or "materials", total
    local money = GetMoney and Buying.Money() or total
    S.SetEnabled(f.all, #lines > 0 and total <= money)
    trace("%s confirmation: %d lines, total %d, money %d, Buy %s", f.kind, #lines, total, money,
        S.IsOn(f.all) and "on" or "off (not enough money)")
    for _, l in ipairs(lines) do
        trace("  %s x%d (item %d, slot %d, stack %d) %d", l.name, l.count, l.itemID, l.index, l.stack, l.cost)
    end
    f:Show()
end

-- Lights or greys the open popup's Buy button from the purse as it stands now.
function Buying.RefreshPopup()
    local f = Buying.popup
    if not (f and f:IsShown() and f.all and f.all.lines) then return end
    S.SetEnabled(f.all, #f.all.lines > 0 and (f.total or 0) <= Buying.Money())
end

-- The Buy button in the vendor's window -------------------------------------------

-- Daylight UI's vendor window (Npc/Window.lua): its frame by name, its shop page and
-- that page's footer, whose buttons (Sell junk, Repair, Goodbye) sit on the right. Read
-- only: the button is ProfLost's own, a child of that footer (or page, or MerchantFrame), laid
-- beside its left end. Daylight's windows are toplevel and raise on a click, taking their
-- children along, so a UIParent child would drop under the window between press and release.
Buying.DAYLIGHT_VENDOR = "DaylightUINpc"
Buying.DAYLIGHT_EDGE, Buying.DAYLIGHT_FOOT_Y, Buying.DAYLIGHT_H = 16, 12, 28
Buying.GAME_VENDOR = "MerchantFrame"
Buying.CHECK_EVERY = 0.2
Buying.LABEL = "Buy for guide"

-- Where the Buy button goes: the window it belongs to, the frame it sits on and how.
-- Nil while no vendor window shows the shop.
-- Daylight UI's vendor window: API.GetFrame("npc") (1.7; nil while that part is off), else
-- its global.
function Buying.DaylightWindow()
    local API = S.Daylight()
    if API and type(API.GetFrame) == "function" then return API.GetFrame("npc") end
    return rawget(_G, Buying.DAYLIGHT_VENDOR)
end

function Buying.Host()
    local npc = Buying.DaylightWindow()
    if type(npc) == "table" and npc.IsVisible and npc:IsVisible() then
        local page = type(npc.pages) == "table" and npc.pages.shop
        if not (page and page:IsVisible()) then return nil end
        local foot = type(page.foot) == "table" and page.foot.frame
        if foot and foot.IsVisible and foot:IsVisible() then
            return { kind = "Daylight footer", window = npc, on = foot, point = "LEFT", rel = "LEFT", x = 0, y = 0, h = Buying.DAYLIGHT_H }
        end
        return { kind = "Daylight shop page", window = npc, on = page, point = "BOTTOMLEFT", rel = "BOTTOMLEFT", x = Buying.DAYLIGHT_EDGE,
                 y = Buying.DAYLIGHT_FOOT_Y, h = Buying.DAYLIGHT_H }
    end
    local game = rawget(_G, Buying.GAME_VENDOR)
    if type(game) == "table" and game.IsVisible and game:IsVisible() then
        return { kind = "game MerchantFrame", window = game, on = game, point = "TOPLEFT", rel = "BOTTOMLEFT", x = 4, y = -4, h = S.BUTTON_H }
    end
    return nil
end

local vendor = { button = nil, host = nil, lines = {}, total = 0, patterns = {}, patternTotal = 0, dirty = true, since = 0 }
Buying.vendor = vendor

local function money()
    local m = GetMoney and GetMoney()
    return type(m) == "number" and m or nil
end

-- The selected rows by name, for the tooltip and the reasons.
function Buying.SelectedText()
    local parts = {}
    for _, e in ipairs(Buying.selected or {}) do
        if e.row then parts[#parts + 1] = e.name end
    end
    return #parts > 0 and table.concat(parts, ", ") or "your guide step"
end

-- Why the button is off, or nil while it is on.
function Buying.Reason()
    if Buying.numItems == 0 then return "This vendor lists no items" end
    if vendor.stockEmpty then
        return Buying.unresolved and "Can't read this vendor's items yet" or "Nothing here you can buy with gold"
    end
    if (Buying.guided or 0) == 0 then return "No guided profession to buy for" end
    if #vendor.lines == 0 and #vendor.patterns == 0 then
        if Buying.capped and #Buying.capped > 0 then return table.concat(Buying.capped, " ") end
        for _, n in ipairs(Buying.needs or {}) do
            if n.sold and n.left == 0 and not n.pattern then
                return "You hold all this vendor sells for " .. Buying.SelectedText()
            end
        end
        return "Nothing here " .. Buying.SelectedText() .. " needs"
    end
    local first = #vendor.lines > 0 and vendor.total or vendor.patternTotal
    local have = money()
    if have and first > have then
        return ("Costs %s, you have %s"):format(CP.Pricing.Format(first), CP.Pricing.Format(have))
    end
    return nil
end

local function tooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText("Buy for your guide step", 1, 1, 1)
    GameTooltip:AddLine(Buying.SelectedText(), 0.7, 0.7, 0.7, true)
    local reason = Buying.Reason()
    if reason then GameTooltip:AddLine(reason, 1, 0.5, 0.4, true) end
    -- Rows past the cap buy nothing, even while patterns here are on offer.
    for _, why in ipairs(Buying.capped or {}) do
        if not (reason and reason:find(why, 1, true)) then GameTooltip:AddLine(why, 1, 0.5, 0.4, true) end
    end
    for _, l in ipairs(vendor.lines) do
        GameTooltip:AddDoubleLine(("%d %s"):format(l.count, l.name), CP.Pricing.Format(l.cost), 0.9, 0.9, 0.9, 1, 1, 1)
    end
    if #vendor.lines > 0 then
        GameTooltip:AddDoubleLine("Total", CP.Pricing.Format(vendor.total), 1, 0.82, 0, 1, 1, 1)
    end
    if #vendor.patterns > 0 then
        GameTooltip:AddLine("Patterns here:", 1, 0.82, 0)
        for _, l in ipairs(vendor.patterns) do
            GameTooltip:AddDoubleLine(Buying.PatternText(l), CP.Pricing.Format(l.cost), 0.9, 0.9, 0.9, 1, 1, 1)
        end
    end
    if (#vendor.lines > 0 or #vendor.patterns > 0) and not reason then
        GameTooltip:AddLine("Asks first.", 0.6, 0.6, 0.6)
    end
    GameTooltip:Show()
end

-- The second confirmation: the patterns here, Buy or Skip.
function Buying.ConfirmPatterns()
    if #vendor.patterns == 0 then return end
    Buying.Confirm(vendor.patterns, vendor.patternTotal, "patterns")
end

local function makeButton()
    local b = S.Button(UIParent, 52, Buying.DAYLIGHT_H)
    b:Hide()
    b.label:SetText(CP.Gradient(Buying.LABEL))
    b:SetWidth(CP.Panel.TextWidth(b.label) + S.BUTTON_PAD)
    b:HookScript("OnMouseDown", function() trace("Buy for guide: mouse down") end)
    b:HookScript("OnMouseUp", function() trace("Buy for guide: mouse up") end)
    b:SetScript("OnClick", function()
        traceUntil = GetTime() + Buying.TRACE_AFTER
        trace("Buy for guide clicked: %d lines, %d patterns, %s", #vendor.lines, #vendor.patterns, Buying.Reason() or "on")
        Buying.TraceSlots()
        if CP.Preview and CP.Preview.Refuse("buy") then return end
        if Buying.Reason() ~= nil then return end
        if #vendor.lines > 0 then
            local after
            if #vendor.patterns > 0 then after = Buying.ConfirmPatterns end
            Buying.Confirm(vendor.lines, vendor.total, "materials", after)
        else
            Buying.ConfirmPatterns()
        end
    end)
    b:SetScript("OnEnter", tooltip)
    b:SetScript("OnLeave", GameTooltip_Hide)
    vendor.button = b
    return b
end

-- Places the button on `host` (Buying.Host): a child of the frame it sits on, above its window.
local function place(b, host)
    b:SetParent(host.on)
    b:ClearAllPoints()
    b:SetPoint(host.point, host.on, host.rel, host.x, host.y)
    b:SetHeight(host.h)
    b:SetFrameStrata(host.window:GetFrameStrata())
    b:SetFrameLevel(host.window:GetFrameLevel() + 30)
end

-- What the offer was last built from: the merchant's stock, the plans, the pick, and
-- what the player holds of every item the merchant sells or the offer reads, bags and
-- bank. A look that finds all of it the same rebuilds nothing.
vendor.held, vendor.bags, vendor.lives = {}, {}, {}

local function pickKey()
    return CP.Window.Mode() .. ":" .. tostring(CP.Window.ChosenID()) .. ":" .. CP.GuideTab.PickKey()
end

local function noteHeld(stock)
    local held, bags = {}, {}
    local function add(id)
        held[id] = C_Item.GetItemCount(id, true) or 0
        bags[id] = C_Item.GetItemCount(id) or 0
    end
    for id in pairs(stock) do add(id) end
    for _, id in ipairs(Buying.watched or {}) do add(id) end
    vendor.held, vendor.bags = held, bags
end

local function heldMoved()
    for id, n in pairs(vendor.held) do
        if (C_Item.GetItemCount(id, true) or 0) ~= n or (C_Item.GetItemCount(id) or 0) ~= vendor.bags[id] then
            return true
        end
    end
    return false
end

-- Plan.Current and Plan.Shut hand back the same table while their plan holds.
local function livesMoved()
    local lives, was = Buying.Lives(), vendor.lives
    if #lives ~= #was then return true end
    for i, live in ipairs(lives) do
        if live ~= was[i] then return true end
    end
    return false
end

local function sameStock(a, b)
    if not (a and b) then return false end
    for id, s in pairs(a) do
        local t = b[id]
        if not (t and t.index == s.index and t.price == s.price and t.stack == s.stack and t.left == s.left) then
            return false
        end
    end
    for id in pairs(b) do
        if not a[id] then return false end
    end
    return true
end

-- Reads the merchant and the guides afresh: the offer, and a trace of how it came about.
function Buying.Rebuild(stock)
    stock = stock or Buying.Stock()
    local notes = Buying.slotNotes
    vendor.stockEmpty = next(stock) == nil
    vendor.lines, vendor.total, vendor.patterns, vendor.patternTotal = Buying.Wants(stock)
    vendor.stock, vendor.lives, vendor.pickKey = stock, Buying.lives or {}, pickKey()
    noteHeld(stock)
    if not Buying.Tracing() then return end
    local out = { ("merchant: %d slots"):format(Buying.numItems or 0) }
    for _, n in ipairs(notes or {}) do out[#out + 1] = n end
    out[#out + 1] = ("guides: %d guided professions, %s mode, needs %d items"):format(Buying.guided or 0,
        CP.Window.Mode(), #Buying.needs)
    for _, e in ipairs(Buying.selected or {}) do
        out[#out + 1] = ("  selected %s: %s"):format(e.prof or "?", e.row and ("%s, key %s"):format(e.name, tostring(e.row.key)) or "no step")
    end
    for i, n in ipairs(Buying.needs) do
        if i > 40 then
            out[#out + 1] = ("  ... %d more needs"):format(#Buying.needs - 40)
            break
        end
        out[#out + 1] = ("  need item %d: need %d, have %d, buy %d, %s%s"):format(n.itemID, n.need or 0, n.have or 0,
            n.left, n.sold and "sold here" or "not sold here", n.pattern and " (pattern)" or "")
    end
    for _, l in ipairs(vendor.lines) do
        out[#out + 1] = ("  offer %s x%d (item %d, slot %d, stack %d) %d copper"):format(l.name, l.count, l.itemID,
            l.index, l.stack, l.cost)
    end
    for _, l in ipairs(vendor.patterns) do
        out[#out + 1] = ("  pattern %s (item %d, slot %d) %d copper"):format(Buying.PatternText(l), l.itemID, l.index, l.cost)
    end
    out[#out + 1] = ("offer: %d lines, total %d copper, %d patterns, money %s"):format(#vendor.lines, vendor.total,
        #vendor.patterns, tostring(money()))
    local key = table.concat(out, "\n")
    if key == vendor.lastTrace then return end
    vendor.lastTrace = key
    for _, line in ipairs(out) do trace("%s", line) end
end

-- One line when the button's window, state or reason changes.
local function traceState(host, reason)
    if not Buying.Tracing() then return end
    local state = host and ("%s: button %s, %s"):format(host.kind or "window", reason and "OFF" or "ON",
        reason or "can buy")
        or "no vendor window shows the shop yet (Daylight UI's vendor and MerchantFrame both not visible); no button"
    if state == vendor.lastState then return end
    vendor.lastState = state
    trace("%s", state)
end

-- Shows the button while a vendor window shows the shop. It is on when this merchant
-- sells what the guides want and the player can pay; its tooltip says why when it is off.
-- It fades with that window, as its child.
function Buying.Update()
    local b = vendor.button
    local host = Buying.open and Buying.Host() or nil
    if Buying.open and (vendor.dirty or vendor.look) and (host or Buying.Tracing()) then
        local look = not vendor.dirty
        vendor.dirty, vendor.look = false, false
        if not look or vendor.pickKey ~= pickKey() or heldMoved() or livesMoved() then
            Buying.Rebuild(vendor.fresh)
        end
    end
    vendor.fresh = nil
    if not host then
        vendor.host = nil
        if Buying.open then traceState(nil) end
        if b then b:Hide() end
        return
    end
    local reason = Buying.Reason()
    traceState(host, reason)
    b = b or makeButton()
    if not (vendor.host and vendor.host.window == host.window and vendor.host.on == host.on) then
        vendor.host = host
        place(b, host)
    end
    S.SetEnabled(b, reason == nil)
    b:SetAlpha(1)
    b:Show()
    if GameTooltip:GetOwner() == b then tooltip(b) end
end

-- Something the button reads changed: the merchant came or went, or an item name arrived.
function Buying.Changed()
    vendor.dirty = true
    Buying.Update()
end

-- Something the offer reads may have changed: the bags or a plan. One look on the next
-- frame covers a craft's burst of events, after the panel's redraw has the new plan and
-- pick; it rebuilds only when an input moved.
function Buying.Look()
    vendor.look = true
    CP:Soon("buying", Buying.Update)
end

-- The merchant's list changed: a rebuild now when its stock did, else a look.
function Buying.StockChanged()
    local stock = Buying.Stock()
    vendor.fresh = stock
    if Buying.unresolved or not sameStock(stock, vendor.stock) then
        vendor.dirty = true
        return Buying.Update()
    end
    Buying.Look()
end

-- Seconds between looks at what the player holds while the merchant is open. The bags
-- can change without an event that reaches here in time (a sale to this vendor).
Buying.HELD_EVERY = 0.5

-- Daylight UI's window shows a frame or more after MERCHANT_SHOW: a check every
-- CHECK_EVERY while the merchant is open finds it, and follows its fade.
local watch = CreateFrame("Frame")
watch:Hide()
watch:SetScript("OnUpdate", function(_, dt)
    vendor.since = vendor.since + (dt or 0)
    vendor.heldAge = (vendor.heldAge or 0) + (dt or 0)
    if vendor.since < Buying.CHECK_EVERY then return end
    vendor.since = 0
    if vendor.heldAge >= Buying.HELD_EVERY then
        vendor.heldAge = 0
        vendor.look = true
    end
    if Buying.unresolved then vendor.dirty = true end
    if pickKey() ~= vendor.pickKey then vendor.dirty = true end
    Buying.Update()
end)
Buying.watch = watch

function Buying.Button() return vendor.button end
