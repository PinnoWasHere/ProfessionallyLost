local _, CP = ...
if CP.stopped then return end

-- The guide window: title bar, tab strip and one content frame per tab. Settings live
-- in Daylight UI's options (UI/Plugin.lua).
-- Tabs register themselves with Panel:AddTab. Window.lua places and shows it.

local S = CP.Style
local Panel = { tabs = {}, order = {} }
CP.Panel = Panel

-- The window is at least BASE_WIDTH wide, wider when its title bar or its guide rows need
-- it in the current font, up to MAX_WIDTH times the text size. The player's corner grip
-- sets any width from the gathering panel's up (Panel.ApplyWidth).
local WIDTH = 356
local TITLE_H = S.HEADER.height   -- two lines and their padding
local TAB_H = 24
local TAB_PAD, TAB_GAP = 12, 2   -- tabs fit their labels; padding gives way before the font does

local f = CreateFrame("Frame", "ProfLost_Panel", UIParent)
f:SetWidth(WIDTH)
f:SetClampedToScreen(true)
f:EnableMouse(true)
f:SetFrameStrata(S.WINDOW_STRATA)
f:SetToplevel(true)
f:Hide()
S.Shell(f, TITLE_H + TAB_H + 2)
Panel.frame = f
Panel.WIDTH, Panel.TITLE_H, Panel.TAB_H = WIDTH, TITLE_H, TAB_H
Panel.BASE_WIDTH, Panel.MAX_WIDTH = WIDTH, 520

-- The title bar's insets are Style.HEADER, which the gathering panel's header shares, and
-- its icons sit Daylight UI's Win.HEADER_ICON_GAP (6 px) apart. Our close is a 12 px X in
-- a 16 px box.
local LOGO, LOGO_GAP = 18, 5
local TITLE_INSET, TITLE_EDGE, TITLE_GAP = S.HEADER.left, S.HEADER.right, 6
local TITLE_LEFT = TITLE_INSET + LOGO + LOGO_GAP
Panel.TITLE_INSET, Panel.TITLE_EDGE, Panel.TITLE_GAP, Panel.TITLE_LEFT = TITLE_INSET, TITLE_EDGE, TITLE_GAP, TITLE_LEFT

-- Line 1 is the title, line 2 the addon's version in the note colour, each where
-- Style.HEADER puts it. The logo and the controls centre on the two lines.
local title = S.HeaderText(f, 1, S.color.title)
local logo = f:CreateTexture(nil, "ARTWORK")
logo:SetSize(LOGO, LOGO)
logo:SetPoint("TOPLEFT", f, "TOPLEFT", TITLE_INSET, -(S.HEADER.mid - LOGO / 2))
logo:SetTexture(CP.MEDIA .. "Icon")
title:SetPoint("TOPLEFT", f, "TOPLEFT", TITLE_LEFT, -S.HEADER.top)
title:SetJustifyH("LEFT")
title:SetText(CP.Gradient("Professionally Lost"))
Panel.titleText = "Professionally Lost"
Panel.logo, Panel.title = logo, title

-- The TOC's version, as written there ("0.2.65-beta"), or nil.
function Panel.VersionText()
    if not (C_AddOns and C_AddOns.GetAddOnMetadata) then return nil end
    local ok, v = pcall(C_AddOns.GetAddOnMetadata, CP.name, "Version")
    return ok and type(v) == "string" and v ~= "" and v or nil
end

-- Header line 2: "Preview: Enchanting 150" in the warning ink while a profession preview
-- is on (UI/Preview.lua), else the version.
function Panel.SubText()
    local marker = CP.Preview and CP.Preview.Marker()
    if marker then return S.Hex(S.color.warn) .. marker .. "|r" end
    return Panel.VersionText() or ""
end

local version = S.HeaderText(f, 2, S.color.muted)
version:SetPoint("TOPLEFT", f, "TOPLEFT", TITLE_LEFT, -S.HEADER.line2Top)
version:SetJustifyH("LEFT")
version:SetText(Panel.VersionText() or "")
Panel.version = version

