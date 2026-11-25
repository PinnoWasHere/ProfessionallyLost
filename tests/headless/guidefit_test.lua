-- The guide window's place, layout and width hold up under the owner's three in-game checks.
-- Steps shown changes leave the top-left exactly where it was, with Daylight UI's mover
-- saving each spot as the game's does (a centre snapped to whole screen pixels). A scale
-- change lays the window out again as a fold and unfold would. The corner grip narrows the
-- window to the gathering panel's width, and every part still lays out there.

local CP = ProfLost
local W, P, GP, GT = CP.Window, CP.Panel, CP.GatherPanel, CP.GuideTab
local LW, TAILOR, MINING = 165, 197, 186
local DUROTAR = 1411
local LEFT, TOP = 100, 1000

local function settle() T.advance(0.5) end

local function scene()
    Visual.begin()
    DaylightWorld.begin({ plugin = true })
    Visual.Skin()
    MapWorld.begin({ zone = DUROTAR, level = 20, side = "Horde" })
    CraftWorld.begin({ professions = { [LW] = 1, [TAILOR] = 60, [MINING] = 30 } })
    for _, key in ipairs({ "windowClosed", "windowCollapsed", "windowCollapsedAll", "windowLocked", "windowSize",
                           "windowWidth", "guideScale", "windowAnchorSize" }) do
        World.set(CP.db, key, nil)
    end
    World.set(CP.db, "hideInCombat", true)
    World.set(CP.db, "guideSteps", CP.DEFAULTS.guideSteps)
    World.set(CP.db, "windowHeight", CP.DEFAULTS.windowHeight)
    World.set(CP.db, "windowPoint", { "TOPLEFT", "BOTTOMLEFT", LEFT, TOP })
    World.set(CP.db, "gatherAttached", true)
    World.set(CP.db, "gatherOpen", true)
    World.set(CP.db, "gatherSide", "right")
    World.set(CP.charDB, "guideMode", "one")
    World.set(W.managed, "mover", false)
    World.set(GP.managed, "mover", false)
    World.onEnd(function()
        CraftWorld.Close()
        W.managed.mover = false
        W.anchor:SetScale(1)
        W.SetFolded(false)
        GP.anchor:ClearAllPoints()
        W.PlaceAnchor()
        P:Refresh()
        W.Update()
    end)
    GP.anchor:ClearAllPoints()
    W.PlaceAnchor()
    W.Update()
    W.Pick(LW)
    P:Refresh()
    settle()
end

-- 1. Steps shown keeps the top-left exactly ---------------------------------------------

-- Daylight UI's Movers.Save as the game runs it (Movers.lua liveOffset, store, Apply; Pixel.Snap):
-- the anchor's centre from the screen's centre in UIParent units, snapped to the nearest
-- physical pixel, and the anchor placed back by that centre. PHYS_H is a 1440p screen.
local PHYS_H = 1440

local function snap(v)
    local u = 768 / PHYS_H / UIParent:GetEffectiveScale()
    local px = v / u
    if px >= 0 then px = math.floor(px + 0.5 + 0.001) else px = -math.floor(-px + 0.5 + 0.001) end
    return px * u
end

local saved

-- The anchor placed by the saved centre, as Movers.Apply does.
local function moverApply()
    local f = W.anchor
    local r = f:GetEffectiveScale() / UIParent:GetEffectiveScale()
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "CENTER", saved[1] / r, saved[2] / r)
end

local function moverSave()
    local f = W.anchor
    local r = f:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local cx, cy = f:GetCenter()
    saved = { snap(cx * r - UIParent:GetWidth() / 2), snap(cy * r - UIParent:GetHeight() / 2) }
    moverApply()
end

-- The mover holds the anchor at `scale`, by its centre, and saves as the game's does.
local function moverHolds(scale)
    W.anchor:SetScale(scale)
    P:Refresh()
    settle()
    World.set(W.managed, "mover", true)
    World.set(DaylightUI.Movers, "Save", function() moverSave() end)
    moverSave()
end

-- The window's top-left in screen pixels.
local function topLeft()
    local l, _, _, t = Visual.Resolve(P.frame)
    return l, t
end

