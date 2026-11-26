-- The first-run tour (UI/Tour.lua, its spec's R-01 to R-12) on a
-- mock of Daylight UI's tour engine.

local CP = ProfLost
local Tour, W, P, GP = CP.Tour, CP.Window, CP.Panel, CP.GatherPanel
local LW, MINING = 165, 186
local DUROTAR = 1411

-- Mock: Daylight UI's tour engine as DaylightUI/Tour.lua's header and code describe it.
-- Run refuses while a tour runs, in a fight or with no stops, and enters the first stop.
-- A move leaves the stop with the next one, then enters that one. Every end leaves the
-- stop with nil; finished(how) runs on "done" and "skip" only. Pop wraps the text.
local function mockEngine()
    local E = { runs = 0 }
    local S
    local function finish(how)
        local s = S
        local step = s.list[s.i]
        if step.leave then step.leave(nil) end
        S = nil
        if how and s.opts.finished then s.opts.finished(how) end
    end
    local function go(i)
        local list = S.list
        if list[S.i].leave then list[S.i].leave(list[i]) end
        S.i = i
        if list[i].enter then list[i].enter() end
    end
    function E.Run(list, opts)
        if S or InCombatLockdown() or #list == 0 then return false end
        S = { list = list, opts = opts or {}, i = 1 }
        E.runs, E.list, E.opts = E.runs + 1, list, S.opts
        if list[1].enter then list[1].enter() end
        return true
    end
    function E.Running(key)
        if key == nil then return S ~= nil end
        return S ~= nil and S.opts.key == key
    end
    function E.Stop() if S then finish() end end
    function E.Pop(text) return "[" .. text .. "]" end
    function E.Next()
        if S.i < #S.list then return go(S.i + 1) end
        finish("done")
    end
    function E.Back() if S.i > 1 then go(S.i - 1) end end
    function E.Skip() finish("skip") end
    function E.Step() return S and S.list[S.i] end
    -- Another addon's tour (Daylight UI's own), started and ended from outside.
    function E.Other() S = { list = { {} }, opts = { key = "tour" }, i = 1 } end
    function E.EndOther() S = nil end
    return E
end

-- A shut guide window on a character with Leatherworking and Mining (or `spec.professions`),
-- the Shop tab shown (Gather it yourself off) unless `spec.collect`, the gathering panel
-- attached and folded. `spec.engine = false` leaves Daylight UI without its tour engine.
local function scene(spec)
    spec = spec or {}
    MapWorld.begin({ zone = DUROTAR, level = 20, side = "Horde" })
    CraftWorld.begin({ professions = spec.professions or { [LW] = 100, [MINING] = 30 } })
    for _, key in ipairs({ "hideInCombat", "windowClosed", "windowCollapsed", "windowCollapsedAll", "windowLocked",
                           "windowPoint", "gatherOpen", "gatherAttached", "gatherPanelClosed", "gatherSide",
                           "routeMode", "collect" }) do
        World.set(CP.db, key, CP.db[key])
    end
    CP.db.hideInCombat, CP.db.windowLocked = true, nil
    CP.db.collect = spec.collect == true
    CP.db.gatherAttached, CP.db.gatherOpen, CP.db.gatherPanelClosed = true, false, nil
    CP.db.windowCollapsed, CP.db.windowCollapsedAll, CP.db.routeMode = nil, nil, nil
    World.set(CP.charDB, "guideMode", "one")
    World.set(CP.charDB, "tourSeen", nil)
    local tab = P.current
    World.onEnd(function()
        Tour.End()
        T.fire("PLAYER_REGEN_ENABLED")
        if P.current ~= tab then P.SelectTab(tab) end
        W.opened = false
        W.Update()
    end)
    W.Close()
    T.advance(0.1)
    local E = mockEngine()
    if spec.engine ~= false then World.set(_G, "DaylightUI", { Tour = E }) end
    return E
end

-- Opens the guide window and waits out the tour's start delay.
local function open()
    W.Open()
    T.ok(P.frame:IsShown(), "the guide window")
    T.advance(Tour.DELAY + 0.01)
end

-- Moves the mock to the next card and lets that card's enter settle.
local function nextCard(E)
    E.Next()
    T.advance(0.5)
end

local function seen() return CP.charDB.tourSeen end

local function replayButton()
    for _, s in ipairs(CP.Settings.LIST) do
        if s.kind == "button" and s.label == "Take the tour" then return s end
    end
end

-- R-12, R-08: the seam --------------------------------------------------------------------

