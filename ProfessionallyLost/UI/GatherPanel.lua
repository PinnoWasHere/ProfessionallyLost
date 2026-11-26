local _, CP = ...
if CP.stopped then return end

-- The gathering checklist's panel. Attached (CP.db.gatherAttached, default on), it slides
-- out from behind the guide window on the side the gatherSide setting names, and the
-- window and the panel share one shell, as Daylight UI's meter and minimap do: the shell
-- widens as the panel comes out, and the panel takes the window's height. A fold tab
-- tucked behind the shell's edge on that side opens and folds it; it shows while the
-- mouse is near. Attached, it is the window's child, so it shows, hides and fades with
-- it. CP.db.gatherOpen keeps it open or folded.
--
-- Detached, the sheet is its own window: its own shell, close button, padlock, mover
-- (ProfLost_GatherAnchor, key gatherpanel) and fade. It shows unless closed
-- (CP.db.gatherPanelClosed) and hides in combat by its own setting.
-- It keeps the size the player drags its corner grip to (CP.db.gatherSize), its rows
-- scroll inside it, and its anchor is always its exact rect.

local S, Panel = CP.Style, CP.Panel
local panel = Panel.frame

local GatherPanel = {
    SLIDE = 0.3,           -- seconds the panel takes to slide out or back
    TAB = { 14, 34 },      -- the fold tab's width and height
    ARROW = 12,            -- the tab's chevron
    ARROW_COLOR = { 0.55, 0.55, 0.58 },
    TUCK = 2,              -- how far the tab sits behind the shell's border
    REACH = 10,            -- past the tab, how near the mouse must come to show it
    HOVER_EVERY = 0.05,    -- seconds between mouse checks
    FADE = 0.12,           -- seconds the tab takes to fade in or out
    MIN_H = 120,           -- attached without a window height: the panel's least height
    WIDTH = Panel.WIDTH,   -- attached, and a first detach's width
    SIZE_MIN = { 220, 160 }, -- detached: the grip's least size, the header and about four rows
    MAX_W = 500,           -- detached: the grip's widest; the tallest is the screen
    GRIP_LIFT = 20,        -- the grip's frame levels above the sheet
    LEVEL = 5,             -- detached: the sheet's least frame level, its shell's skin sits below it
    GAP = 8,               -- detached, first placed this far beside the guide window
    CLOSE = 16,            -- the detached panel's close box
    CLOSE_GAP = 6,         -- between the detached controls and the header's icons
    LOCK = 16,             -- the detached panel's padlock
    GUIDE = 16,            -- the detached panel's open-the-guide button
    ICON_GAP = 6,          -- between the detached controls, Daylight UI's Win.HEADER_ICON_GAP
    MOVER = "gatherpanel", -- Daylight UI's mover key and label for the detached panel
    MOVER_LABEL = "Gathering window",
    managed = { mover = false, fade = false },
    opened = false,        -- opened in a fight while hideInCombat hides it; stays for that fight
}
CP.GatherPanel = GatherPanel

local DAYLIGHT = "DaylightUI"   -- the addon's global; its Motion.Tween drives the slide
local KEY, TAB_KEY = "proflost:gather", "proflost:gathertab"
local CHEVRON = CP.MEDIA .. "Chevron"
local RULE = { 1, 1, 1, 0.06 }
local RULE_INSET = S.CONTENT_EDGE   -- the seam stops this far short of the top and bottom

-- The tab's border: half the player's border width, at least 3 px, as Daylight UI's own tab.
local function tabBorder(px) return math.max(3, math.floor((px or 0) * 0.5 + 0.5)) end

-- The shared shell: behind the window and the panel, as wide as both and as tall as the taller.
local shell = CreateFrame("Frame", nil, panel)
S.Shell(shell)
GatherPanel.shell = shell

-- A faint rule where the window meets the panel.
local seam = shell:CreateTexture(nil, "OVERLAY")
seam:SetWidth(1)
seam:SetColorTexture(RULE[1], RULE[2], RULE[3], RULE[4])
GatherPanel.seam = seam

-- The clip grows from the window's edge and shows as much of the sheet as has slid out.
local clip = CreateFrame("Frame", nil, panel)
clip:SetClipsChildren(true)
clip:SetWidth(0.01)
GatherPanel.clip = clip

local sheet = CreateFrame("Frame", "ProfLost_GatherPanel", clip)
sheet:SetWidth(GatherPanel.WIDTH)
sheet:EnableMouse(true)

-- Its own shell shows only while it stands detached.
S.Shell(sheet)
S.ShellShown(sheet, false)
S.LineShown(sheet, false)
GatherPanel.sheet = sheet

local BODY_TOP = Panel.BODY_PAD + 4
local body = CreateFrame("Frame", nil, sheet)
body:SetPoint("TOPLEFT", Panel.BODY_PAD, -BODY_TOP)
body:SetPoint("BOTTOMRIGHT", -Panel.BODY_PAD, Panel.BODY_PAD)
GatherPanel.body = body
CP.GatherList.Mount(body)

