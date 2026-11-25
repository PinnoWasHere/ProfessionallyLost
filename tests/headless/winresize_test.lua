-- The guide window's corner grip: it sets the width freely, between the gathering panel's
-- width (Window.LeastWidth) and the screen (CP.db.windowWidth), and its height in whole step rows
-- through "Steps shown" (stepsshown_test). Both come back after a reload; a taller window
-- shows more step rows; a locked window ignores the grip unless /dui unlock is on; the
-- attached gathering panel stays beside it; a right-click resets.

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
    World.set(CP.db, "hideInCombat", true)
    World.set(CP.db, "windowClosed", nil)
    World.set(CP.db, "windowCollapsed", nil)
    World.set(CP.db, "windowCollapsedAll", nil)
    World.set(CP.db, "windowLocked", nil)
    World.set(CP.db, "windowSize", nil)
    World.set(CP.db, "windowWidth", nil)
    World.set(CP.db, "windowAnchorSize", nil)
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

local function height(f) local _, _, _, h = f:GetRect() return h end
local function width(f) local _, _, w = f:GetRect() return w end

-- Step rows the list shows without scrolling.
local function rowsShown() return math.floor(height(GT.ui.scroll) / GT.RowHeight() + 0.001) end


T.test("the grip resizes the window and saves the size", function()
    scene()
    local w0, h0, n0, row = P.WIDTH, P.frame:GetHeight(), CP.db.guideSteps, GT.RowHeight()
    T.ok(W.grip:IsShown(), "unlocked: the grip shows")
    T.eq(n0, CP.DEFAULTS.guideSteps, "a long guide shows the default steps")
    dragGrip(80, 200)
    T.eq(CP.db.windowWidth, w0 + 80, "the width is saved")
    T.eq(CP.db.guideSteps, n0 + 8, "200 px down: eight more steps")
    T.eq(P.WIDTH, w0 + 80, "the window is wider")
    T.eq(width(P.frame), w0 + 80, "and draws wider")
    T.eq(P.frame:GetHeight(), h0 + 8 * row, "and taller by whole rows")
    T.eq({ W.anchor:GetWidth(), W.anchor:GetHeight() }, { w0 + 80, h0 + 8 * row }, "the anchor, for the mover's box")
    T.eq({ P.frame:GetLeft(), P.frame:GetTop() }, { LEFT, TOP }, "its top-left held still")
end)

-- The least width is the gathering panel's, even where the window's own width is more (an "or"
-- row's info naming Tailoring widens this guide's).
T.test("the grip keeps the window between the gathering panel's width, one step and the screen", function()
    scene()
    local w0 = W.LeastWidth()
    T.eq(w0, GP.WIDTH, "the gathering panel's width")
    dragGrip(-1000, -1000)
    T.eq({ CP.db.windowWidth, CP.db.guideSteps }, { w0, 1 }, "never narrower than the gathering panel, nor under one step")
    T.eq(P.WIDTH, w0)
    T.eq(rowsShown(), 1)

    -- Daylight UI's grip sizes the frame to the mouse before it asks; the window takes its least size back.
    P.frame:SetSize(200, 300)
    W.Resize(200, 300, true)
    T.eq(width(P.frame), w0, "a frame sized under the least width")
    T.eq(CP.db.guideSteps, 1, "and under one step")

    T.ok(GP.Reach() > 0, "the gathering panel is out on the right")
    dragGrip(5000, 5000)
    T.eq(CP.db.windowWidth, Visual.SCREEN[1] - LEFT - GP.Reach(), "no further than the screen's right edge, the panel beside it")
    T.eq(CP.db.guideSteps, CP.Settings.Find("guideSteps").max, "nor past the most steps")
    T.eq({ P.frame:GetLeft(), P.frame:GetTop() }, { LEFT, TOP }, "the window stays put")
end)

