-- Each profession keeps the row the player picked in its guide while the player looks at
-- other professions and comes back (owner decision 2026-11-16, "Yes keep picked row").

local CP = ProfLost
local W, P = CP.Window, CP.Panel
local LW, TAILOR = 165, 197
local DUROTAR = 1411

-- Leatherworking and Tailoring known, the guide on Leatherworking in One mode with its
-- third step picked. Returns the guide's ui and the picked row.
local function scene()
    MapWorld.begin({ zone = DUROTAR, level = 20, side = "Horde" })
    CraftWorld.begin({ professions = { [LW] = 100, [TAILOR] = 60 } })
    World.set(CP.db, "hideInCombat", false)
    World.set(CP.db, "windowClosed", nil)
    World.onEnd(function()
        W.CancelPick()
        W.opened = false
        W.Update()
    end)
    CraftWorld.Open(LW)
    CraftWorld.Close()
    CraftWorld.Open(TAILOR)
    CraftWorld.Close()
    World.set(CP.charDB, "guideMode", "one")
    W.Pick(LW)
    P.tabs.guide.button:GetScript("OnClick")()
    T.advance(1)
    local ui = CP.GuideTab.ui
    local row = ui.rows[3]
    T.ok(row ~= nil and row.key ~= ui.rows[1].key, "a row past the current step")
    CP.GuideTab.Pick(row)
    T.advance(0.2)
    return ui, row
end

local function shownKey()
    return CP.GuideTab.PickKey()
end

T.test("the dropdown: another profession and back keeps the picked row", function()
    local ui, row = scene()
    local want = shownKey()
    W.Pick(TAILOR)
    T.advance(0.2)
    T.eq(ui.live.prof.id, TAILOR, "Tailoring shown")
    W.Pick(LW)
    T.advance(0.2)
    T.eq(ui.live.prof.id, LW, "Leatherworking shown")
    T.eq(shownKey(), want, "the pick survives")
end)

T.test("each profession keeps its own pick", function()
    local ui, row = scene()
    W.Pick(TAILOR)
    T.advance(0.2)
    local mine = ui.rows[2]
    CP.GuideTab.Pick(mine)
    W.Pick(LW)
    T.advance(0.2)
    T.eq(shownKey(), LW .. ":" .. row.key, "Leatherworking's")
    W.Pick(TAILOR)
    T.advance(0.2)
    T.eq(shownKey(), TAILOR .. ":" .. mine.key, "Tailoring's")
end)

T.test("opening another profession's window and coming back keeps the pick", function()
    local ui, row = scene()
    CraftWorld.Open(TAILOR)
    T.advance(0.5)
    T.eq(ui.live.prof.id, TAILOR, "the guide followed to Tailoring")
    CraftWorld.Close()
    T.advance(1)
    CraftWorld.Open(LW)
    T.advance(0.5)
    T.eq(ui.live.prof.id, LW, "back on Leatherworking")
    T.eq(shownKey(), LW .. ":" .. row.key, "the pick is kept")
    CraftWorld.Close()
end)

T.test("Single and All mode keep the pick", function()
    local ui, row = scene()
    W.SetMode("all")
    World.onEnd(function() W.SetMode("one") end)
    T.advance(0.5)
    W.SetMode("one")
    T.advance(0.5)
    T.eq(shownKey(), LW .. ":" .. row.key, "kept")
end)

T.test("the launcher closing and opening the window keeps the pick", function()
    local _, row = scene()
    CP.Launcher.Click("LeftButton")
    T.advance(0.5)
    CP.Launcher.Click("LeftButton")
    T.advance(0.5)
    T.eq(shownKey(), LW .. ":" .. row.key, "kept")
end)

T.test("a reload keeps the pick: the saved variables hold it", function()
    local _, row = scene()
    CP.GuideTab.Forget()
    CP.Panel:Refresh()
    T.advance(0.5)
    T.eq(shownKey(), LW .. ":" .. row.key, "kept")
end)

-- The guide's plan without the steps whose start is in the returned set: a setting switched on
-- and off again re-plans without a step, then with it.
local function dropSteps()
    local gone = {}
    local live = W.Live
    World.set(W, "Live", function(...)
        local l = live(...)
        if not (next(gone) and l and l.plan) then return l end
        local copy = setmetatable({ plan = {} }, { __index = l })
        for _, st in ipairs(l.plan) do
            if not gone[st.from] then copy.plan[#copy.plan + 1] = st end
        end
        return copy
    end)
    return gone
end

local function redraw()
    P:Refresh()
    T.advance(0.2)
end

-- The scene with a craft step past the current one picked: its row key is the step's start.
local function craftPicked()
    local ui = scene()
    local row
    for i = 2, #ui.rows do
        local r = ui.rows[i]
        if not row and r.spell and not (r.train or r.rank or r.side) then row = r end
    end
    T.ok(row ~= nil, "a craft step past the current one")
    CP.GuideTab.Pick(row)
    T.advance(0.2)
    return ui, row
end

T.test("a re-plan that drops the picked step and brings it back keeps the pick", function()
    local ui, row = craftPicked()
    local gone = dropSteps()
    gone[row.from] = true
    redraw()
    for _, r in ipairs(ui.rows) do T.ok(r.key ~= row.key, "the picked step is out of the plan") end
    T.eq(shownKey(), LW .. ":" .. ui.rows[1].key, "the current step shows while the step is gone")
    gone[row.from] = nil
    redraw()
    T.eq(shownKey(), LW .. ":" .. row.key, "the player's pick is back")
end)

T.test("a row picked while the old pick is gone stays picked when it comes back", function()
    local ui, row = craftPicked()
    local gone = dropSteps()
    gone[row.from] = true
    redraw()
    local other = ui.rows[2]
    CP.GuideTab.Pick(other)
    T.advance(0.2)
    gone[row.from] = nil
    redraw()
    T.eq(shownKey(), LW .. ":" .. other.key, "the later pick holds")
end)

T.test("a shown step dropped and brought back comes back after an older pick that stays gone", function()
    local ui, row = craftPicked()
    local gone = dropSteps()
    gone[row.from] = true
    redraw()
    local shown = ui.rows[1]
    T.ok(shown.from ~= nil, "the current step has a start")
    gone[shown.from] = true
    redraw()
    gone[shown.from] = nil
    redraw()
    T.eq(shownKey(), LW .. ":" .. shown.key, "the step shown before the second re-plan")
end)

T.test("a pick the plan no longer holds falls back to the current step", function()
    local ui = scene()
    CP.GuideTab.Pick({ key = "gone:step" })
    T.advance(0.5)
    T.eq(shownKey(), LW .. ":" .. ui.rows[1].key, "the first row is picked")
end)