T.test("Tour.Engine is Daylight UI's four tour calls, or nil when any is missing", function()
    local E = scene()
    local got = Tour.Engine()
    T.ok(got ~= nil, "engine present")
    T.eq(got.Run, E.Run)
    T.eq(got.Running, E.Running)
    T.eq(got.Stop, E.Stop)
    T.eq(got.Pop, E.Pop)
    World.set(E, "Pop", nil)
    T.eq(Tour.Engine(), nil, "an engine without Pop")
    World.set(_G, "DaylightUI", { Tour = "not a table" })
    T.eq(Tour.Engine(), nil, "no Tour table")
    World.set(_G, "DaylightUI", nil)
    T.eq(Tour.Engine(), nil, "no Daylight UI")
end)

T.test("every engine call goes through Tour.Engine", function()
    local E = scene()
    -- Tour.Engine hands over the mock itself; a read of DaylightUI.Tour anywhere else errors.
    World.set(Tour, "Engine", function() return E end)
    World.set(_G, "DaylightUI", setmetatable({}, { __index = function(_, k)
        if k == "Tour" then error("DaylightUI.Tour read past Tour.Engine") end
    end }))
    open()
    T.eq(E.runs, 1, "the start")
    for _ = 1, 3 do nextCard(E) end
    E.Back()
    E.Skip()
    T.ok(Tour.Replay(), "the replay")
    T.advance(Tour.DELAY + 0.01)
    T.eq(E.runs, 2)
    T.fire("PLAYER_REGEN_DISABLED")
    T.ok(not E.Running(), "the fight's stop")
    T.fire("PLAYER_REGEN_ENABLED")
    W.Close()
    T.eq(replayButton().when(), true, "the options row")
end)

-- R-01: the first open -----------------------------------------------------------------------