for _, scale in ipairs({ 0.8, 1.0, 1.25 }) do
    T.test(("ten Steps shown changes keep the top-left within half a pixel at scale %.2f, held by the mover"):format(scale), function()
        scene()
        moverHolds(scale)
        local l0, t0 = topLeft()
        local worst = 0
        for _, n in ipairs({ 7, 3, 9, 2, 8, 5, 10, 1, 6, 4 }) do
            CP.Settings.Set("guideSteps", n)
            settle()
            local l, t = topLeft()
            worst = math.max(worst, math.abs(l - l0), math.abs(t - t0))
        end
        T.ok(worst <= 0.5, ("the top-left moved at most %.3f px"):format(worst))

        -- A reload: the anchor at its first size takes its saved size, then the mover places it.
        W.anchor:SetSize(P.BASE_WIDTH, CP.DEFAULTS.windowHeight)
        W.SizeAnchor()
        moverApply()
        P:Refresh()
        settle()
        local l, t = topLeft()
        T.ok(math.abs(l - l0) <= 0.5 and math.abs(t - t0) <= 0.5,
            ("after a reload the top-left is %.3f, %.3f px off"):format(l - l0, t - t0))
    end)
end

-- 2. A scale change lays the window out again ------------------------------------------

-- The game draws each glyph a whole number of screen pixels wide, so a string measures a
-- little differently at each scale (Style.lua's gauge note). The harness's widths become
-- that: each letter's width rounded at the string's drawn scale, back in its own units.
local function glyphsRound()
    local probe = P.frame:CreateFontString(nil, "OVERLAY")
    local methods = getmetatable(probe).__index
    for _, name in ipairs({ "GetUnboundedStringWidth", "GetStringWidth" }) do
        local base = methods[name]
        World.set(methods, name, function(self)
            local w = base(self)
            local text = tostring(self:GetText() or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
            local n = #text
            local parent = self:GetParent()
            local k = parent and parent.GetEffectiveScale and parent:GetEffectiveScale() or 1
            if n == 0 or w <= 0 or k <= 0 then return w end
            return n * math.floor(w / n * k + 0.5) / k
        end)
    end
end

-- Every shown part of the window: its rect in the window's units from its top-left, and its text.
local function layout()
    local out, seen = {}, {}
    local fl, _, _, ft = Visual.Resolve(P.frame)
    local k = P.frame:GetEffectiveScale()
    local function walk(o, depth)
        if seen[o] or depth > 12 then return end
        seen[o] = true
        if o.IsShown and not o:IsShown() then return end
        local l, b, r, t = Visual.Resolve(o)
        local text = o.GetText and o:GetObjectType() == "FontString" and o:GetText() or ""
        if l then
            out[#out + 1] = ("%.1f %.1f %.1f %.1f %s"):format((l - fl) / k, (ft - t) / k, (r - l) / k, (t - b) / k, tostring(text))
        end
        if o.GetRegions then for _, x in ipairs({ o:GetRegions() }) do walk(x, depth + 1) end end
        if o.GetChildren then for _, x in ipairs({ o:GetChildren() }) do walk(x, depth + 1) end end
    end
    walk(P.frame, 0)
    table.sort(out)
    return { width = P.WIDTH, height = P.frame:GetHeight(), parts = out }
end

local function foldCycle()
    W.SetFolded(true)
    settle()
    W.SetFolded(false)
    settle()
end

for _, scale in ipairs({ 0.8, 1.25 }) do
    T.test(("a guide scale of %.2f lays the window out as a fold and unfold does"):format(scale), function()
        scene()
        glyphsRound()
        P:Refresh()
        settle()
        local before = layout()
        foldCycle()
        T.eq(layout(), before, "a fold cycle at the same scale changes nothing")

        W.SetPieceScale(scale)
        settle()
        local changed = layout()
        foldCycle()
        local folded = layout()
        T.ok(folded.width ~= before.width or #folded.parts ~= #before.parts or folded.parts[1] ~= before.parts[1],
            "the scale measures the text differently")
        T.eq(changed, folded, "the scale change laid the window out at once")
    end)
end

T.test("the mover's scale lays the window out again too", function()
    scene()
    glyphsRound()
    P:Refresh()
    settle()
    W.anchor:SetScale(1.25)
    settle()
    local changed = layout()
    foldCycle()
    T.eq(changed, layout(), "Daylight UI's mover scaling the anchor relays it")
end)

-- 3. The grip narrows the window to the gathering panel's width -------------------------

-- A drag of the corner grip by `dx`, `dy` (right and down), through its own scripts.
local function dragGrip(dx, dy)
    local x, y = 1000, 500
    World.set(_G, "GetCursorPosition", function() return x, y end)
    W.grip:GetScript("OnMouseDown")(W.grip, "LeftButton")
    x, y = x + dx, y - dy
    W.grip:GetScript("OnUpdate")(W.grip, 0.016)
    W.grip:GetScript("OnMouseUp")(W.grip, "LeftButton")
    settle()
end

-- A wider font than the harness's own, as the game's is: the window's parts need more
-- room than the gathering panel's width. At 11 px a letter even the tab row's tabs,
-- switch and dropdown need more.
local function wideFont(letter)
    World.set(Visual, "LETTER", letter or 9)
    P:Refresh()
    settle()
end

local function inside(f, label)
    local l, b, r, t = Visual.Resolve(f)
    local pl, pb, pr, pt = Visual.Resolve(P.frame)
    T.ok(l >= pl - 0.5 and r <= pr + 0.5 and b >= pb - 0.5 and t <= pt + 0.5, label .. " inside the window")
    return l, b, r, t
end

local function apart(a, b, label)
    local al, ab, ar, at = Visual.Resolve(a)
    local bl, bb, br, bt = Visual.Resolve(b)
    T.ok(ar <= bl + 0.5 or br <= al + 0.5 or at <= bb + 0.5 or bt <= ab + 0.5, label)
end

T.test("the grip narrows the window to the gathering panel's width, and no further", function()
    scene()
    wideFont()
    T.ok(P.AutoWidth() > GP.WIDTH, "the window's own width is wider than the panel's")
    dragGrip(-2000, 0)
    T.eq(P.WIDTH, GP.WIDTH, "as narrow as the gathering panel")
    T.eq(CP.db.windowWidth, GP.WIDTH, "saved")
    T.eq(P.frame:GetWidth(), GP.sheet:GetWidth(), "the two match edge to edge")
    W.Resize(GP.WIDTH - 50, P.frame:GetHeight())
    T.eq(P.WIDTH, GP.WIDTH, "never narrower")
    dragGrip(40, 0)
    T.eq(P.WIDTH, GP.WIDTH + 40, "wider again from there")
end)

for _, letter in ipairs({ 9, 11 }) do
T.test(("at the gathering panel's width every part of the guide lays out without overlap, %d px letters"):format(letter), function()
    scene()
    wideFont(letter)
    if letter == 11 then T.ok(P.needs.row > GP.WIDTH, "the tab row needs more than the panel's width") end
    dragGrip(-2000, 0)
    T.eq(P.WIDTH, GP.WIDTH)
    Visual.Check("narrow, One view")

    -- The tab row: the tabs, then the Single/All switch and the profession dropdown.
    local tabs = {}
    for _, k in ipairs(P.order) do
        local b = P.tabs[k].button
        if b:IsShown() then tabs[#tabs + 1] = b end
    end
    local sw, pick = W.switchButton, W.pickButton
    inside(sw, "the switch")
    inside(pick, "the dropdown")
    apart(sw, pick, "the switch and the dropdown apart")
    for _, b in ipairs(tabs) do
        apart(b, sw, "a tab clear of the switch")
        apart(b, pick, "a tab clear of the dropdown")
    end
    T.ok(not Visual.Truncated(sw.label), "the switch's label whole")

    -- The title bar's buttons and title.
    for _, t in ipairs(P.titleButtons) do
        if t.button:IsShown() then
            inside(t.button, "a title bar button")
            if P.title:IsShown() then apart(P.title, t.button, "the title clear of a title bar button") end
        end
    end

    -- The step rows, the card and Available Skill Ups.
    inside(GT.ui.scroll, "the step list")
    inside(GT.ui.details, "the card")
    if GT.ui.impromptu:IsShown() then
        inside(GT.ui.impromptu, "Available Skill Ups")
        apart(GT.ui.impromptu, GT.ui.details, "Available Skill Ups clear of the card")
    end
    apart(GT.ui.scroll, GT.ui.details, "the list clear of the card")

    W.SetMode("all")
    settle()
    T.eq(P.WIDTH, GP.WIDTH, "the All view keeps the width")
    Visual.Check("narrow, All view")
    W.SetMode("one")
    W.SetFolded(true)
    settle()
    Visual.Check("narrow, folded")
end)
end