-- The checklist's header starts at the sheet's top and keeps Style.HEADER's insets from its
-- edges, as the guide's title bar does from the window's.
local H = S.HEADER
CP.GatherList.SetHeadInsets(H.left - Panel.BODY_PAD, H.right - Panel.BODY_PAD, BODY_TOP)

-- Detached, the sheet hangs from this anchor's top-left at the anchor's size, so /dui
-- unlock's box is the panel. Daylight UI's mover moves and scales the anchor.
local anchor = CreateFrame("Frame", "ProfLost_GatherAnchor", UIParent)
anchor:SetSize(GatherPanel.WIDTH, CP.DEFAULTS.windowHeight)
anchor:SetClampedToScreen(true)
anchor:SetMovable(true)
GatherPanel.anchor = anchor

-- The detached panel's own controls at the right end of the checklist's header, right to
-- left: close, padlock. They sit in the room the header keeps clear
-- (GatherPanel.HeadRoom), Daylight UI's header icon gap apart.
local head = CP.GatherList.head
local closeBtn = S.Close(head, function() GatherPanel.Close() end, GatherPanel.CLOSE)
closeBtn:Hide()
GatherPanel.closeButton = closeBtn

local guideBtn
local lockBtn = S.LockButton(head, GatherPanel.LOCK, function() return GatherPanel.Locked() end, function()
    CP.db.gatherLocked = not GatherPanel.Locked()
    CP.Window.GatherEscSync()
end)
lockBtn:SetPoint("RIGHT", closeBtn, "LEFT", -GatherPanel.ICON_GAP, 0)
lockBtn:Hide()
GatherPanel.lockButton = lockBtn

-- The guide window's button, left of the padlock. It opens the guide window while it is
-- shut and closes it while it stands open, so a second press undoes the first. Daylight UI's
-- header icon button with its journal icon.
GatherPanel.GUIDE_ICONS = { daylight = "ui-micro-journal.png", own = CP.MEDIA .. "Icon" }
GatherPanel.GUIDE_LABELS = { open = "Open the guide", close = "Close the guide" }   -- its tooltip and its menu entry

-- True while the guide window stands open.
function GatherPanel.GuideOpen()
    return panel:IsShown()
end

-- The button and its menu entry show while the panel stands on its own.
function GatherPanel.GuideButtonShown()
    return CP.db ~= nil and not GatherPanel.Attached()
end

-- What a press does now, by whether the guide window stands open.
function GatherPanel.GuideLabel()
    return GatherPanel.GuideOpen() and GatherPanel.GUIDE_LABELS.close or GatherPanel.GUIDE_LABELS.open
end

function GatherPanel.GuideTip(owner)
    GameTooltip:SetOwner(owner, "ANCHOR_BOTTOM")
    GameTooltip:SetText(GatherPanel.GuideLabel(), 1, 1, 1, 1, true)
    GameTooltip:Show()
end

-- Opens the guide window when it is shut, closes it when it stands open.
function GatherPanel.ToggleGuide()
    if GatherPanel.GuideOpen() then CP.Window.Close() else CP.Window.Open() end
    if guideBtn and GameTooltip:GetOwner() == guideBtn then GatherPanel.GuideTip(guideBtn) end
end

guideBtn = S.IconButton(head, { icon = GatherPanel.GUIDE_ICONS.daylight, own = GatherPanel.GUIDE_ICONS.own,
    size = GatherPanel.GUIDE, box = GatherPanel.GUIDE, onClick = function() GatherPanel.ToggleGuide() end,
    tip = function(self) GatherPanel.GuideTip(self) end })
guideBtn:SetPoint("RIGHT", lockBtn, "LEFT", -GatherPanel.ICON_GAP, 0)
guideBtn:Hide()
GatherPanel.guideButton = guideBtn

-- The header room the detached controls take, past the route icons.
function GatherPanel.HeadRoom()
    local G = GatherPanel
    return G.CLOSE_GAP + G.GUIDE + G.ICON_GAP + G.LOCK + G.ICON_GAP + G.CLOSE
end
closeBtn:SetPoint("RIGHT", head, "TOPRIGHT", GatherPanel.HeadRoom(), -H.mid)

-- The fold tab, tucked behind the shell's border on the panel's side.
local tab = CreateFrame("Button", nil, panel)
tab:SetSize(GatherPanel.TAB[1] + GatherPanel.TUCK, GatherPanel.TAB[2])
S.TabShell(tab, tabBorder)
tab.icon = tab:CreateTexture(nil, "OVERLAY")
tab.icon:SetTexture(S.Daylight() and S.Media("ui-chevron.png") or CHEVRON)
tab.icon:SetSize(GatherPanel.ARROW, GatherPanel.ARROW)
tab.icon:SetPoint("CENTER")
local function shade(over)
    local c = over and S.color.accent or GatherPanel.ARROW_COLOR
    tab.icon:SetVertexColor(c[1], c[2], c[3])