T.test("the size comes back after a reload", function()
    scene()
    local w0 = P.WIDTH
    dragGrip(60, 3 * GT.RowHeight())
    local h = P.frame:GetHeight()
    T.eq({ CP.db.windowWidth, CP.db.guideSteps }, { w0 + 60, CP.DEFAULTS.guideSteps + 3 })
    P.WIDTH = P.BASE_WIDTH
    P.frame:SetWidth(P.BASE_WIDTH)
    P.frame:SetHeight(CP.DEFAULTS.windowHeight)
    Visual.Reload()
    P:Refresh()
    settle()
    T.eq({ P.WIDTH, P.frame:GetHeight() }, { w0 + 60, h }, "the saved size")
    T.eq({ P.frame:GetLeft(), P.frame:GetTop() }, { LEFT, TOP }, "at the saved spot")
end)

T.test("a taller window shows more step rows, a wider one more of each name", function()
    scene()
    T.ok(#GT.ui.rows > rowsShown(), "the guide has more steps than today's window shows")
    local before, room = rowsShown(), GT.NameRoom()
    dragGrip(100, 200)
    T.ok(rowsShown() > before, ("more rows: %d, was %d"):format(rowsShown(), before))
    T.eq(GT.NameRoom(), room + 100, "the names have the added width")
    Visual.Check("wide and tall, One view")
end)

T.test("the card and the All view lay out at a larger size", function()
    scene()
    dragGrip(200, 250)
    local full = P.frame:GetHeight()
    W.SetFolded(true)
    settle()
    T.eq(P.WIDTH, CP.db.windowWidth, "folded keeps the width")
    T.ok(P.frame:GetHeight() < full, "folded fits the card, not the step list")
    Visual.Check("wide, folded")
    W.SetFolded(false)
    W.SetMode("all")
    W.SetFolded(false)
    settle()
    T.eq(P.WIDTH, CP.db.windowWidth, "the All view takes the width")
    Visual.Check("wide and tall, All view")
    W.SetMode("one")
end)

T.test("folded, the grip changes the width only", function()
    scene()
    W.SetFolded(true)
    settle()
    local w0 = P.WIDTH
    dragGrip(50, 300)
    T.eq({ CP.db.windowWidth, CP.db.guideSteps }, { w0 + 50, CP.DEFAULTS.guideSteps }, "the steps stay")
end)

T.test("a locked window ignores the grip, unless /dui unlock is on", function()
    scene()
    W.lockButton:GetScript("OnClick")(W.lockButton)
    T.ok(W.Locked(), "locked")
    T.ok(not W.grip:IsShown(), "locked: no grip")
    local w0, h0 = P.WIDTH, P.frame:GetHeight()
    dragGrip(80, 200)
    T.eq({ CP.db.windowWidth, CP.db.guideSteps }, { nil, CP.DEFAULTS.guideSteps }, "nothing saved")
    T.eq({ P.WIDTH, P.frame:GetHeight() }, { w0, h0 }, "the size stays")
    W.grip:GetScript("OnMouseUp")(W.grip, "RightButton")
    T.eq(CP.db.windowWidth, nil, "a right-click does nothing either")

    World.set(GP, "Unlocked", function() return true end)
    W.SyncGrip()
    T.ok(W.grip:IsShown(), "/dui unlock: the grip shows")
    T.eq(W.grip:GetFrameStrata(), "FULLSCREEN", "over the mover handles")
    dragGrip(80, 0)
    T.eq(CP.db.windowWidth, w0 + 80, "and resizes")
end)

T.test("the attached gathering panel stays beside the window at any size", function()
    scene()
    GP.Open(true)
    settle()
    dragGrip(120, 220)
    local l, _, w = P.frame:GetRect()
    T.eq(GP.clip:GetLeft(), l + w, "the panel starts at the window's right edge")
    T.eq(GP.sheet:GetHeight(), P.frame:GetHeight(), "as tall as the window")
    T.eq(GP.shell:GetWidth(), P.WIDTH + GP.p * GP.WIDTH, "one shell around both")
    Visual.Check("wide and tall, panel out")
end)

T.test("a right-click on the grip puts back the window's own width and the default steps", function()
    scene()
    local w0, h0 = P.WIDTH, P.frame:GetHeight()
    dragGrip(100, 100)
    W.grip:GetScript("OnMouseUp")(W.grip, "RightButton")
    settle()
    T.eq({ CP.db.windowWidth, CP.db.guideSteps }, { nil, CP.DEFAULTS.guideSteps }, "forgotten")
    T.eq({ P.WIDTH, P.frame:GetHeight() }, { w0, h0 })
end)
