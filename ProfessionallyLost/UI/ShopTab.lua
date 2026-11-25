local _, CP = ...
if CP.stopped then return end

-- Shop tab, for Buy-and-power-level: everything the queue needs that the player still
-- has to buy, with prices and what's left to spend. It doesn't buy anything; when the
-- player buys at the auction house, Purchases counts it and the row ticks. Each list
-- runs to the profession's current cap. All mode merges every profession's list.

local S = CP.Style
local Queue = CP.Queue
local Scan = CP.Scan
local ROW_H = 22
local SCAN_H = 24   -- room under the list for the scan status line

local ShopTab = {}
CP.ShopTab = ShopTab

local ui = {}
ShopTab.ui = ui   -- read by tests

-- Materials for skill `p.skill` to `target`, with have (bags, bank, mail, just bought),
-- price each and the cost still to buy; short ones first.
function ShopTab.Rows(guide, entries, priceFn)
    local rows = {}
    for _, m in ipairs(Queue.Materials(entries)) do
        local item = guide.items and guide.items[m.itemID]
        m.have = CP.Purchases.Have(m.itemID)
        m.price, m.source = priceFn(m.itemID, item)
        -- The price's own source names the row; a price function that gives none leaves
        -- the stock flag to say.
        m.vendor = m.source == "vendor" or (m.source == nil and item and item[2] == true) or false
        m.mail = CP.Purchases.InMail(m.itemID) + CP.Purchases.Bought(m.itemID)
        m.left = math.max(0, m.need - m.have)
        m.others = CP.Shared.Others(CP.Shared.KeyOf(guide), m.itemID)
        rows[#rows + 1] = m
    end
    return Queue.SortMaterials(rows)
end

-- Rows of several professions merged by item: needs add up, the rest is the item's.
function ShopTab.Merge(lists)
    local out, byID = {}, {}
    for _, rows in ipairs(lists) do
        for _, m in ipairs(rows) do
            local got = byID[m.itemID]
            if got then
                got.need = got.need + m.need
                got.left = math.max(0, got.need - got.have)
                got.first = math.min(got.first or math.huge, m.first or math.huge)
            else
                local copy = {}
                for k, v in pairs(m) do copy[k] = v end
                copy.others = nil   -- every guide's share is in the sum already
                byID[m.itemID] = copy
                out[#out + 1] = copy
            end
        end
    end
    return Queue.SortMaterials(out)
end

-- Save what the Shop list needs, so a purchase made with the panel closed can say how
-- far along it is.
local function remember(rows)
    local needs = {}
    for _, m in ipairs(rows) do needs[m.itemID] = m.need end
    CP.charDB.shopNeeds = needs
end

-- Items whose name the list waits on. The item event can come while the name still reads
-- nil, and an item the game already holds raises no second one, so the list asks again on a
-- timer (as the guide card does) and redraws once the name reads.
local nameWatch = {}
ShopTab.NAME_RETRY, ShopTab.NAME_TRIES = 1, 15

local function watchName(id, tries)
    if tries == nil then
        if nameWatch[id] then return end
        nameWatch[id] = true
        tries = 0
    end
    C_Timer.After(ShopTab.NAME_RETRY, function()
        local shown = ui.content and ui.content:IsShown()
        if shown and not C_Item.GetItemNameByID(id) and tries < ShopTab.NAME_TRIES then
            CP.RequestItem(id)
            return watchName(id, tries + 1)
        end
        nameWatch[id] = nil
        if shown then CP.Panel.Changed() end
    end)
end

local function nameOf(id)
    local name = CP.ItemName(id)
    if not name then watchName(id) end
    return name or "…"
end

-- A row's texts: its count, cost and tag columns.
local function countText(m) return ("%d / %d"):format(math.min(m.have, m.need), m.need) end
local function costText(m)
    return m.left == 0 and "" or (m.price and CP.Pricing.Format(m.price * m.left) or "no price")
end
local function tagText(m)
    return m.vendor and "vendor" or (m.source == "auction" and "auction") or (m.mail > 0 and "in mail") or (m.others and #m.others > 0 and "shared") or ""
end

-- The row's pieces across, left to right: icon, name, tag, check, count, cost, with
-- their gaps; `list` is the scroll bar's room right of the rows.
ShopTab.COLUMNS = { icon = 6 + 16 + 6, gap = 4, check = 14, edge = 6, list = 12 }
ui.costW = 64
ui.tagW = 40

-- Every tag a row can carry, so the tag column fits the widest of them.
local TAG_WORDS = { "vendor", "auction", "in mail", "shared" }

-- Measures `rows` in the current font: the cost column takes its widest text.
function ShopTab.Measure(rows)
    local costs = {}
    for i, m in ipairs(rows) do costs[i] = costText(m) end
    ui.costW = S.Widest(costs, "small")
    ui.tagW = S.Widest(TAG_WORDS, "tiny")
end

local function initRow(r, m)
    local C = ShopTab.COLUMNS
    if not r.name then
        r:EnableMouse(true)
        S.Rule(r)
        r.icon = r:CreateTexture(nil, "ARTWORK")
        r.icon:SetSize(16, 16)
        r.icon:SetPoint("LEFT", 6, 0)
        r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        r.cost = S.Column(S.Text(r, "small", S.color.muted))
        r.cost:SetPoint("RIGHT", -C.edge, 0)
        r.cost:SetJustifyH("RIGHT")
        r.count = S.Column(S.Text(r, "small"))
        r.count:SetPoint("RIGHT", r.cost, "LEFT", -C.edge, 0)
        r.count:SetJustifyH("RIGHT")
        r.check = S.Check(r, C.check)
        r.check:SetPoint("RIGHT", r.count, "LEFT", -C.gap, 0)
        r.tag = S.Column(S.Text(r, "tiny", S.color.muted))
        r.tag:SetJustifyH("LEFT")
        r.tag:SetPoint("RIGHT", r.check, "LEFT", -C.gap, 0)
        -- One line; the item tooltip on hover shows a long name whole.
        r.name = S.OneLine(S.Text(r, "body"))
        r.name:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
        r.name:SetPoint("RIGHT", r.tag, "LEFT", -C.gap, 0)
        r:SetScript("OnEnter", function(self)
            local row = self.row
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink("item:" .. row.itemID)
            GameTooltip:Show()
        end)
        r:SetScript("OnLeave", GameTooltip_Hide)
    end
    r.row = m
    r.icon:SetTexture(C_Item.GetItemIconByID(m.itemID))
    r.name:SetText(nameOf(m.itemID))
    local done = m.left == 0
    r.check:SetShown(done)
    r.count:SetText(countText(m))
    r.count:SetTextColor(unpack(done and S.color.good or (m.have > 0 and S.color.warn or S.color.bad)))
    r.cost:SetWidth(ui.costW)
    r.cost:SetText(costText(m))
    r.tag:SetWidth(ui.tagW)
    r.tag:SetText(tagText(m))
end

-- Every row is one line high.
function ShopTab.RowHeight() return ROW_H end
ShopTab.InitRow = initRow

local function build(c)
    ui.summary = S.Text(c, "body", S.color.label)
    ui.summary:SetPoint("TOPLEFT", 2, -4)
    ui.summary:SetPoint("RIGHT", -2, 0)
    ui.summary:SetWordWrap(true)

    ui.total = S.Text(c, "head", S.color.title)
    ui.total:SetPoint("TOPLEFT", ui.summary, "BOTTOMLEFT", 0, -4)
    ui.total:SetPoint("RIGHT", -2, 0)
    ui.total:SetWordWrap(true)

    local scroll = CreateFrame("Frame", nil, c, "WowScrollBoxList")
    scroll:SetPoint("TOPLEFT", ui.total, "BOTTOMLEFT", 0, -8)
    scroll:SetPoint("BOTTOMRIGHT", -12, 0)
    local view = CreateScrollBoxListLinearView()
    view:SetElementExtent(ROW_H)
    view:SetElementInitializer("Frame", initRow)
    ui.scrolling = S.ListScroll("Shop list", scroll, view, c)
    ui.scroll = scroll

    ui.empty = S.Text(c, "body", S.color.muted)
    ui.empty:SetPoint("TOP", scroll, "TOP", 0, -20)
    ui.empty:SetWidth(240)
    ui.empty:SetJustifyH("CENTER")

    ui.content = c
    ui.scanText = S.Text(c, "small", S.color.muted)
    ui.scanText:SetPoint("BOTTOMLEFT", 2, 4)
    ui.scanText:SetPoint("RIGHT", -2, 0)
    ui.scanText:SetWordWrap(true)
end

-- The scan status line sits at the Shop tab's foot in Buy-and-power-level. The scan
-- itself starts from ProfLost Scan on the auction house window (UI/ScanButton.lua).
local function scanShown()
    return CP.db ~= nil and CP.db.collect == false
end

-- Said after the status line while the auction house is shut.
ShopTab.SCAN_HINT = "scan at the auction house"

-- The Shop tab's status line follows the scan.
local function scanSaid()
    local progress = Scan.ProgressText()
    if progress then return progress end
    local last = Scan.LastTime()
    local now = GetServerTime and GetServerTime() or time()
    local said = last and ("Last scan %s ago"):format(CP.Pricing.FormatAge(math.max(0, now - last)))
        or "No price scan yet"
    if not Scan.open then said = said .. "  ·  " .. ShopTab.SCAN_HINT end
    return said
end

-- The line wraps when the window is narrow; the list stops above it.
local function scanRow()
    if not ui.scanText then return end
    local shown = scanShown()
    ui.scanText:SetShown(shown)
    if shown then ui.scanText:SetText(scanSaid()) end
    local h = shown and ui.scanText:GetStringHeight() or 0
    local room = shown and math.max(SCAN_H, math.ceil(type(h) == "number" and h or 0) + 8) or 0
    ui.scroll:SetPoint("BOTTOMRIGHT", -12, room)
end

Scan.OnChange(scanRow)
ShopTab.Changed = scanRow

-- One plan's rows to the current cap, the queue entries, and the target.
local function rowsFor(live)
    local guide, p = live.guide, live.prof
    local target = Queue.Target(guide, p.skill, nil, p.max)
    local entries = target and Queue.Build(guide, p.skill, p.max, target, live.plan, live.learned) or {}
    return ShopTab.Rows(guide, entries, CP.Pricing.Get), entries, target
end
ShopTab.RowsFor = rowsFor

-- All mode: every guided profession's list, merged.
local function refreshAll()
    local lists, training = {}, 0
    for _, live in ipairs(CP.Window.AllLives()) do
        if live.guide then
            local rows, entries = rowsFor(live)
            lists[#lists + 1] = rows
            local _, _, fees = Queue.Cost(live.guide, entries, {}, CP.Pricing.Get)
            training = training + fees
        end
    end
    local rows = ShopTab.Merge(lists)
    remember(rows)
    local total, done, missing = training, 0, false
    for _, m in ipairs(rows) do
        if m.left == 0 then done = done + 1 end
        if m.left > 0 then
            if m.price then total = total + m.price * m.left else missing = true end
        end
    end
    ui.summary:SetText("Shopping for every profession, each to its current cap")
    local text = ("%s%s left  ·  %d of %d done"):format(missing and "over " or "~", CP.Pricing.Format(total),
        done, #rows)
    if training > 0 then text = text .. ("  ·  %s training"):format(CP.Pricing.Format(training)) end
    ui.total:SetText(#rows > 0 and text or "")
    ui.empty:SetText(#rows == 0 and "Nothing to buy." or "")
    ui.empty:SetShown(#rows == 0)
    ShopTab.Measure(rows)
    ui.scroll:SetDataProvider(CreateDataProvider(rows), true)
end

local function refresh()
    scanRow()
    if CP.Window.Mode() == "all" then return refreshAll() end
    local live = CP.Window.Live()
    local guide = live and live.guide
    if not guide then
        ui.summary:SetText("")
        ui.total:SetText("")
        ui.empty:SetText(live and CP.Guide.NoGuideText(live.prof) or "No profession to guide yet.")
        ui.empty:Show()
        ui.scroll:SetDataProvider(CreateDataProvider({}))
        return
    end
    local p = live.prof
    local rows, entries, target = rowsFor(live)
    remember(rows)

    local done, short = 0, 0
    for _, m in ipairs(rows) do
        if m.left == 0 then done = done + 1 else short = short + 1 end
    end
    local total, _, training, missing = Queue.Cost(guide, entries, rows, CP.Pricing.Get)
    ui.summary:SetText(("Shopping for skill %d to %d"):format(p.skill, target or p.skill))
    local text = ("%s%s left  ·  %d of %d done"):format(missing and "over " or "~", CP.Pricing.Format(total),
        done, #rows)
    if training > 0 then text = text .. ("  ·  %s training"):format(CP.Pricing.Format(training)) end
    ui.total:SetText(#rows > 0 and text or "")
    ui.empty:SetText(#rows == 0 and "Nothing to buy for this target." or "")
    ui.empty:SetShown(#rows == 0)
    ShopTab.Measure(rows)
    ui.scroll:SetDataProvider(CreateDataProvider(rows), true)  -- keep the scroll position
end

-- Purchases of something on the list: one chat line per item with the summed count, said
-- once a burst of them (a vendor's stacks, one after another) goes quiet.
ShopTab.BOUGHT_QUIET, ShopTab.BOUGHT_MOST = 0.6, 2
local boughtTotal, boughtOrder = {}, {}

local function sayBought()
    local order = boughtOrder
    local total = boughtTotal
    boughtTotal, boughtOrder = {}, {}
    for _, itemID in ipairs(order) do
        local need = CP.charDB.shopNeeds and CP.charDB.shopNeeds[itemID]
        if need then
            CP:Print(("bought %d %s (%d / %d)"):format(total[itemID], nameOf(itemID),
                math.min(CP.Purchases.Have(itemID), need), need))
        end
    end
end

CP.Purchases.OnPurchase(function(itemID, quantity)
    local need = CP.charDB.shopNeeds and CP.charDB.shopNeeds[itemID]
    if not need then return end
    if not boughtTotal[itemID] then boughtOrder[#boughtOrder + 1] = itemID end
    boughtTotal[itemID] = (boughtTotal[itemID] or 0) + quantity
    CP:Later("shopBought", ShopTab.BOUGHT_QUIET, ShopTab.BOUGHT_MOST, sayBought)
    CP:Soon("shopRefresh", function() CP.Panel:Refresh() end)
end)

CP.Panel:AddTab("shop", "Shop", build, refresh, function() return not CP.db or CP.db.collect == false end)