end
shade(false)
tab:SetScript("OnClick", function() GatherPanel.Toggle() end)
tab:SetScript("OnEnter", function() shade(true) end)
tab:SetScript("OnLeave", function() shade(false) end)
GatherPanel.tab = tab

function GatherPanel.IsOpen()
    return CP.db ~= nil and CP.db.gatherOpen ~= false
end

-- True while the panel slides out of the guide window; false while it stands on its own.
function GatherPanel.Attached()
    return not (CP.db and CP.db.gatherAttached == false)
end

-- True when the player closed the detached panel. Saved, like the guide's windowClosed.
function GatherPanel.Closed()
    return CP.db ~= nil and CP.db.gatherPanelClosed == true
end

-- True while its own "Hide in combat" hides the detached panel.
local function combatHidden()
    return CP.Window ~= nil and CP.Window.GatherCombatHidden()
end

-- True when the detached panel should show now.
function GatherPanel.Wanted()
    if GatherPanel.Closed() then return false end
    return GatherPanel.opened or not combatHidden()
end

-- True when the detached panel's own padlock is shut: its header drags nothing.
function GatherPanel.Locked()
    return CP.db ~= nil and CP.db.gatherLocked == true
end

-- True while the checklist is on screen. Attached: open beside the visible guide window.
-- Detached: its own window shows.
function GatherPanel.Showing()
    if not GatherPanel.Attached() then return sheet:IsVisible() end
    return GatherPanel.IsOpen() and panel:IsVisible()
end

-- The side the panel slides out on: the gatherSide setting, left or right of the guide.
-- Anything else (a save not carried over yet) is the default side.
function GatherPanel.Side()
    local side = CP.db and CP.db.gatherSide
    if side == "left" or side == "right" then return side end
    return CP.DEFAULTS.gatherSide
end

local function motion()
    local addon = _G[DAYLIGHT]
    local M = type(addon) == "table" and addon.Motion
    return type(M) == "table" and type(M.Tween) == "function" and M or nil
end

-- The fold tab's fade --------------------------------------------------------------

-- Hidden until the mouse is over the window, the panel or the tab, then eased in.
GatherPanel.tabAlpha = 0
tab:SetAlpha(0)
local near = false

local function paintTab(a)
    GatherPanel.tabAlpha = a
    tab:SetAlpha(a)
end

-- True while the mouse is over the shell, the tab, or a tab's width past the shell's edge.
function GatherPanel.MouseNear()
    local reach = GatherPanel.TAB[1] + GatherPanel.REACH
    local left = GatherPanel.side == "left"
    return shell:IsMouseOver(0, 0, left and -reach or 0, left and 0 or reach) or tab:IsMouseOver() or false
end

-- Eases the tab in or out as the mouse comes near or leaves; `snap` jumps there.
function GatherPanel.WatchTab(snap)
    local now = tab:IsVisible() and GatherPanel.MouseNear() or false
    if now == near and not snap then return end
    near = now
    local M = motion()
    local to = now and 1 or 0
    if M and not snap then
        M.Tween(TAB_KEY, GatherPanel.tabAlpha, to, GatherPanel.FADE, paintTab)
    else
        if M then M.Tween(TAB_KEY, to, to, 0, paintTab) end
        paintTab(to)
    end
end

-- The tab's child, so the check runs only while the tab shows.
local hover = CreateFrame("Frame", nil, tab)
local since = 0
hover:SetScript("OnUpdate", function(_, dt)
    since = since + (dt or 0)
    if since < GatherPanel.HOVER_EVERY then return end
    since = 0
    GatherPanel.WatchTab(false)
end)
tab:SetScript("OnShow", function() GatherPanel.WatchTab(true) end)

-- Heights --------------------------------------------------------------------------

-- Room from the detached panel's top down to the screen's bottom edge, in the panel's own
-- units, or nil while its anchor has no place yet. The clamp keeps a placed top above
-- the bottom edge, so a top at 0 or below is no place.
function GatherPanel.Room()
    local top = anchor:GetTop()
    if type(top) ~= "number" or top <= 0 then return nil end
    return top
end

local function anchorScale()
    local s = anchor:GetScale()
    return (type(s) == "number" and s > 0) and s or 1
end

-- The screen's width and height in the anchor's units, or nil before the screen has a size.
local function screen()
    local w, h = UIParent:GetWidth(), UIParent:GetHeight()
    if type(w) ~= "number" or type(h) ~= "number" or w <= 0 or h <= 0 then return nil end
    local s = anchorScale()
    return w / s, h / s
end

-- Detached sizes -------------------------------------------------------------------