-- Title bar controls sit right to left in the order they are added, each while its
-- `shown()` says so. Panel.LayoutTitle places them. The title text takes the room left
-- of them.
Panel.titleButtons = {}

local BUG_SIZE = 16

-- Daylight UI's bug icon through the icon button; ProfLost's own beetle without it.
local bugBtn = S.IconButton(f, { icon = "ui-bug.png", own = CP.MEDIA .. "Bug",
    size = BUG_SIZE, box = BUG_SIZE, onClick = function() CP.BugReport.Show() end })
Panel.bugButton = bugBtn

-- The body sits under the tab row. Folded, the row keeps only its right-hand buttons
-- (the View switch and the profession dropdown), so the body sits there too.
local BODY_TOP, BODY_PAD = TITLE_H + TAB_H + 8, 10
local FOLD_TOP = BODY_TOP
Panel.BODY_TOP, Panel.FOLD_TOP, Panel.BODY_PAD = BODY_TOP, FOLD_TOP, BODY_PAD

local body = CreateFrame("Frame", nil, f)
body:SetPoint("TOPLEFT", BODY_PAD, -BODY_TOP)
body:SetPoint("BOTTOMRIGHT", -BODY_PAD, BODY_PAD)
Panel.body = body

-- A font string's width for `text` in its own font. Tests stand in for the font engine here.
function Panel.TextWidth(fs, text)
    if text then fs:SetText(text) end
    return math.ceil(tonumber(fs:GetUnboundedStringWidth()) or 0)
end

local function paintTabs()
    for _, k in ipairs(Panel.order) do
        local b = Panel.tabs[k].button
        local on = k == Panel.current
        if b.look then
            b.look.Pick(on, on and b.clicked)
            b.clicked = nil
        else
            b.label:SetTextColor(unpack(on and S.color.title or S.color.muted))
            b.underline:SetShown(on)
        end
    end
end

-- The picked tab keeps its look when Daylight UI repaints (StyleChanged at login, an
-- accent change) and each time the window shows.
S.OnRepaint(paintTabs)
f:HookScript("OnShow", paintTabs)

-- Folded, the window shows the Guide view; open, the current tab.
Panel.FOLD_TAB = "guide"

local function showContent()
    local key = Panel.folded and Panel.FOLD_TAB or Panel.current
    for _, k in ipairs(Panel.order) do
        Panel.tabs[k].content:SetShown(k == key)
    end
end

-- The tab that hid while current, and the tab it handed over to (layoutTabs): it takes over
-- again when it shows, unless a tab was picked in between.
local handed

local function selectTab(key)
    handed = nil
    Panel.current = key
    showContent()
    paintTabs()
    Panel:Refresh()
end

