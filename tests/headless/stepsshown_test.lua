-- "Steps shown": a Guide window slider sets how many steps the One view lists, a step being a
-- main row and its "or" rows, and the window's height follows while its top-left stays put. The
-- corner grip's vertical drag sets the same value by whole steps, while its width stays free. The value is saved through the settings path, and an old saved
-- grip height (CP.db.windowSize) becomes a step count once.

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
    World.set(CP.db, "guideSteps", CP.DEFAULTS.guideSteps)
    World.set(CP.db, "guideStepsCarried", nil)
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

-- Step rows the list shows without scrolling, and whether a part of one more peeks out.
local function rowsShown()
    local n = height(GT.ui.scroll) / GT.RowHeight()
    return math.floor(n + 0.001), math.abs(n - math.floor(n + 0.5)) > 0.001
end

local function setSteps(n)
    CP.Settings.Set("guideSteps", n)
    settle()
end

T.test("a Steps shown slider in the Guide window group, 1 to 15, today's rows by default", function()
    local s = CP.Settings.Find("guideSteps")
    T.ok(s ~= nil, "the setting exists")
    T.eq({ s.kind, s.group, s.label }, { "slider", "Guide window", "Steps shown" })
    T.eq({ s.min, s.max, s.step }, { 1, 15, 1 }, "whole steps from 1 to 15")
    T.eq(CP.DEFAULTS.guideSteps, 4, "the rows a default window showed whole")
    local row
    for _, g in ipairs(CP.Plugin.Pages()[1].groups) do
        for _, it in ipairs(g.items) do
            if it.key == "guideSteps" then row = { g.label, it.type, it.min, it.max, it.step } end
        end
    end
    T.eq(row, { "Guide window", "slider", 1, 15, 1 }, "Daylight UI's own slider row on the options page")
    T.eq(CP.Plugin.Defaults().guideSteps, 4, "Daylight UI's default for it")
end)