-- `w`, `h` within the grip's bounds: at least SIZE_MIN, at most MAX_W wide and the
-- screen's height, in whole pixels.
function GatherPanel.ClampSize(w, h)
    local lo = GatherPanel.SIZE_MIN
    local _, top = screen()
    w = math.max(lo[1], math.min(GatherPanel.MAX_W, w))
    h = math.max(lo[2], top and math.min(top, h) or h)
    return math.floor(w + 0.5), math.floor(h + 0.5)
end

-- A first detach's size: the guide window's width, as tall as the list it holds (the
-- window's unfolded height before it has rows), at most that height and the room down
-- to the screen's bottom.
function GatherPanel.DefaultSize()
    local most = CP.Window and CP.Window.ExpandedHeight() or CP.DEFAULTS.windowHeight
    local room = GatherPanel.Room()
    if room then most = math.min(most, room) end
    local lines = CP.GatherList.Drawn()
    local h = #lines > 0 and CP.GatherList.NeedHeight() + 2 * Panel.BODY_PAD + 4 or most
    return GatherPanel.ClampSize(GatherPanel.WIDTH, math.min(most, h))
end

-- The detached panel's size: the player's (CP.db.gatherSize), else the default. `keep`
-- saves the default, so the rows it holds later never change it.
function GatherPanel.Size(keep)
    local s = CP.db and CP.db.gatherSize
    if type(s) == "table" and type(s[1]) == "number" and type(s[2]) == "number" then
        return GatherPanel.ClampSize(s[1], s[2])
    end
    local w, h = GatherPanel.DefaultSize()
    if keep and CP.db then CP.db.gatherSize = { w, h } end
    return w, h
end

-- The panel's height. Attached: the guide window's, so one shell fits both and a folded
-- window leaves no empty block; past that its rows scroll. Detached: its saved size.
function GatherPanel.Height()
    local h = panel:GetHeight() or 0
    if not GatherPanel.Attached() then return select(2, GatherPanel.Size(true)) end
    if h > 0 then return h end
    local need = CP.GatherList.NeedHeight() + 2 * Panel.BODY_PAD + 4
    local most = CP.Window and CP.Window.ExpandedHeight() or CP.DEFAULTS.windowHeight
    return math.max(GatherPanel.MIN_H, math.min(most, need))
end

-- Sizes the shell for where the slide is: the window's width plus what has slid out, at
-- the window's height. Detached, it frames the window alone.
local function shape()
    local p = GatherPanel.Attached() and GatherPanel.p or 0
    shell:SetSize(Panel.WIDTH + p * GatherPanel.WIDTH, panel:GetHeight() or 0)
    seam:SetShown(p > 0)
    seam:SetAlpha(p)
end

local function equal(a, b) return math.abs((a or 0) - b) < 0.5 end

-- The detached panel and its anchor at `w` x `h`, the list as wide as the body. True
-- when either changed.
local function sizeTo(w, h)
    local same = equal(sheet:GetWidth(), w) and equal(sheet:GetHeight(), h)
        and equal(anchor:GetWidth(), w) and equal(anchor:GetHeight(), h)
    anchor:SetSize(w, h)
    S.ClampTop(anchor, h)
    sheet:SetSize(w, h)
    CP.GatherList.SetWidth(w - 2 * Panel.BODY_PAD)
    return not same
end

-- The anchor at the detached panel's size. Daylight UI's mover places it by its centre,
-- so it takes this size before the mover places it.
function GatherPanel.SizeAnchor()
    if not CP.db then return end
    local w, h = GatherPanel.Size(not GatherPanel.Attached())
    anchor:SetSize(w, h)
    S.ClampTop(anchor, h)
end

-- Fits the panel. True when its size changed. Attached: the window's height. Detached:
-- its saved size, which its rows never change; they scroll inside it.
function GatherPanel.Fit()
    if not GatherPanel.Attached() then return sizeTo(GatherPanel.Size(true)) end
    local h = GatherPanel.Height()
    if math.abs((sheet:GetHeight() or 0) - h) < 0.5 then return false end
    clip:SetHeight(h)
    sheet:SetHeight(h)
    shape()
    return true
end

-- Sliding --------------------------------------------------------------------------

GatherPanel.p = 0   -- how far out the panel is: 0 folded, 1 open

local function apply(p)
    GatherPanel.p = p
    clip:SetWidth(math.max(p * GatherPanel.WIDTH, 0.01))
    clip:SetAlpha(p)
    if GatherPanel.Attached() then sheet:SetShown(GatherPanel.goal == 1 or p > 0) end
    shape()
end

-- Without Daylight UI: the same ease-out over the same time, on our own frame.
local driver = CreateFrame("Frame")
local function ownTween(from, to, dur)
    local t = 0
    apply(from)
    driver:SetScript("OnUpdate", function(self, dt)
        t = t + dt
        local u = math.min(1, t / dur)
        apply(from + (to - from) * (1 - (1 - u) ^ 3))
        if u >= 1 then self:SetScript("OnUpdate", nil) end
    end)
end

-- Slides toward `goal`; `glide` false jumps there. A slide already heading there carries on.
local function slide(goal, glide)
    if GatherPanel.goal == goal then return shape() end
    GatherPanel.goal = goal
    driver:SetScript("OnUpdate", nil)
    local M = motion()
    if not glide then
        -- A zero-length tween ends one in flight.
        if M then return M.Tween(KEY, goal, goal, 0, apply) end
        return apply(goal)
    end
    if M then
        M.Tween(KEY, GatherPanel.p, goal, GatherPanel.SLIDE, apply)
    else
        ownTween(GatherPanel.p, goal, GatherPanel.SLIDE)
    end
end

-- Layout ---------------------------------------------------------------------------

-- The chevron points the way the panel moves next. Its art points down.
local function pointArrow()
    local right = GatherPanel.side == "right"
    if GatherPanel.IsOpen() then right = not right end
    tab.points = right and "right" or "left"
    tab.icon:SetRotation((right and 1 or -1) * math.pi / 2)
end

local function place(side)
    GatherPanel.side = side
    local left = side == "left"
    local tuck = GatherPanel.TUCK
    shell:ClearAllPoints()
    clip:ClearAllPoints()
    sheet:ClearAllPoints()
    tab:ClearAllPoints()
    seam:ClearAllPoints()
    tab.icon:ClearAllPoints()
    if left then
        shell:SetPoint("TOPRIGHT", panel, "TOPRIGHT")
        clip:SetPoint("TOPRIGHT", panel, "TOPLEFT")
        sheet:SetPoint("TOPLEFT", clip, "TOPLEFT")
        tab:SetPoint("RIGHT", shell, "LEFT", tuck, 0)
        seam:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -RULE_INSET)
        seam:SetPoint("BOTTOM", shell, "BOTTOM", 0, RULE_INSET)
        tab.icon:SetPoint("CENTER", tab, "CENTER", -tuck / 2, 0)
    else
        shell:SetPoint("TOPLEFT", panel, "TOPLEFT")
        clip:SetPoint("TOPLEFT", panel, "TOPRIGHT")
        sheet:SetPoint("TOPRIGHT", clip, "TOPRIGHT")
        tab:SetPoint("LEFT", shell, "RIGHT", -tuck, 0)
        seam:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, -RULE_INSET)
        seam:SetPoint("BOTTOM", shell, "BOTTOM", 0, RULE_INSET)
        tab.icon:SetPoint("CENTER", tab, "CENTER", tuck / 2, 0)
    end
