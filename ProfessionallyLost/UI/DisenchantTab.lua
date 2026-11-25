local _, CP = ...
if CP.stopped then return end

-- Disenchant tab, shown while Enchanting is open: the greens and blues in the bags
-- the player can disenchant, best first. The big button disenchants the head of the
-- queue, one item per press, then moves to the next. Items can be ignored, and each
-- row warns when selling it would be worth more gold than disenchanting. Such an item
-- never becomes the head by itself: the player picks its row, and the button then says
-- "Disenchant anyway". Gear another guide made for Enchanting's dust is marked, leads the
-- queue and is never told "sell"; its row still shows both values.

local S = CP.Style
local DE = CP.Disenchant
local ROW_H = 34
local ICON = 14   -- the warning and ignore glyphs

local DisenchantTab = {}
CP.DisenchantTab = DisenchantTab
DisenchantTab.LABEL_PAD = 16   -- the big button's label insets, both sides

-- Row icons: Daylight UI's close and warning glyphs by path while it is loaded, else the
-- game's stop button and alert.
DisenchantTab.ICONS = {
    daylight = { ignore = "ui-close.png", warn = "ui-meter-avoidable.png" },
    own = { ignore = "Interface\\Buttons\\UI-StopButton", warn = "Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew" },
}

-- A row's pieces across: the icon with its gaps, and the warning and ignore icons with
-- theirs; `list` is the scroll bar's room right of the rows.
DisenchantTab.COLUMNS = { icon = 6 + 24 + 6, right = 4 + 14 + 4 + 14 + 6, list = 12 }

local ui = {}
local nextItem   -- { bag, slot, itemID } the player picked to go next, this session
local showIgnored = false
local casting = false   -- a disenchant is under way; the button waits for it

local function ignored()
    CP.charDB.deIgnore = CP.charDB.deIgnore or {}
    return CP.charDB.deIgnore
end

local function nameOf(id)
    return CP.ItemName(id) or "…"
end

local function enchantingSkill()
    local info = CP.Professions.SkillLine(DE.ENCHANTING)
    return info and (info.rank or 0) + (info.modifier or 0) or 0
end