-- Picks tab `key` as a click on it does (the tour's Shop card). False while it doesn't show.
function Panel.SelectTab(key)
    local t = Panel.tabs[key]
    if not t or (t.visible and not t.visible()) then return false end
    if Panel.current ~= key then selectTab(key) end
    return true
end

local TAB_Y = TITLE_H

-- The title text takes the room the controls leave: the full title when it fits, else
-- TITLE_SHORT, else nothing. It never truncates.
Panel.TITLE_FULL, Panel.TITLE_SHORT = "Professionally Lost", "ProfLost"

local function titleWidth(text)
    return Panel.TextWidth(title, CP.Gradient(text))
end

local function fitTitle(right)
    -- Both lines keep their header sizes through Daylight UI's font repaints.
    S.Pin(title)
    S.Pin(version)
    local room = Panel.WIDTH - right - TITLE_LEFT - TITLE_GAP
    local text = titleWidth(Panel.TITLE_FULL) <= room and Panel.TITLE_FULL or Panel.TITLE_SHORT
    local w = titleWidth(text)
    Panel.titleText = text
    title:SetWidth(math.max(1, w))
    title:SetShown(w <= room)
    -- The version always shows, as wide as its text. A profession preview's marker takes
    -- its place.
    version:SetText(Panel.SubText())
    version:SetWidth(math.max(1, Panel.TextWidth(version)))
end

-- The width the title bar needs for its own controls and the full title.
function Panel.TitleNeed()
    local x = TITLE_EDGE
    for _, t in ipairs(Panel.titleButtons) do
        if t.reserve or not t.shown or t.shown() then x = x + t.button:GetWidth() + TITLE_GAP end
    end
    local keep = title:GetText()
    local w = titleWidth(Panel.TITLE_FULL)
    title:SetText(keep or "")
    return x + TITLE_LEFT + TITLE_GAP + math.max(w, Panel.TextWidth(version))
end

-- Width -------------------------------------------------------------------------------

-- What each part of the window needs across, by key ("title", "row", "guide").
Panel.needs = {}

function Panel.SetNeed(key, px)
    Panel.needs[key] = px
end

-- The widest the window grows: MAX_WIDTH at the text size.
function Panel.Cap()
    return math.max(Panel.BASE_WIDTH, math.floor(Panel.MAX_WIDTH * S.TextScale() + 0.5))
end

-- The width the window's parts need, at most Panel.Cap: the width it takes by itself.
function Panel.AutoWidth()
    local w = Panel.BASE_WIDTH
    for _, px in pairs(Panel.needs) do w = math.max(w, math.ceil(px)) end
    return math.min(w, Panel.Cap())
end

-- The player's width from the corner grip (Window.lua sets it), or nil.
Panel.PlayerWidth = function() return nil end

-- The player's width when there is one, else the parts' width. The grip keeps the
-- player's at least the gathering panel's width (Window.LeastWidth); the parts give way.
function Panel.WantedWidth()
    return Panel.PlayerWidth() or Panel.AutoWidth()
end

-- Sizes the window to Panel.WantedWidth. True when the width changed.
function Panel.ApplyWidth()
    local w = Panel.WantedWidth()
    if w == Panel.WIDTH then return false end
    Panel.WIDTH = w
    f:SetWidth(w)
    return true
end

-- Places the title bar controls right to left, then fits the title left of them.
function Panel.LayoutTitle()
    local x = TITLE_EDGE
    for _, t in ipairs(Panel.titleButtons) do
        local on = not t.shown or t.shown()
        t.button:SetShown(on)
        if on then
            local h = t.button:GetHeight()
            t.button:ClearAllPoints()
            t.button:SetPoint("TOPRIGHT", f, "TOPRIGHT", -x, -math.floor(S.HEADER.mid - h / 2))
            x = x + t.button:GetWidth() + TITLE_GAP
        elseif t.reserve then
            x = x + t.button:GetWidth() + TITLE_GAP
        end
    end
    fitTitle(x)
end

-- `reserve` keeps the button's slot while it is hidden, so the buttons to its left and the
-- window width do not change as it shows and hides.
function Panel:AddTitleButton(button, shown, reserve)
    self.titleButtons[#self.titleButtons + 1] = { button = button, shown = shown, reserve = reserve }
    Panel.LayoutTitle()
end
Panel:AddTitleButton(bugBtn)

-- Tabs left to right, skipping hidden ones; a hidden current tab hands over to the first.
-- Each tab is its label plus the same padding, so the labels sit evenly apart.
local function labelWidth(t)
    return math.ceil(tonumber(t.button.label:GetUnboundedStringWidth()) or 0)
end

-- Folded (Window.lua): no tab row, and the body shows the Guide view's header and
-- current step. The current tab comes back on unfolding.
Panel.folded = false

function Panel.SetFolded(on)
    on = on and true or false
    if Panel.folded == on then return end
    Panel.folded = on
    body:SetPoint("TOPLEFT", BODY_PAD, -(on and FOLD_TOP or BODY_TOP))
    showContent()
    Panel.Layout()
end

-- The folded window's height: title bar, then what the Guide view needs.
function Panel.FoldedHeight()
    local need = CP.GuideTab and CP.GuideTab.FoldedHeight and CP.GuideTab.FoldedHeight() or 0
    return FOLD_TOP + need + BODY_PAD
end

-- The unfolded window's height for the current tab: title bar, tab row, then what the
-- tab's content needs. Nil when the tab can't say (Panel:SetTabNeed).
function Panel.OpenHeight()
    local t = Panel.current and Panel.tabs[Panel.current]
    local need = t and t.need and t.need()
    return need and BODY_TOP + need + BODY_PAD or nil
end

-- `need()` gives the body height tab `key` needs to show everything without scrolling.
function Panel:SetTabNeed(key, need)
    if self.tabs[key] then self.tabs[key].need = need end
end

-- Buttons on the right of the tab row, right to left in the order added, each while its
-- `shown()` says so (Panel:AddRowButton). They stay while the window is folded.
Panel.rowButtons = {}
local ROW_EDGE, ROW_GAP = 8, 4
local TAB_MIN_PAD = 4
Panel.ROW_EDGE, Panel.ROW_GAP = ROW_EDGE, ROW_GAP

function Panel:AddRowButton(button, shown)
    self.rowButtons[#self.rowButtons + 1] = { button = button, shown = shown }
end

local function shownTabs()
    local list = {}
    for _, k in ipairs(Panel.order) do
        local t = Panel.tabs[k]
        if not t.visible or t.visible() then list[#list + 1] = t end
    end
    return list
end

-- The tabs' least width, labels at TAB_MIN_PAD, from the row's left edge. Folded, the
-- row has no tabs.
function Panel.TabsLeast(unfolded)
    if Panel.folded and not unfolded then return 8 end
    local list, w = shownTabs(), 8
    for _, t in ipairs(list) do w = w + labelWidth(t) + 2 * TAB_MIN_PAD end
    return w + TAB_GAP * math.max(0, #list - 1)
end

-- Places the row's right-hand buttons; returns the width they take with their gap.
local function layoutRow()
    local x = ROW_EDGE
    for _, r in ipairs(Panel.rowButtons) do
        local on = not r.shown or r.shown()
        r.button:SetShown(on)
        if on then
            local h = r.button:GetHeight()
            r.button:ClearAllPoints()
            r.button:SetPoint("TOPRIGHT", f, "TOPRIGHT", -x, -(TITLE_H + math.floor((TAB_H - h) / 2)))
            x = x + r.button:GetWidth() + ROW_GAP
        end
    end
    return x - ROW_EDGE
end

local function layoutTabs()
    local tabs, text = shownTabs(), 0
    for _, t in ipairs(tabs) do text = text + labelWidth(t) end
    local right = layoutRow()
    local room = Panel.WIDTH - 8 - ROW_EDGE - right - TAB_GAP * math.max(0, #tabs - 1)
    local pad = #tabs > 0 and math.min(TAB_PAD, math.max(0, math.floor((room - text) / (2 * #tabs)))) or 0

    local x, first = 8, nil
    for _, k in ipairs(Panel.order) do
        local t = Panel.tabs[k]
        local shown = not t.visible or t.visible()
        t.button:SetShown(shown and not Panel.folded)
        if shown then
            local w = labelWidth(t) + 2 * pad
            t.button:ClearAllPoints()
            t.button:SetPoint("TOPLEFT", f, "TOPLEFT", x, -TAB_Y)
            t.button:SetWidth(w)
            x = x + w + TAB_GAP
            first = first or k
        elseif Panel.current == k then
            Panel.current = nil
            handed = { from = k }
        end
    end
    if not Panel.current and first then
        Panel.current = first
        if handed then handed.to = first end
        showContent()
        paintTabs()
    elseif handed and handed.to == Panel.current and Panel.tabs[handed.from].visible() then
        Panel.current, handed = handed.from, nil
        showContent()
        paintTabs()
    end
end

-- Re-lays the tab row (a tab's visibility changed).
function Panel.Layout() layoutTabs() end

-- Add a tab. `build(content)` runs once; `refresh(content)` runs whenever data changes;
-- `visible()`, when given, says whether the tab shows now.
function Panel:AddTab(key, label, build, refresh, visible)
    local index = #self.order + 1

    local b = CreateFrame("Button", nil, f)
    b:SetHeight(TAB_H)
    S.Interactive(b)
    b.label = S.Text(b, "body", S.color.muted, true)
    b.label:SetPoint("CENTER")
    b.label:SetJustifyH("CENTER")
    b.label:SetText(label)
    b.look = S.TabLook(b, b.label)
    if not b.look then b.underline = S.Mark(b) end
    b:SetScript("OnClick", function() b.clicked = true; selectTab(key) end)

    local content = CreateFrame("Frame", nil, body)
    content:SetAllPoints()
    content:Hide()
    build(content)

    self.tabs[key] = { button = b, content = content, refresh = refresh, visible = visible }
    self.order[index] = key
    if index == 1 then selectTab(key) end
    layoutTabs()
end

-- A hidden window lays out its tab row and notes the redraw; the next show makes it.
Panel.dirty = false

function Panel:Refresh()
    if not f:IsShown() then
        Panel.dirty = true
        return layoutTabs()
    end
    Panel.dirty = false
    if CP.Window then CP.Window.Chrome() end
    layoutTabs()
    Panel.LayoutTitle()
    local key = self.folded and Panel.FOLD_TAB or self.current
    if not key then return end
    local t = self.tabs[key]
    if t and t.refresh then t.refresh(t.content) end
    if CP.Window then CP.Window.Fit() end
end

local function catchUp()
    if Panel.dirty then Panel:Refresh() end
end
f:HookScript("OnShow", function()
    if Panel.dirty then CP:Soon("shown", catchUp) end
end)

-- Opens Daylight UI's options on this plugin's page (page id "<module>.<page>"): the
-- launchers' right-click, /proflost settings and /dui pl. Without it, chat says where they are.
Panel.SETTINGS_PAGE = "ProfLost.general"

function Panel:OpenSettings()
    local dui = _G.DaylightUI
    local options = dui and dui.OptionsPanel
    if options and type(options.Show) == "function" and pcall(options.Show, Panel.SETTINGS_PAGE) then return end
    CP:Print("Professionally Lost's settings are in Daylight UI's options: type /dui, then pick ProfLost under Plugins.")
end

-- Profession, bag or item data changed: redraw the visible tab.
local function redraw() Panel:Refresh() end
local function dataChanged() CP:Soon("refresh", redraw) end
Panel.Changed = dataChanged
-- A profession window opened, switched or shut, whichever addon draws it: the guide's craft
-- buttons follow.
CP:On("TRADE_SKILL_SHOW", dataChanged)
CP:On("TRADE_SKILL_DATA_SOURCE_CHANGED", dataChanged)
CP:On("TRADE_SKILL_LIST_UPDATE", dataChanged)
CP:On("TRADE_SKILL_CLOSE", dataChanged)
CP:On("BAG_UPDATE_DELAYED", dataChanged)
-- A name ProfLost asked for arrived. Names trickle in over many frames: one redraw a burst.
Panel.NAMES_QUIET, Panel.NAMES_MOST = 0.3, 1
CP:On("ProfLost_ITEM_LOADED", function() CP:Later("names", Panel.NAMES_QUIET, Panel.NAMES_MOST, dataChanged) end)
CP:On("ProfLost_SKILLS", dataChanged)          -- a skill-up: the current step may be done
CP:On("NEW_RECIPE_LEARNED", dataChanged)    -- a trained or read recipe changes the plan
CP:On("ProfLost_FONT", dataChanged)            -- the font or text size: widths measure again
-- The gathering guides' zones are built: redraw if the guide tab was waiting for them.
CP:On(CP.GatherGuide.WARM.signal, function()
    if CP.GuideTab and CP.GuideTab.waitingZones then
        CP.GuideTab.waitingZones = false
        dataChanged()
    end
end)