end

-- The shell sits under the window's own drawing, the tab under the shell's border.
local function stack()
    local level = panel:GetFrameLevel()
    shell:SetFrameLevel(math.max(0, level - 1))
    tab:SetFrameLevel(math.max(0, level - 2))
    S.Restack()
end

-- Detached ----------------------------------------------------------------------------

hooksecurefunc(anchor, "SetScale", function()
    if not GatherPanel.Attached() then sheet:SetScale(anchorScale()) end
    GatherPanel.Refit()
end)

-- The detached panel fits its size again once the screen may have shrunk under it: a
-- move, a scale, a new UI scale or screen size. A new size redraws the list.
local refitting = false
function GatherPanel.Refit()
    if refitting or not CP.db or GatherPanel.Attached() or not sheet:IsShown() then return end
    refitting = true
    local changed = GatherPanel.Fit()
    refitting = false
    if changed then CP.GatherList.Changed() end
end
hooksecurefunc(anchor, "SetPoint", function() GatherPanel.Refit() end)
hooksecurefunc(anchor, "StopMovingOrSizing", function() GatherPanel.Refit() end)
CP:On("UI_SCALE_CHANGED", function() GatherPanel.Refit() end)
CP:On("DISPLAY_SIZE_CHANGED", function() GatherPanel.Refit() end)

-- Beside the guide window, on the panel's side: where a first detach puts it.
function GatherPanel.Beside()
    local w = CP.Window.anchor
    if GatherPanel.Side() == "left" then return { "TOPRIGHT", w, "TOPLEFT", -GatherPanel.GAP, 0 } end
    return { "TOPLEFT", w, "TOPRIGHT", GatherPanel.GAP, 0 }
end

-- True while the anchor still hangs from the guide window: the panel was never placed.
local function unplaced()
    local _, rel = anchor:GetPoint(1)
    return rel == nil or rel == CP.Window.anchor
end
GatherPanel.Unplaced = unplaced

-- At login: the anchor at the panel's size, then, without Daylight UI's mover, at the
-- saved spot, else beside the guide window.
function GatherPanel.PlaceAnchor()
    GatherPanel.SizeAnchor()
    if GatherPanel.managed.mover then return end
    anchor:SetScale(GatherPanel.PieceScale())
    anchor:ClearAllPoints()
    local pt = CP.db and CP.db.gatherPoint
    if pt then
        anchor:SetPoint(pt[1], UIParent, pt[2], pt[3], pt[4])
    else
        anchor:SetPoint(unpack(GatherPanel.Beside()))
    end