-- "~1.6 Strange Dust, ~0.3 Lesser Magic Essence"
function DisenchantTab.YieldText(yield)
    local parts = {}
    for i, y in ipairs(yield) do
        if i > 2 then break end
        parts[#parts + 1] = ("~%.1f %s"):format(y.count, nameOf(y.item))
    end
    return table.concat(parts, ", ")
end

-- "Disenchant 24s · Vendor 45s · Auction 1g"
function DisenchantTab.ValueText(a)
    local fmt = CP.Pricing.Format
    local parts = {}
    if a.de then parts[#parts + 1] = "Disenchant " .. DE.Money(a) end
    if a.vendor and a.vendor > 0 then parts[#parts + 1] = "Vendor " .. fmt(a.vendor) end
    if a.ah then parts[#parts + 1] = "Auction " .. fmt(a.ah) end
    return table.concat(parts, " · ")
end

-- A row's mark for gear another guide made for Enchanting's dust.
DisenchantTab.DUST_MARK = "Made for Enchanting"

-- Gear the other guides made for Enchanting's dust: { [itemID] = count }. A guide's step
-- counts while it is the saved plan's current step (Plan.Committed), its recipe takes
-- Enchanting's credit (Shared.CreditFor) and the player has made some of it on that step.
-- The count is the crafts made on the step, never more than the step asked for.
function DisenchantTab.MadeForDust()
    local out = {}
    if not (CP.Shared.ForEnchanting() and CP.Plan and CP.Plan.Committed) then return out end
    local skills = { [DE.ENCHANTING] = true }
    for key, guide in pairs(CP.Guides or {}) do
        local c = key ~= DE.ENCHANTING and CP.Plan.Committed(key)
        local f = c and c.current and c.steps and c.steps[c.current]
        local r = f and guide.recipes[f[3]]
        local made = c and math.min(c.made or 0, f and f[9] or 0) or 0
        if r and r.makes and made > 0 then
            local credit = CP.Shared.CreditFor(key, CP.db.collect, skills)
            local cost = 1e9
            if credit and credit(f[3], r, cost) < cost then
                out[r.makes] = (out[r.makes] or 0) + made * (r.yield or 1)
            end
        end
    end
    return out
end

-- The queue head: the picked item while it's still in place (a "worth more sold" one
-- included), else the first that isn't ignored and isn't worth more sold.
function DisenchantTab.Head(queue)
    if nextItem then
        for _, it in ipairs(queue) do
            if it.bag == nextItem.bag and it.slot == nextItem.slot and it.itemID == nextItem.itemID then return it end
        end
        nextItem = nil
    end
    for _, it in ipairs(queue) do
        if not it.ignored and it.advice.verdict ~= "sell" then return it end
    end
end

-- True when only items worth more sold are left to disenchant: the player must pick one.
local function onlySell(queue)
    local any = false
    for _, it in ipairs(queue or {}) do
        if not it.ignored then
            if it.advice.verdict ~= "sell" then return false end
            any = true
        end
    end
    return any
end

-- Point the secure button at `head`: cast Disenchant, then target the bag item. The
-- game's secure button only uses target-bag/target-slot while a spell is waiting for
-- an item target, so a cast that fails can never equip the item. Out of combat only;
-- while a disenchant casts, the button does nothing.
local function arm(head)
    local b = ui.button
    if InCombatLockdown() then
        b.label:SetText("In combat")
        return
    end
    -- A profession preview never aims: its click only says why (build's PostClick).
    local aim = not casting and not CP.Professions.preview and head
    b:SetAttribute("type", aim and "spell" or nil)
    b:SetAttribute("spell", aim and tostring(DE.SPELL) or nil)
    b:SetAttribute("target-bag", aim and head.bag or nil)
    b:SetAttribute("target-slot", aim and head.slot or nil)
    if casting then
        b.label:SetText("Disenchanting…")
        S.SetEnabled(b, false)
    elseif head then
        -- The item's name when it fits; the list's top row names it either way. An item
        -- worth more sold says so: its row was picked on purpose.
        local verb = head.advice and head.advice.verdict == "sell" and "Disenchant anyway" or "Disenchant"
        local full = verb .. ": " .. head.name
        local room = CP.Panel.WIDTH - 2 * CP.Panel.BODY_PAD - DisenchantTab.LABEL_PAD
        b.label:SetText(CP.Panel.TextWidth(b.label, full) <= room and full or verb)
        S.SetEnabled(b, true)
    elseif onlySell(ui.queue) then
        b.label:SetText("Pick an item to disenchant")
        S.SetEnabled(b, false)
    else
        b.label:SetText("Nothing to disenchant")
        S.SetEnabled(b, false)
    end
end

-- Make `item` the next to disenchant.
function DisenchantTab.Pick(item)
    nextItem = { bag = item.bag, slot = item.slot, itemID = item.itemID }
    CP.Panel:Refresh()
end

-- Never disenchant an item again, or take it back.
function DisenchantTab.ToggleIgnore(itemID)
    ignored()[itemID] = not ignored()[itemID] or nil
    CP.Panel:Refresh()
end

function DisenchantTab.ShowIgnored(on)
    showIgnored = on
    CP.Panel:Refresh()
end

function DisenchantTab.RowTip(self)
    local it = self.item
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetHyperlink(it.link or ("item:" .. it.itemID))
    for _, id in ipairs(it.advice and it.advice.missing or {}) do
        GameTooltip:AddLine("No price for " .. nameOf(id), unpack(S.color.warn))
    end
    GameTooltip:Show()
end

-- A row's two texts: the item with its item level, and its value and yield. Gear made for
-- dust leads its detail with DUST_MARK in the accent ink.
local function rowTexts(it)
    local mark = it.forDust and ("%s%s|r  ·  "):format(S.Hex(S.color.accent), DisenchantTab.DUST_MARK) or ""
    return ("%s  %s%d|r"):format(it.name, S.Hex(S.color.muted), it.ilvl),
        mark .. DisenchantTab.ValueText(it.advice) .. "  ·  " .. DisenchantTab.YieldText(it.yield)
end

-- Measures `queue` in the current font: a row whose detail is too long for it breaks
-- onto more lines (it.lines) in a taller row (it.height). The name stays one line.
function DisenchantTab.Measure(queue)
    local C = DisenchantTab.COLUMNS
    local room = CP.Panel.WIDTH - 2 * CP.Panel.BODY_PAD - C.list - C.icon - C.right
    for _, it in ipairs(queue) do
        local _, detail = rowTexts(it)
        local b = S.Measure(detail, "small") > room and S.Lines(detail, "small", room) or { detail }
        it.lines = { detail = #b > 1 and table.concat(b, "\n") or nil }
        it.height = ROW_H + (#b - 1) * S.LineHeight("small")
    end
end

local function rowHeight(it) return it and it.height or ROW_H end

local function initRow(r, it)
    DisenchantTab.lastRow = r
    if not r.name then
        S.Interactive(r)
        S.Rule(r)
        r.icon = r:CreateTexture(nil, "ARTWORK")
        r.icon:SetSize(24, 24)
        r.icon:SetPoint("TOPLEFT", 6, -(ROW_H - 24) / 2)
        r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        local icons = S.Daylight() and DisenchantTab.ICONS.daylight or DisenchantTab.ICONS.own
        r.ignore = S.IconButton(r, { icon = DisenchantTab.ICONS.daylight.ignore, own = DisenchantTab.ICONS.own.ignore,
            size = ICON, onClick = function(self) DisenchantTab.ToggleIgnore(self:GetParent().item.itemID) end })
        -- A hit box wider than the glyph spills evenly round it, so the glyph keeps its place.
        local spill = ((r.ignore:GetWidth() or ICON) - ICON) / 2
        r.ignore:SetPoint("RIGHT", -6 + spill, 0)
        r.warn = r:CreateTexture(nil, "OVERLAY")
        r.warn:SetSize(ICON, ICON)
        r.warn:SetPoint("RIGHT", r.ignore, "LEFT", -4 + spill, 0)
        r.warn:SetTexture(S.Daylight() and S.Media(icons.warn) or icons.warn)
        r.tinted = S.Daylight() ~= nil
        -- One line; the item tooltip on hover shows a long name whole.
        r.name = S.OneLine(S.Text(r, "body"))
        r.name:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 6, 1)
        r.name:SetPoint("RIGHT", r.warn, "LEFT", -4, 0)
        r.detail = S.Text(r, "small", S.color.muted)
        r.detail:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -2)
        r.detail:SetPoint("RIGHT", r.warn, "LEFT", -4, 0)
        r.detail:SetWordWrap(true)
        r:SetScript("OnClick", function(self) DisenchantTab.Pick(self.item) end)
        r:SetScript("OnEnter", DisenchantTab.RowTip)
        r:SetScript("OnLeave", GameTooltip_Hide)
    end
    r.item = it
    r.icon:SetTexture(it.icon)
    r.icon:SetDesaturated(it.ignored)
    local name, detail = rowTexts(it)
    local lines = it.lines or {}
    r.name:SetText(name)
    local qr, qg, qb = C_Item.GetItemQualityColor(it.quality)
    if qr then r.name:SetTextColor(qr, qg, qb) end
    r.detail:SetText(lines.detail or detail)
    local sell = it.advice.verdict == "sell"
    r.warn:SetShown(sell)
    -- Daylight UI's glyphs are white: the warning takes the warn ink. The ignore button
    -- inks its own glyph.
    if r.tinted then
        local w = S.color.warn
        r.warn:SetVertexColor(w[1], w[2], w[3])
    end
    r.detail:SetTextColor(unpack(sell and S.color.warn or S.color.muted))
    if ui.head == it then r.name:SetTextColor(unpack(S.color.accent)) end
end

-- The secure button lives under UIParent, never inside or anchored to the panel: a
-- protected frame there would make the panel protected, and the game would block
-- hiding it in combat. Out of combat it sits over `slot` by screen position; a state
-- driver hides it the moment combat starts.
local laid = {}

local function follow()
    local b, slot = ui.button, ui.slot
    if not (b and slot) or InCombatLockdown() then return end
    local left, top, w = slot:GetLeft(), slot:GetTop(), slot:GetWidth()
    if not (slot:IsVisible() and left and top and w) then
        if b:IsShown() then b:Hide() end
        return
    end
    local ks, kb = slot:GetEffectiveScale(), b:GetEffectiveScale()
    local panel = CP.Panel.frame
    local strata, level, h = panel:GetFrameStrata(), panel:GetFrameLevel() + 20, slot:GetHeight()

    -- The layout is redone only when something it depends on changed or the button hid.
    if b:IsShown() and laid.b == b and laid.left == left and laid.top == top and laid.w == w and laid.h == h
        and laid.ks == ks and laid.kb == kb and laid.strata == strata and laid.level == level then
        return
    end
    local k = ks / kb
    b:SetFrameStrata(strata)
    b:SetFrameLevel(level)
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left * k, top * k)
    b:SetSize(w * k, h * k)
    b:Show()
    laid.b, laid.left, laid.top, laid.w, laid.h = b, left, top, w, h
    laid.ks, laid.kb, laid.strata, laid.level = ks, kb, strata, level
end
DisenchantTab.Follow = follow

local function build(c)
    local slot = CreateFrame("Frame", nil, c)
    slot:SetHeight(28)
    slot:SetPoint("TOPLEFT", 0, -2)
    slot:SetPoint("TOPRIGHT", 0, -2)
    slot:SetScript("OnUpdate", follow)   -- runs only while the tab shows
    slot:SetScript("OnHide", follow)
    ui.slot = slot

    local b = CreateFrame("Button", "ProfLost_DisenchantButton", UIParent,
        "SecureActionButtonTemplate, SecureHandlerStateTemplate")
    b:Hide()
    b:SetAttribute("_onstate-combat", [[ if newstate == "on" then self:Hide() end ]])
    RegisterStateDriver(b, "combat", "[combat] on; off")
    -- One action per click: on release only.
    b:RegisterForClicks("AnyUp")
    b:SetAttribute("useOnKeyDown", false)
    b:SetScript("PostClick", function()
        if CP.Preview then CP.Preview.Refuse("disenchant") end
    end)
    S.Dress(b)
    b.label:ClearAllPoints()
    b.label:SetPoint("LEFT", 8, 0)
    b.label:SetPoint("RIGHT", -8, 0)
    b.label:SetJustifyH("CENTER")
    b.label:SetWordWrap(false)
    ui.button = b

    ui.summary = S.Text(c, "small", S.color.muted)
    ui.summary:SetPoint("TOPLEFT", slot, "BOTTOMLEFT", 2, -6)
    ui.summary:SetPoint("RIGHT", -2, 0)

    local scroll = CreateFrame("Frame", nil, c, "WowScrollBoxList")
    scroll:SetPoint("TOPLEFT", ui.summary, "BOTTOMLEFT", -2, -6)
    scroll:SetPoint("BOTTOMRIGHT", -12, 22)
    local view = CreateScrollBoxListLinearView()
    view:SetElementExtent(ROW_H)
    -- A row whose texts wrap is taller (DisenchantTab.Measure).
    if view.SetElementExtentCalculator then
        view:SetElementExtentCalculator(function(_, it) return rowHeight(it) end)
    end
    view:SetElementInitializer("Button", initRow)
    ui.scrolling = S.ListScroll("Disenchant list", scroll, view, c)
    ui.scroll = scroll

    ui.toggle = DisenchantTab.MakeToggle(c)
end

-- The "Show ignored items" link along the bottom of `c`.
function DisenchantTab.MakeToggle(c)
    local t = S.Link(c, "small")
    t:SetPoint("BOTTOMLEFT", 2, 0)
    t:SetScript("OnClick", function() DisenchantTab.ShowIgnored(not showIgnored) end)
    return t
end

-- The bag items, and a preview's sample greens after them.
local function items()
    local list = DE.Bags()
    if CP.Preview and CP.Professions.preview then
        for _, it in ipairs(CP.Preview.DisenchantSamples()) do list[#list + 1] = it end
    end
    return list
end

local function refresh()
    local queue = DE.Queue(items(), enchantingSkill(), ignored(), CP.Pricing.Auction, CP.Pricing.Auction,
        nameOf, showIgnored, DisenchantTab.MadeForDust())
    ui.queue = queue
    ui.head = DisenchantTab.Head(queue)
    arm(ui.head)

    local count, sell, hidden = 0, 0, 0
    for _, it in ipairs(queue) do
        if not it.ignored then
            count = count + 1
            if it.advice.verdict == "sell" then sell = sell + 1 end
        end
    end
    for _ in pairs(ignored()) do hidden = hidden + 1 end
    if count == 0 then
        ui.summary:SetText("No greens or blues in your bags that you can disenchant.")
    else
        ui.summary:SetText(("%d to disenchant%s"):format(count,
            sell > 0 and ("  ·  %d worth more sold (marked)"):format(sell) or ""))
    end
    ui.toggle.SetLabel(showIgnored and "Hide ignored items" or ("Show ignored items (%d)"):format(hidden))
    ui.toggle:SetShown(hidden > 0)
    DisenchantTab.Measure(queue)
    ui.scroll:SetDataProvider(CreateDataProvider(queue), true)
end

-- After each disenchant, and when the bags change, re-read and move to the next.
local function castState(on)
    return function(_, unit, _, spellID)
        if unit == "player" and spellID == DE.SPELL then
            casting = on
            if not on then CP:Soon("disenchantNext", function() CP.Panel:Refresh() end) end
            if ui.button then arm(ui.head) end
        end
    end
end
CP:On("UNIT_SPELLCAST_START", castState(true))
for _, event in ipairs({ "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED",
    "UNIT_SPELLCAST_STOP" }) do
    CP:On(event, castState(false))
end

-- The tab's state, for tests: the queue, its head and the button.
function DisenchantTab.State()
    return ui.queue, ui.head, ui.button, ui.summary and ui.summary:GetText()
end

DisenchantTab.InitRow, DisenchantTab.Arm = initRow, arm
-- Combat over: the button can take its spell again. Only the Disenchant tab draws it.
CP:On("PLAYER_REGEN_ENABLED", function()
    if CP.Panel.current == "disenchant" then CP.Panel.Changed() end
end)

-- A profession preview shows the tab for an Enchanting preview alone.
local function enchantingOpen()
    local pv = CP.Professions.preview
    if pv then return pv.line == DE.ENCHANTING end
    local p = CP.Professions.Current()
    if not p then return false end
    for _, id in ipairs(p.ids or {}) do
        if id == DE.ENCHANTING then return true end
    end
    return p.name == "Enchanting"
end

CP.Panel:AddTab("disenchant", "Disenchant", build, refresh, enchantingOpen)
