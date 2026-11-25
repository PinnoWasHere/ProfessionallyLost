-- The guide window's title bar shows the addon's version on its own line under the title,
-- small and in the note colour, whatever the title fits as. The tabs look as Daylight UI's
-- own tabs do from the first paint: the picked one in the accent, others in the label ink,
-- white on hover; a Daylight UI repaint (StyleChanged at login) never greys the picked tab.

local CP = ProfLost
local W, P, S = CP.Window, CP.Panel, CP.Style
local LW, TAILOR = 165, 197
local DUROTAR = 1411
local VERSION = "0.2.65-beta"

local function scene()
    Visual.begin()
    DaylightWorld.begin({ plugin = true })
    Visual.Skin()
    MapWorld.begin({ zone = DUROTAR, level = 20, side = "Horde" })
    CraftWorld.begin({ professions = { [LW] = 100, [TAILOR] = 60 } })
    World.set(C_AddOns, "GetAddOnMetadata", function(addon, key)
        if addon == CP.name and key == "Version" then return VERSION end
    end)
    World.set(CP.db, "hideInCombat", true)
    World.set(CP.db, "windowClosed", nil)
    World.set(CP.db, "windowCollapsed", nil)
    World.set(CP.db, "windowLocked", nil)
    World.set(CP.db, "windowPoint", { "TOPLEFT", "BOTTOMLEFT", 100, 900 })
    World.set(CP.charDB, "guideMode", "one")
    World.onEnd(function()
        P.SetFolded(false)
        W.Update()
    end)
    W.Update()
    W.Pick(LW)
    P:Refresh()
    T.advance(0.5)
    T.ok(P.frame:IsShown(), "the guide window")
end

local function color(fs)
    local r, g, b = fs:GetTextColor()
    return { math.floor(r * 1000 + 0.5), math.floor(g * 1000 + 0.5), math.floor(b * 1000 + 0.5) }
end
local function rgb(c) return { math.floor(c[1] * 1000 + 0.5), math.floor(c[2] * 1000 + 0.5), math.floor(c[3] * 1000 + 0.5) } end

-- The version line ----------------------------------------------------------------------

T.test("the version sits on its own line under the title, small, in the note colour", function()
    scene()
    local v, t = P.version, P.title
    T.eq(v:GetText(), VERSION, "the TOC's version")
    T.ok(v:IsShown(), "shown")
    S.Repaint()   -- colours set at load predate the visual world
    T.eq(color(v), rgb(S.color.muted), "the note colour")
    local _, size = v:GetFont()
    local _, titleSize = t:GetFont()
    T.ok(size < titleSize, ("smaller than the title (%s, %s)"):format(tostring(size), tostring(titleSize)))
    local vl, vb, _, vt = Visual.Resolve(v)
    local tl, tb = Visual.Resolve(t)
    T.ok(vt <= tb, "below the title")
    T.eq(vl, tl, "lined up with the title's left edge")
    local _, fb, _, ft = Visual.Resolve(P.frame)
    T.ok(vb >= ft - P.TITLE_H, "inside the title bar")
    T.ok(not v:IsTruncated(), "whole")
    -- The title and the version are centred on the bar's middle, as the controls are.
    local mid = ft - S.HEADER.mid
    local _, lb, _, lt = Visual.Resolve(P.logo)
    T.ok(math.abs((lb + lt) / 2 - mid) < 1, "the logo on the middle")
    local _, _, _, tt = Visual.Resolve(t)
    T.ok(math.abs((vb + tt) / 2 - mid) < 4, ("the two lines centred on the middle (%d to %d, %d)"):format(vb, tt, mid))
    local _, bb, _, bt = Visual.Resolve(P.bugButton)
    T.ok(math.abs((bb + bt) / 2 - mid) < 1, "the controls stay centred")
    T.eq(P.TITLE_H, 2 * S.HEADER.mid, "the bar keeps its height")
    Visual.Check("the version line")
end)

T.test("a title too long for the window reads ProfLost, and the version still shows", function()
    scene()
    World.set(P, "TITLE_FULL", ("Professionally Lost "):rep(4))
    P:Refresh()
    T.advance(0.5)
    T.eq(P.titleText, P.TITLE_SHORT)
    T.ok(P.version:IsShown(), "shown")
    T.eq(P.version:GetText(), VERSION)
    T.ok(not P.version:IsTruncated())
end)

T.test("folded, the title bar still holds both lines", function()
    scene()
    P.SetFolded(true)
    P:Refresh()
    T.advance(0.5)
    T.ok(P.version:IsVisible(), "the version shows folded")
    local _, vb = Visual.Resolve(P.version)
    local _, _, _, ft = Visual.Resolve(P.frame)
    T.ok(vb >= ft - P.TITLE_H, "inside the title bar")
    Visual.Check("folded, the version line")
end)

-- Tabs ----------------------------------------------------------------------------------

-- A tab made as Panel:AddTab makes it, with Daylight UI loaded.
local function tab(picked)
    local b = CreateFrame("Button", nil, P.frame)
    b:SetSize(60, 24)
    b.label = S.Text(b, "body", S.color.muted, true)
    b.label:SetPoint("CENTER")
    b.look = S.TabLook(b, b.label)
    T.ok(b.look ~= nil, "Daylight UI's tab look")
    b.look.Pick(picked)
    World.onEnd(function() b:Hide() end)
    return b
end

local function accent() return rgb({ DaylightUI.API.Accent() }) end

T.test("the picked tab is in the accent from the first paint, and a Daylight UI repaint keeps it", function()
    scene()
    local b = tab(true)
    T.eq(color(b.label), accent(), "at load")
    S.Repaint()   -- Daylight UI's StyleChanged at login
    T.eq(color(b.label), accent(), "after Daylight UI repaints")
    b:GetScript("OnEnter")(b)
    b:GetScript("OnLeave")(b)
    T.eq(color(b.label), accent(), "after a hover")
end)

T.test("an unpicked tab is the label ink, white on hover, back on leave", function()
    scene()
    local b = tab(false)
    local label = rgb(DaylightUI.API.Colors().LABEL)
    T.eq(color(b.label), label)
    b:GetScript("OnEnter")(b)
    T.eq(color(b.label), rgb(DaylightWorld.state.tabWhite), "white on hover")
    b:GetScript("OnLeave")(b)
    T.eq(color(b.label), label, "back on leave")
    S.Repaint()
    T.eq(color(b.label), label, "a repaint keeps the label ink")
end)

T.test("the guide window's picked tab keeps its colour through a repaint and a show", function()
    scene()
    local guide = P.tabs.guide.button
    guide:GetScript("OnClick")(guide)
    T.eq(P.current, "guide")
    local before = color(guide.label)
    T.eq(before, rgb(guide.look and { DaylightUI.API.Accent() } or S.color.title), "picked")
    S.Repaint()
    T.eq(color(guide.label), before, "a repaint leaves the picked tab as it was")
    P.frame:Hide()
    P.frame:Show()
    T.eq(color(guide.label), before, "and a show")
end)