end

-- Daylight UI's mover key for the anchor (API.lua prefixes a plugin's keys).
GatherPanel.MOVER_KEY = "plugin.ProfLost." .. GatherPanel.MOVER

-- The options' "Gathering panel scale": the detached panel's own size, kept like the guide
-- window's (Window.PieceScale). Attached, the panel takes the guide window's scale and
-- this one waits.
function GatherPanel.PieceScale()
    local W = CP.Window
    return W.ReadScale(GatherPanel.managed.mover, GatherPanel.MOVER_KEY, "gatherScale")
end

function GatherPanel.SetPieceScale(v)
    local W = CP.Window
    v = W.WriteScale(GatherPanel.managed.mover, GatherPanel.MOVER_KEY, "gatherScale", v)
    if v then anchor:SetScale(v) end
end

-- Saves where the anchor stands: into Daylight UI's mover when it places the panel, else
-- CP.db.gatherPoint. A spot beside the guide window becomes a spot on the screen.
function GatherPanel.SavePlace()
    if GatherPanel.managed.mover then
        local addon = rawget(_G, DAYLIGHT)
        local Movers = type(addon) == "table" and addon.Movers
        if type(Movers) == "table" and type(Movers.Save) == "function" then
            local ok = pcall(Movers.Save, GatherPanel.MOVER_KEY, true)
            if ok then return true end
        end
    end
    local point, rel, relPoint, x, y = anchor:GetPoint(1)
    if rel ~= nil and rel ~= UIParent then
        local left, top = anchor:GetLeft(), anchor:GetTop()
        if not (left and top) then return false end
        point, relPoint, x, y = "TOPLEFT", "BOTTOMLEFT", left, top
        anchor:ClearAllPoints()
        anchor:SetPoint(point, UIParent, relPoint, x, y)
    end
    if point then CP.db.gatherPoint = { point, relPoint, x, y } end
    return false
end

-- A first detach sizes the panel, puts it beside the guide window's current spot and
-- keeps it there. The size comes first, so the mover saves the panel's own centre.
local function placeFirst()
    if not unplaced() then return end
    GatherPanel.SizeAnchor()
    anchor:ClearAllPoints()
    anchor:SetPoint(unpack(GatherPanel.Beside()))
    GatherPanel.SavePlace()
end

-- The corner grip ----------------------------------------------------------------------

-- Hangs the anchor by its top-left where it stands, so a new size keeps that corner still.
local function pin()
    local left, top = anchor:GetLeft(), anchor:GetTop()
    if type(left) ~= "number" or type(top) ~= "number" then return end
    anchor:ClearAllPoints()
    anchor:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
end

-- The detached panel at the player's new size `w` x `h`: within the grip's bounds and the
-- screen's edges past its top-left, saved in CP.db.gatherSize. `live` while the corner is
-- dragged; at the drop the sheet hangs from its anchor again and the spot is saved.
function GatherPanel.Resize(w, h, live)
    if not CP.db then return end
    local room, sw = GatherPanel.Room(), screen()
    local left = anchor:GetLeft()
    if room then h = math.min(h, room) end
    if sw and type(left) == "number" then w = math.min(w, sw - left) end
    w, h = GatherPanel.ClampSize(w, h)
    CP.db.gatherSize = { w, h }
    if sizeTo(w, h) then CP.GatherList.Changed() end
    if live then return end
    sheet:ClearAllPoints()
    sheet:SetPoint("TOPLEFT", anchor, "TOPLEFT")
    GatherPanel.SavePlace()
end

-- The grip's right-click: back to a first detach's size, the top-left kept.
function GatherPanel.ResetSize()
    if not CP.db or GatherPanel.Attached() then return end
    pin()
    CP.db.gatherSize = nil
    GatherPanel.Resize(GatherPanel.DefaultSize())
end

-- Daylight UI's window grip (Style.Grip), shown only while detached.
local grip = S.Grip(sheet, {
    min = GatherPanel.SIZE_MIN,
    start = pin,
    resized = function(w, h) GatherPanel.Resize(w, h, true) end,
    done = function(w, h) GatherPanel.Resize(w, h) end,
    reset = function() GatherPanel.ResetSize() end,
})
grip:Hide()
GatherPanel.grip = grip

-- True while Daylight UI's /dui unlock is on: API.IsUnlocked (1.7), else its Movers.unlocked.
local function unlocked()
    local API = S.Daylight()
    if API and type(API.IsUnlocked) == "function" then return API.IsUnlocked() == true end
    local addon = rawget(_G, DAYLIGHT)
    local Movers = type(addon) == "table" and addon.Movers
    return type(Movers) == "table" and Movers.unlocked == true
end
GatherPanel.Unlocked = unlocked