T.test("the step list shows exactly the chosen rows and the window's height follows", function()
    scene()
    T.ok(#GT.ui.rows > 15, "a guide longer than any choice")
    local n, peek = rowsShown()
    T.eq({ n, peek }, { CP.DEFAULTS.guideSteps, false }, "the default: whole rows, no part of the next")
    local h4 = P.frame:GetHeight()

    setSteps(3)
    n, peek = rowsShown()
    T.eq({ n, peek }, { 3, false }, "3 rows")
    T.eq(P.frame:GetHeight(), h4 - GT.RowHeight(), "one row shorter")
    T.ok(GT.ui.details:IsShown() and GT.ui.impromptu:IsShown(), "the card and Available Skill Ups still show")
    T.ok(GT.ui.details:GetBottom() >= P.frame:GetBottom() - 0.5, "the card ends inside the window")
    T.eq(GP.sheet:GetHeight(), P.frame:GetHeight(), "the attached gathering panel matches")
    Visual.Check("3 steps")

    setSteps(10)
    n, peek = rowsShown()
    T.eq({ n, peek }, { 10, false }, "10 rows")
    T.eq(P.frame:GetHeight(), h4 + 6 * GT.RowHeight(), "six rows taller")
    T.eq(W.anchor:GetHeight(), P.frame:GetHeight(), "the mover's box is the window")
    T.eq(GP.sheet:GetHeight(), P.frame:GetHeight(), "the gathering panel follows")
    Visual.Check("10 steps")
end)

T.test("a guide with fewer steps than chosen shows them all, with no empty space", function()
    scene()
    World.set(GT.ui, "rows", { GT.ui.rows[1], GT.ui.rows[2] })
    CP.db.guideSteps = 15
    local fifteen = GT.OpenHeight()
    CP.db.guideSteps = 2
    T.eq(fifteen, GT.OpenHeight(), "15 chosen, 2 steps: as tall as 2 chosen")
end)

T.test("the grip's vertical drag sets Steps shown in whole rows; its width stays free", function()
    scene()
    local row, n0, w0 = GT.RowHeight(), CP.db.guideSteps, P.WIDTH
    local h0 = P.frame:GetHeight()
    dragGrip(80, 2 * row + 5)
    T.eq(CP.db.guideSteps, n0 + 2, "down by two rows: two more steps")
    T.eq(DaylightWorld.Snapshot().settings.ProfLost.guideSteps, n0 + 2, "saved where the slider saves it")
    T.eq(P.frame:GetHeight(), h0 + 2 * row, "the window snaps to whole rows")
    T.eq({ rowsShown() }, { n0 + 2, false })
    T.eq(P.WIDTH, w0 + 80, "the width follows the mouse")
    T.eq(CP.db.windowWidth, w0 + 80, "and is saved")

    dragGrip(0, -row)
    T.eq(CP.db.guideSteps, n0 + 1, "up by one row: one fewer")
    dragGrip(0, 40 * row)
    T.eq(CP.db.guideSteps, 15, "never past the slider's top")
    dragGrip(0, -40 * row)
    T.eq(CP.db.guideSteps, 1, "nor under its bottom")
    T.eq({ rowsShown() }, { 1, false })
end)

T.test("folded, the grip changes the width only", function()
    scene()
    W.SetFolded(true)
    settle()
    local n0, w0 = CP.db.guideSteps, P.WIDTH
    dragGrip(50, 300)
    T.eq(CP.db.guideSteps, n0, "the steps stay")
    T.eq(CP.db.windowWidth, w0 + 50, "the width changes")
end)

T.test("Steps shown comes back after a reload", function()
    scene()
    dragGrip(0, 3 * GT.RowHeight())
    local want = CP.DEFAULTS.guideSteps + 3
    T.eq(CP.db.guideSteps, want)
    -- A fresh save takes the default until Daylight UI's copy arrives at login.
    CP.db.guideSteps = CP.DEFAULTS.guideSteps
    CP.Plugin.Sync(DaylightUI.API)
    Visual.Reload()
    P:Refresh()
    settle()
    T.eq(CP.db.guideSteps, want, "Daylight UI's saved value")
    T.eq({ rowsShown() }, { want, false }, "the list shows it")
end)

local function carried(db)
    local copy = {}
    for k, v in pairs(db) do copy[k] = v end
    return CP.CarryOver(copy)
end

T.test("an old saved grip height becomes the nearest step count once, keeping the width", function()
    local row, base = GT.RowHeight(), CP.DEFAULTS.windowHeight
    local db = carried({ windowSize = { 520, base + 2 * row + 5 } })
    T.eq(db.guideSteps, CP.DEFAULTS.guideSteps + 2, "two rows taller: two more steps")
    T.eq(db.windowWidth, 520, "the width stays")
    T.eq(db.windowSize, nil, "the old size goes")
    T.eq(db.guideStepsCarried, true, "Daylight UI's copy is settled at login")
    T.eq(carried({ windowSize = { 400, base } }).guideSteps, CP.DEFAULTS.guideSteps, "today's height: the default")
    T.eq(carried({ windowSize = { 400, base + 13 } }).guideSteps, CP.DEFAULTS.guideSteps + 1, "half a row and more rounds up")
    T.eq(carried({ windowSize = { 400, 5000 } }).guideSteps, 15, "at most 15")
    local kept = carried({ windowSize = { 400, 900 }, guideSteps = 6 })
    T.eq(kept.guideSteps, 6, "a picked value stays")
    T.eq(carried({ guideSteps = 6 }).guideStepsCarried, nil, "nothing to carry")
    local again = carried(db)
    T.eq(again.guideSteps, db.guideSteps, "a second load changes nothing")
end)

T.test("Daylight UI's default does not undo a carried step count, and takes it", function()
    scene()
    CP.db.guideSteps, CP.db.guideStepsCarried = 7, true
    CP.Plugin.Sync(DaylightUI.API)
    T.eq(CP.db.guideSteps, 7, "the carried value stays")
    T.eq(CP.db.guideStepsCarried, nil, "settled once")
    T.eq(DaylightWorld.Snapshot().settings.ProfLost.guideSteps, 7, "Daylight UI's options page shows it")
end)

-- Daylight UI's mover holds the anchor by its centre (Movers.Apply), as it does in game.
local function moverHolds()
    World.set(W.managed, "mover", true)
    World.set(CP.db, "windowAnchorSize", nil)
    World.onEnd(function() W.managed.mover = false end)
    local cx, cy = W.anchor:GetCenter()
    W.anchor:ClearAllPoints()
    W.anchor:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx, cy)
end

-- The window's top-left and the attached gathering panel's left edge and top.
local function place()
    return { P.frame:GetLeft(), P.frame:GetTop(), GP.sheet:GetLeft(), GP.sheet:GetTop() }
end