T.test("the first open of the guide window runs the tour once, key proflost, 9 stops, mouse through", function()
    local E = scene()
    open()
    T.eq(E.runs, 1)
    T.eq(E.opts.key, "proflost")
    T.eq(#E.list, 9)
    T.eq(E.opts.through, true, "the mouse reaches the window")
    T.ok(E.opts.skipped:find("[Take the tour]", 1, true), E.opts.skipped)
    T.ok(Tour.Running())
end)

T.test("the tour waits for the window's start delay", function()
    local E = scene()
    W.Open()
    T.advance(Tour.DELAY / 2)
    T.eq(E.runs, 0, "not before the delay")
    T.advance(Tour.DELAY)
    T.eq(E.runs, 1)
end)

T.test("no start in a fight", function()
    local E = scene()
    CP.db.hideInCombat = false
    World.patch("InCombatLockdown", function() return true end)
    open()
    T.eq(E.runs, 0)
    T.eq(seen(), nil)
end)

-- R-02: once per character -------------------------------------------------------------------

T.test("Next on the last card saves tourSeen; reopening the window runs nothing", function()
    local E = scene()
    open()
    for _ = 1, #E.list do nextCard(E) end
    T.ok(not Tour.Running(), "done")
    T.eq(seen(), true)
    W.Close()
    open()
    T.eq(E.runs, 1, "once")
end)

T.test("Skip tour saves tourSeen too", function()
    local E = scene()
    open()
    nextCard(E)
    E.Skip()
    T.eq(seen(), true)
    W.Close()
    open()
    T.eq(E.runs, 1)
end)

-- R-03: the 9 cards ----------------------------------------------------------------------------

T.test("the 9 cards, in order, each lighting its part", function()
    local E = scene()
    open()
    local ids = {}
    for i, step in ipairs(E.list) do ids[i] = step.id end
    T.eq(ids, { "welcome", "profession", "steps", "skillups", "details", "shop", "gather", "mode", "settings" })
    for _, step in ipairs(E.list) do
        T.eq(step.title, Tour.WORDS[step.id].title, step.id)
        T.ok(type(step.text) == "string" or type(step.text) == "function", step.id .. " text")
        T.ok(not step.wait, step.id .. " never waits for the player")
    end

    T.eq(E.Step().id, "welcome")
    T.eq(E.Step().part, nil, "the welcome sits in the middle")
    T.ok(E.Step().text():find("[Skip tour]", 1, true), "button names in Pop's accent")

    nextCard(E)
    local a, b = E.Step().part()
    T.eq(a, W.pickButton, "the profession dropdown")
    T.eq(b, W.switchButton, "and the View switch")
    T.ok(E.Step().text():find("[Single]", 1, true) and E.Step().text():find("[All]", 1, true))

    nextCard(E)
    T.eq(E.Step().part(), CP.GuideTab.ui.scroll, "the step list")
    T.eq(P.current, "guide")

    nextCard(E)
    T.eq(E.Step().part(), CP.GuideTab.ui.impromptu, "the Available Skill Ups area")
    T.ok(E.Step().text():find("never uses materials your guide needs", 1, true), "says it spares the guide's materials")
    T.ok(E.Step().text():find("[Craft]", 1, true), "button name in Pop's accent")

    nextCard(E)
    T.eq(E.Step().part(), CP.GuideTab.ui.details, "the details box")

    nextCard(E)
    T.eq(P.current, "shop", "the tour switches to the Shop tab")
    a, b = E.Step().part()
    T.eq(a, P.tabs.shop.content, "the Shop tab")
    T.eq(b, P.tabs.shop.button)
    T.eq(E.Step().text(), Tour.WORDS.shop.text)

    nextCard(E)
    T.ok(GP.Showing(), "the tour opens the gathering panel")
    T.eq(CP.db.routeMode, nil, "in Follow the guide")
    T.eq(E.Step().part(), GP.sheet, "the gathering panel")

    nextCard(E)
    T.eq(E.Step().part(), CP.GatherList.head.filter, "the Farm and Follow the guide menu")
    T.ok(E.Step().text():find("[Farm]", 1, true))

    nextCard(E)
    a, b = E.Step().part()
    T.eq(a, P.logo, "the window title")
    T.eq(b, P.title)
    T.ok(E.Step().text():find("Right-click the title", 1, true) and E.Step().text():find("[Take the tour]", 1, true))
end)

T.test("Back to a guide card switches back to the Guide tab", function()
    local E = scene()
    open()
    for _ = 1, 5 do nextCard(E) end
    T.eq(P.current, "shop")
    E.Back()
    T.eq(E.Step().id, "details")
    T.eq(P.current, "guide")
end)

-- R-04: a missing part -------------------------------------------------------------------------

T.test("with no profession, no gathering skill and no Shop tab, those cards sit in the middle and the tour ends", function()
    local E = scene({ professions = {}, collect = true })
    open()
    T.eq(E.runs, 1)
    local missing = {}
    for _ = 1, #E.list - 1 do
        nextCard(E)
        local step = E.Step()
        if step.part and step.part() == nil then missing[#missing + 1] = step.id end
        T.ok(step.text == nil or type(step.text) == "string" or #step.text() > 0, step.id .. " keeps its text")
    end
    T.eq(missing, { "steps", "skillups", "details", "shop", "gather", "mode" })
    T.ok(not GP.Showing(), "no gathering panel opened without a gathering skill")
    T.eq(Tour.WORDS.gather.none, E.list[7].text(), "the gathering card says what the window needs")
    T.ok(E.list[6].text():find("[Gather it yourself]", 1, true), "the Shop card says where Shop comes from")
    E.Next()
    T.eq(seen(), true, "the tour reaches its end")
end)

-- R-05: ends without saving ------------------------------------------------------------------

local function endsUnseen(name, stop)
    T.test(name .. " ends the tour without saving; the next open shows it again", function()
        local E = scene()
        open()
        nextCard(E)
        nextCard(E)
        stop(E)
        T.ok(not Tour.Running(), "ended")
        T.eq(seen(), nil, "not seen")
        T.fire("PLAYER_REGEN_ENABLED")
        W.Close()
        open()
        T.eq(E.runs, 2, "again on the next open")
    end)
end

endsUnseen("a fight", function() T.fire("PLAYER_REGEN_DISABLED") end)
endsUnseen("closing the window", function() W.Close() end)
endsUnseen("Tour.Stop from elsewhere", function(E) E.Stop() end)

T.test("a fight while the window stays shown ends the tour too", function()
    local E = scene()
    CP.db.hideInCombat = false
    open()
    T.fire("PLAYER_REGEN_DISABLED")
    T.ok(P.frame:IsShown(), "the window stays")
    T.ok(not Tour.Running())
    T.eq(seen(), nil)
    T.eq(E.runs, 1)
end)

T.test("closing the window while the start waits cancels it", function()
    local E = scene()
    W.Open()
    W.Close()
    T.advance(Tour.DELAY + 0.1)
    T.eq(E.runs, 0)
    T.ok(not Tour.Waiting())
end)

-- R-06: puts things back ---------------------------------------------------------------------

-- The window's state the tour may change.
local function state()
    return { mode = CP.charDB.guideMode, collapsed = CP.db.windowCollapsed, collapsedAll = CP.db.windowCollapsedAll,
             tab = P.current, gatherOpen = CP.db.gatherOpen, gatherClosed = CP.db.gatherPanelClosed,
             routeMode = CP.db.routeMode, folded = P.folded }
end

local ENDS = {
    done = function(E) while Tour.Running() do E.Next() end end,
    skip = function(E) E.Skip() end,
    fight = function() T.fire("PLAYER_REGEN_DISABLED") end,
    close = function() W.Close() end,
    stop = function(E) E.Stop() end,
}

for _, how in ipairs({ "done", "skip", "fight", "close", "stop" }) do
    T.test("after it ends by " .. how .. ", the view, fold, tab and gathering panel are as it found them", function()
        local E = scene()
        CP.charDB.guideMode = "all"
        CP.db.windowCollapsedAll = true
        CP.db.routeMode = "farm"
        -- A first open with the tour seen sets the state up; the second, unseen, brings the tour.
        CP.charDB.tourSeen = true
        open()
        P.SelectTab("shop")
        W.Chrome()
        local was = state()
        local wasShowing = GP.Showing()
        T.eq(was.folded, true, "folded in All")
        W.Close()
        CP.charDB.tourSeen = nil
        open()
        T.eq(E.runs, 1)
        T.eq(W.Mode(), "one", "the tour shows One view")
        T.ok(not P.folded, "unfolded")
        for _ = 1, 7 do nextCard(E) end
        T.ok(GP.Showing(), "the gathering panel is out")
        T.eq(CP.db.routeMode, nil, "in Follow the guide")
        ENDS[how](E)
        T.advance(0.5)
        T.ok(not Tour.Running())
        T.eq(state(), was)
        if how ~= "close" and how ~= "fight" then T.eq(GP.Showing(), wasShowing, "the gathering panel as it was") end
    end)
end

T.test("a tour ended on a guide card puts back the tab it found", function()
    local E = scene()
    open()
    E.Stop()
    P.SelectTab("shop")
    W.Close()
    CP.charDB.tourSeen = nil
    open()
    nextCard(E)
    nextCard(E)
    T.eq(P.current, "guide")
    E.Skip()
    T.eq(P.current, "shop")
end)

-- R-07: another tour ------------------------------------------------------------------------

T.test("while another tour runs, the start waits and runs after it ends", function()
    local E = scene()
    E.Other()
    open()
    T.eq(E.runs, 0, "not over Daylight UI's own tour")
    T.ok(Tour.Waiting())
    T.advance(Tour.POLL * 3)
    T.eq(E.runs, 0, "still waiting")
    E.EndOther()
    T.advance(Tour.POLL + 0.01)
    T.eq(E.runs, 1, "starts when it ends")
    T.ok(Tour.Running())
end)

-- R-08: no engine --------------------------------------------------------------------------

T.test("without the engine: no tour, no error, tourSeen untouched, the options button hidden", function()
    scene({ engine = false })
    World.set(_G, "DaylightUI", { Tour = { Run = function() error("called") end } })
    open()
    T.ok(not Tour.Waiting(), "nothing queued")
    T.ok(not Tour.Running())
    T.eq(seen(), nil, "tourSeen untouched")
    local s = replayButton()
    T.ok(s ~= nil, "the button row")
    T.eq(s.when(), false, "hidden without the engine")
    T.eq(Tour.Replay(), false)
    local hidden
    for _, g in ipairs(CP.Plugin.Pages()[1].groups) do
        for _, item in ipairs(g.items) do
            if item.type == "button" and item.text == "Take the tour" then hidden = item.hidden end
        end
    end
    T.ok(hidden ~= nil and hidden() == true, "the options row hides")
end)

-- R-09: preview ----------------------------------------------------------------------------

T.test("in preview mode the window's open starts nothing; Take the tour still runs it", function()
    local E = scene()
    World.set(CP.Preview, "On", function() return true end)
    open()
    T.eq(E.runs, 0)
    T.ok(Tour.Replay())
    T.advance(Tour.DELAY + 0.01)
    T.eq(E.runs, 1)
end)

-- R-10: replay ------------------------------------------------------------------------------

T.test("Take the tour opens the shut window and runs the tour from card 1", function()
    local E = scene()
    CP.charDB.tourSeen = true
    T.ok(not P.frame:IsShown(), "shut")
    local s = replayButton()
    T.eq(s.when(), true, "shown with the engine")
    T.eq(s.group, "Help")
    s.apply()
    T.ok(P.frame:IsShown(), "the window opens")
    T.advance(Tour.DELAY + 0.01)
    T.eq(E.runs, 1)
    T.eq(E.Step().id, "welcome", "from the first card")
    nextCard(E)
    nextCard(E)
    E.Skip()
    s.apply()
    T.advance(Tour.DELAY + 0.01)
    T.eq(E.runs, 2, "again with the window already open")
    T.eq(E.Step().id, "welcome")
end)

T.test("Take the tour does nothing while the tour runs or in a fight", function()
    local E = scene()
    open()
    T.eq(Tour.Replay(), false, "already running")
    E.Skip()
    World.patch("InCombatLockdown", function() return true end)
    T.eq(Tour.Replay(), false, "in a fight")
end)