-- The grip sits over /dui unlock's handles while it is on, as Daylight UI's meter grips
-- do, so the corner still drags; otherwise in the panel's own strata.
function GatherPanel.LiftGrip()
    grip:SetFrameStrata(unlocked() and "FULLSCREEN" or (sheet:GetFrameStrata() or S.WINDOW_STRATA))
    grip:SetFrameLevel((sheet:GetFrameLevel() or 0) + GatherPanel.GRIP_LIFT)
end

-- Standing and tucked in ---------------------------------------------------------------

-- The sheet as its own window, hanging from the anchor. True when it comes out of hiding or
-- out of the guide window; a standing sheet keeps the level the client gave it.
local function standFree()
    local fresh = sheet:GetParent() ~= UIParent or not sheet:IsShown()
    if sheet:GetParent() ~= UIParent then sheet:SetParent(UIParent) end
    if sheet:GetFrameStrata() ~= S.WINDOW_STRATA then sheet:SetFrameStrata(S.WINDOW_STRATA) end
    sheet:SetToplevel(true)
    if fresh then
        sheet:SetFrameLevel(GatherPanel.LEVEL)
        body:SetFrameLevel(sheet:GetFrameLevel() + 1)   -- under the shell's corner caps, whatever level it held in the clip
    end
    sheet:SetScale(anchorScale())
    sheet:ClearAllPoints()
    sheet:SetPoint("TOPLEFT", anchor, "TOPLEFT")
    S.ShellShown(sheet, true)
    S.LineShown(sheet, true)
    CP.GatherList.SetHeadRoom(GatherPanel.HeadRoom())
    closeBtn:Show()
    lockBtn:Show()
    guideBtn:Show()
    grip:Show()
    GatherPanel.LiftGrip()
    S.Restack()
    CP.Window.GatherEscSync()
    return fresh
end

-- The sheet back in the guide window's clip at the window's width, without its own
-- shell or grip.
local function tuckIn()
    if sheet:GetParent() ~= clip then
        sheet:SetParent(clip)
        sheet:SetFrameStrata(panel:GetFrameStrata())
        sheet:SetToplevel(false)
        sheet:SetScale(1)
        sheet:SetAlpha(1)
        GatherPanel.side = nil   -- place() hangs it on the clip again
    end
    sheet:SetWidth(GatherPanel.WIDTH)
    CP.GatherList.SetWidth(GatherPanel.WIDTH - 2 * Panel.BODY_PAD)
    S.ShellShown(sheet, false)
    S.LineShown(sheet, false)
    CP.GatherList.SetHeadRoom(0)
    closeBtn:Hide()
    lockBtn:Hide()
    guideBtn:Hide()
    grip:Hide()
    CP.Window.GatherEscSync()
end

-- Shows the detached panel or hides it, by GatherPanel.Wanted. Attached, nothing to do:
-- the guide window carries it.
function GatherPanel.Update()
    if not CP.db or GatherPanel.Attached() then return end
    if not GatherPanel.Wanted() then return sheet:Hide() end
    local fresh = standFree()
    sheet:Show()
    if fresh then
        S.Front(sheet, GatherPanel.LEVEL)
        GatherPanel.LiftGrip()
    end
    GatherPanel.Fit()
    if CP.GatherList.stale then CP:Soon("gatherList", CP.GatherList.Refresh) end
end

-- Detached, a drag moves the panel alone while its own padlock is open; attached, it
-- moves the guide window and the panel as one, by the guide's padlock.
local moving = false

function GatherPanel.DragStart()
    if GatherPanel.Attached() then return CP.Window.DragStart() end
    if GatherPanel.Locked() or InCombatLockdown() then return end
    moving = true
    anchor:StartMoving()
end

function GatherPanel.DragStop()
    if not moving then return CP.Window.DragStop() end
    moving = false
    anchor:StopMovingOrSizing()
    GatherPanel.SavePlace()
end

-- Places the shell, the panel and its tab for the side setting and slides the panel to
-- its saved state. Detached, the shell frames the guide window alone and the panel stands
-- on its own.
function GatherPanel.Layout(glide)
    if not CP.db then return end
    local attached = GatherPanel.Attached()
    local on = panel:IsShown()
    tab:SetShown(on and attached)
    clip:SetShown(on and attached)
    shell:SetShown(on)
    S.ShellShown(panel, false)
    S.LineShown(panel, not on)
    -- The shell hangs on the window in both modes. A load while detached has placed nothing yet.
    local side = GatherPanel.Side()
    if side ~= GatherPanel.side then place(side) end
    if attached then
        tuckIn()
    else
        slide(0, false)
        GatherPanel.Update()
    end
    if not on then return end
    stack()
    if not attached then
        CP.Window.Clamp()
        return shape()
    end
    if side ~= GatherPanel.side then place(side) end
    -- The checklist skipped rebuilds while it was out of sight. It rebuilds the frame after
    -- the panel opens, so the click's own frame only starts the slide.
    if GatherPanel.IsOpen() and CP.GatherList.stale then CP:Soon("gatherList", CP.GatherList.Refresh) end
    GatherPanel.Fit()
    pointArrow()
    slide(GatherPanel.IsOpen() and 1 or 0, glide and panel:IsVisible())
    -- The pair keeps to the screen as one; a panel sliding out past the edge moves the window in.
    CP.Window.Clamp()