for _, mover in ipairs({ false, true }) do
    local by = mover and "Daylight UI's mover" or "its own anchor"
    T.test("folded, changing Steps shown keeps the window and its panel in place, held by " .. by, function()
        scene()
        W.SetFolded(true)
        settle()
        if mover then moverHolds() end
        local at, h = place(), P.frame:GetHeight()
        T.ok(GP.Reach() > 0, "the gathering panel is out beside it")
        setSteps(8)
        T.eq(place(), at, "the window and its panel stay put")
        T.eq({ P.frame:GetLeft(), P.frame:GetTop() }, { at[1], at[2] }, "its top-left")
        T.eq(P.frame:GetHeight(), h, "folded, the steps leave its height alone")
        setSteps(2)
        T.eq(place(), at, "fewer steps: still in place")
    end)

    T.test("unfolded, changing Steps shown keeps the window's top-left, held by " .. by, function()
        scene()
        if mover then moverHolds() end
        local at, h = place(), P.frame:GetHeight()
        setSteps(8)
        T.eq(place(), at, "the window and its panel stay put")
        T.ok(P.frame:GetHeight() > h, "only its height grows")
        T.eq(W.anchor:GetHeight(), P.frame:GetHeight(), "the mover's box is the window")
        if mover then T.ok(#DaylightWorld.Saved() > 0, "the mover saves the spot it now holds") end
    end)
end

T.test("after a reload Daylight UI's mover puts the window back where Steps shown left it", function()
    scene()
    moverHolds()
    setSteps(9)
    local at = place()
    -- What Movers.Save stored: the anchor's centre.
    local cx, cy = W.anchor:GetCenter()
    -- A reload: the anchor at its first size, sized again before the mover places it by that centre.
    W.anchor:SetSize(P.BASE_WIDTH, CP.DEFAULTS.windowHeight)
    W.SizeAnchor()
    W.anchor:ClearAllPoints()
    W.anchor:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx, cy)
    P:Refresh()
    settle()
    T.eq(place(), at, "the same spot, not one shifted by the change in height")
end)

-- Rows as GuideTab draws them: "M" a main step, "o" an "or" row under it.
local function rowsOf(shape)
    local rows = {}
    for c in shape:gmatch(".") do rows[#rows + 1] = { side = c == "o" or nil, key = tostring(#rows) } end
    return rows
end

T.test("a step and its \"or\" rows count as one step", function()
    scene()
    World.set(GT.ui, "rows", rowsOf("MooMMoMMM"))
    CP.db.guideSteps = 3
    T.eq(GT.ListHeight(), 6 * GT.RowHeight(), "3 steps: their 3 main rows and 3 \"or\" rows")
    CP.db.guideSteps = 1
    T.eq(GT.ListHeight(), 3 * GT.RowHeight(), "1 step: its main row and both \"or\" rows")
    CP.db.guideSteps = 15
    T.eq(GT.ListHeight(), 9 * GT.RowHeight(), "more steps than the guide has: every row")
    T.eq(GT.GripHeight(15), (9 + 15 - 6) * GT.RowHeight(), "the grip counts a missing step as one row")
end)

T.test("Steps shown lists that many steps of a real guide, with all their \"or\" rows", function()
    scene()
    CraftWorld.begin({ professions = { [LW] = 100, [TAILOR] = 60, [MINING] = 30 } })
    W.Pick(LW)
    P:Refresh()
    settle()
    -- The steps up to and including the first with an "or" row, and the rows they draw.
    local steps, rows
    for i, row in ipairs(GT.ui.rows) do
        if not row.side then
            if steps and GT.ui.rows[i - 1].side then break end
            steps = (steps or 0) + 1
        end
        rows = i
    end
    T.ok(rows > steps, "the guide has \"or\" rows within reach")
    setSteps(steps)
    T.eq({ rowsShown() }, { rows, false }, steps .. " steps show as " .. rows .. " rows, whole")
    local h = P.frame:GetHeight()
    setSteps(steps + 1)
    T.eq(P.frame:GetHeight(), h + GT.RowHeight(), "one more plain step: one row taller")
end)

T.test("the grip moves by whole steps, a step with \"or\" rows as tall as its rows", function()
    scene()
    World.set(GT.ui, "rows", rowsOf("MMooMMMMMMMMMMMMMMMMM"))
    local row = GT.RowHeight()
    T.eq(W.StepsFor(GT.GripHeight(2)), 2, "the height of two steps: two")
    T.eq(W.StepsFor(row + 1.4 * row), 1, "under halfway into the second step's three rows: one")
    T.eq(W.StepsFor(row + 1.5 * row), 2, "halfway: two")
    T.eq(W.StepsFor(GT.GripHeight(2) + row), 3, "a row past two steps: three")
end)