end

-- The guide's title bar shows the attach button only while the panel shows, so any
-- layout or show change lays the bar out again.
do
    local layout, update = GatherPanel.Layout, GatherPanel.Update
    function GatherPanel.Layout(glide)
        layout(glide)
        Panel.LayoutTitle()
    end
    function GatherPanel.Update()
        update()
        Panel.LayoutTitle()
    end
end

-- How far the attached panel reaches past the guide window, and on which side: its
-- width while it is out or sliding out, else 0.
function GatherPanel.Reach()
    if not (GatherPanel.Attached() and GatherPanel.goal == 1 and panel:IsShown()) then
        return 0
    end
    return GatherPanel.WIDTH, GatherPanel.Side()
end

-- The fold tab: slides the attached panel out or back.
function GatherPanel.Toggle()
    CP.db.gatherOpen = not GatherPanel.IsOpen()
    if CP.db.gatherOpen then CP.GatherList.stale = true end
    GatherPanel.Layout(true)
end

-- Opening and closing ----------------------------------------------------------------

-- Shows the checklist. Attached, it slides out, opening the guide window if it is shut.
-- Detached, its own window opens and the open is saved.
function GatherPanel.Open()
    if GatherPanel.Attached() then
        CP.db.gatherOpen = true
        CP.GatherList.stale = true
        if not panel:IsShown() then CP.Window.Open() end
        return GatherPanel.Layout(true)
    end
    CP.db.gatherPanelClosed = nil
    GatherPanel.opened = combatHidden()
    GatherPanel.Update()
end

-- Hides the checklist. Attached, it slides back. Detached, its window closes until
-- opened again, saved.
function GatherPanel.Close()
    if GatherPanel.Attached() then
        CP.db.gatherOpen = false
        return GatherPanel.Layout(true)
    end
    CP.db.gatherPanelClosed = true
    GatherPanel.opened = false
    GatherPanel.Update()
end

-- The launchers' Shift-click and /proflost gather. A press that opened the shut guide window
-- with the attached panel is undone by the next: the window shuts again and the panel keeps
-- the open state it had.
GatherPanel.brought = nil   -- { open = gatherOpen before } while a press opened the guide window

function GatherPanel.ToggleShown()
    if not CP.db then return end
    local brought = GatherPanel.brought
    GatherPanel.brought = nil
    if GatherPanel.Showing() then
        if brought and GatherPanel.Attached() then
            CP.db.gatherOpen = brought.open
            return CP.Window.Close()
        end
        return GatherPanel.Close()
    end
    if GatherPanel.Attached() and not panel:IsShown() then
        GatherPanel.brought = { open = GatherPanel.IsOpen() }
    end
    GatherPanel.Open()
end

-- The player flipped the attach setting. What was shut stays shut: a detached panel the
-- player closed comes in folded, an attached panel out of sight stands closed, and the
-- guide window keeps its own state. The attached panel was out of sight only when it was
-- folded or the guide window was shut.
function GatherPanel.SettingChanged()
    if not CP.db then return end
    GatherPanel.brought = nil
    if GatherPanel.Attached() then
        CP.db.gatherOpen = not GatherPanel.Closed()
        CP.db.gatherPanelClosed = nil
        if CP.db.gatherOpen then CP.GatherList.stale = true end
    else
        local seen = GatherPanel.IsOpen() and panel:IsShown()
        CP.db.gatherPanelClosed = not seen or nil
    end
    GatherPanel.opened = false
    GatherPanel.ModeChanged()
    CP.Window.Update()
end

-- The attach mode changed: a first detach places the panel beside the guide window,
-- then both re-lay out at once.
function GatherPanel.ModeChanged()
    if not CP.db then return end
    if not GatherPanel.Attached() then placeFirst() end
    GatherPanel.Layout()
    CP.GatherList.Changed()
end

panel:HookScript("OnShow", function() GatherPanel.Layout() end)
panel:HookScript("OnSizeChanged", function()
    if not shell:IsShown() then return end
    if GatherPanel.Attached() then GatherPanel.Fit() end
    shape()
end)

CP:On("PLAYER_LOGIN", function() GatherPanel.PlaceAnchor() end)

-- Once the world is up the guide window and Daylight UI's movers have settled, so the
-- saved slide state lands on their final places.
CP:On("PLAYER_ENTERING_WORLD", function()
    CP:Soon("gatherLayout", function() GatherPanel.Layout() end)
end)
