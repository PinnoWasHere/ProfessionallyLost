local _, CP = ...
if CP.stopped then return end

-- The first-run tour: eight cards over the guide window on Daylight UI's own tour card
-- (DaylightUI.Tour), so the dim, the light, the card, Back, Next and Skip tour are
-- Daylight UI's. The mouse reaches the window the whole time.
--
-- It comes with the first show of the guide window on each character. Done, Skip tour and
-- Escape save CP.charDB.tourSeen. A fight, the window closing or a /reload end it without
-- saving, so the next show brings it again. The options page's Take the tour runs it again.
--
-- The tour opens what its cards talk about: One view, the window unfolded, the Shop tab, the
-- gathering panel in Follow the guide. However it ends, it puts each of these back.
--
-- Every engine call goes through Tour.Engine(), the one seam a standalone ProfLost fills
-- with its own engine.

local Panel, Window, GP = CP.Panel, CP.Window, CP.GatherPanel
local panel = Panel.frame

local Tour = {}
CP.Tour = Tour

Tour.KEY = "proflost"

-- After the window shows, before the first card: the window lays itself out first.
Tour.DELAY = 0.5

-- How often a waiting start looks again while another tour runs.
Tour.POLL = 0.5

-- Seconds a card waits after switching a tab or the view, so the light finds the new layout.
Tour.SETTLE = 0.2

-- The gathering panel's card waits for the panel's slide.
Tour.GATHER_SETTLE = GP.SLIDE + 0.1

-- The engine's calls ProfLost uses (Daylight UI internals).
Tour.CALLS = { "Run", "Running", "Stop", "Pop" }

-- Daylight UI's tour engine as { Run, Running, Stop, Pop }, or nil when it lacks any of them.
function Tour.Engine()
    local dui = rawget(_G, "DaylightUI")
    local engine = type(dui) == "table" and dui.Tour
    if type(engine) ~= "table" then return nil end
    local out = {}
    for _, name in ipairs(Tour.CALLS) do
        if type(engine[name]) ~= "function" then return nil end
        out[name] = engine[name]
    end
    return out
end

-- `text` in the tour's accent, as its cards name a button.
local function pop(text)
    local E = Tour.Engine()
    local ok, out = false, nil
    if E then ok, out = pcall(E.Pop, text) end
    return ok and type(out) == "string" and out or text
end

-- Every word the cards show. %s slots take accented names.
Tour.WORDS = {
    welcome = { title = "Welcome to Professionally Lost",
        text = "A quick look at the guide window. %s and %s move through the cards; %s closes them." },
    profession = { title = "Your profession",
        text = "The dropdown picks the profession the guide shows. %s shows one profession's steps, %s a card for each profession." },
    steps = { title = "The steps",
        text = "What to craft from your skill up to the cap, in order. Click a step to see it in full below." },
    skillups = { title = "Available Skill Ups",
        text = "Crafts your spare loot can make right now for skill points. It never uses materials your guide needs, so your steps stay covered. %s makes one." },
    details = { title = "The step card",
        text = "The picked step: its materials, what you have and what you still need, and the button to craft it or open the profession." },
    shop = { title = "Shop",
        text = "Everything the guide needs you to buy, priced from the auction house. Buy it there and the rows tick off.",
        hidden = "With %s off, the guide plans by auction house prices and the %s tab lists what to buy." },
    gather = { title = "Gathering window",
        text = "What you can gather in this zone, with a route on the map. %s gathers what your guides need.",
        none = "Once you have a gathering profession, this window lists what to gather in your zone and draws a route." },
    mode = { title = "Follow the guide or Farm",
        text = "This menu switches the route. %s gathers what your guides need; %s gathers what you pick, for gold." },
    settings = { title = "Settings",
        text = "Right-click the title for the settings. %s there shows this tour again." },
    skipped = "Tour skipped. %s in Professionally Lost's settings shows it again.",
    replay = "Take the tour",
}

local W = Tour.WORDS

-- What the tour changed, and what it found before: set by the first card, put back at the end.
local before

local function shown(f) return f ~= nil and f:IsVisible() and f or nil end

local function gathering()
    return next(CP.Gather.Skills()) ~= nil
end

-- The window as the tour found it.
local function record()
    if before then return end
    local db, char = CP.db or {}, CP.charDB or {}
    before = {
        tab = Panel.current, mode = char.guideMode,
        collapsed = db.windowCollapsed, collapsedAll = db.windowCollapsedAll,
        gatherShowing = GP.Showing(), gatherOpen = db.gatherOpen, gatherClosed = db.gatherPanelClosed,
        routeMode = db.routeMode,
    }
end

-- One view, unfolded: the dropdown, the step list and the step card all show.
local function openView()
    if Window.Mode() ~= "one" then Window.SetMode("one") end
    if Window.Folded() then Window.SetFolded(false) end
end

local function pickTab(key)
    if Panel.current ~= key then Panel.SelectTab(key) end
end

-- The gathering panel out, routing in Follow the guide.
local function openGather()
    if not gathering() then return end
    if CP.db.routeMode ~= nil then
        CP.db.routeMode = nil
        CP.GatherList.RouteChanged()
    end
    if not GP.Showing() then GP.Open() end
end

-- Puts back everything the tour changed.
function Tour.Restore()
    local b = before
    before = nil
    if not (b and CP.db) then return end
    local db = CP.db
    if db.routeMode ~= b.routeMode then
        db.routeMode = b.routeMode
        CP.GatherList.RouteChanged()
    end
    if GP.Showing() and not b.gatherShowing then GP.Close() end
    db.gatherOpen, db.gatherPanelClosed = b.gatherOpen, b.gatherClosed
    GP.Layout(true)
    if CP.charDB then CP.charDB.guideMode = b.mode end
    db.windowCollapsed, db.windowCollapsedAll = b.collapsed, b.collapsedAll
    if b.tab then pickTab(b.tab) end
    Window.Chrome()
    Panel:Refresh()
end

-- The stops ---------------------------------------------------------------------------

local function guideStop() openView(); pickTab("guide") end

Tour.STEPS = {
    { id = "welcome", title = W.welcome.title,
      text = function() return W.welcome.text:format(pop("Next"), pop("Back"), pop("Skip tour")) end,
      enter = function() record(); openView() end, settle = Tour.SETTLE },
    { id = "profession", title = W.profession.title,
      text = function() return W.profession.text:format(pop(Window.VIEW_WORDS.one), pop(Window.VIEW_WORDS.all)) end,
      enter = openView, settle = Tour.SETTLE,
      part = function() return shown(Window.pickButton), shown(Window.switchButton) end },
    { id = "steps", title = W.steps.title, text = W.steps.text,
      enter = guideStop, settle = Tour.SETTLE,
      part = function()
          if not CP.GuideTab.ui.live then return nil end
          return shown(CP.GuideTab.ui.scroll)
      end },
    { id = "skillups", title = W.skillups.title,
      text = function() return W.skillups.text:format(pop("Craft")) end,
      enter = guideStop, settle = Tour.SETTLE,
      part = function() return shown(CP.GuideTab.ui.impromptu) end },
    { id = "details", title = W.details.title, text = W.details.text,
      enter = guideStop, settle = Tour.SETTLE,
      part = function() return shown(CP.GuideTab.ui.details) end },
    { id = "shop", title = W.shop.title,
      text = function()
          local tab = Panel.tabs.shop
          if tab and tab.content:IsVisible() then return W.shop.text end
          return W.shop.hidden:format(pop(CP.Settings.Find("collect").label), pop(W.shop.title))
      end,
      enter = function() openView(); pickTab("shop") end, settle = Tour.SETTLE,
      part = function()
          local tab = Panel.tabs.shop
          local content = tab and shown(tab.content)
          if not content then return nil end
          return content, shown(tab.button)
      end },
    { id = "gather", title = W.gather.title,
      text = function()
          if not gathering() then return W.gather.none end
          return W.gather.text:format(pop(CP.GatherList.MODE_LABEL.level))
      end,
      enter = openGather, settle = Tour.GATHER_SETTLE,
      part = function()
          if not gathering() then return nil end
          return shown(GP.sheet)
      end },
    { id = "mode", title = W.mode.title,
      text = function() return W.mode.text:format(pop(CP.GatherList.MODE_LABEL.level), pop("Farm")) end,
      enter = openGather, settle = Tour.SETTLE,
      part = function()
          if not (gathering() and GP.Showing()) then return nil end
          return shown(CP.GatherList.head.filter)
      end },
    { id = "settings", title = W.settings.title,
      text = function() return W.settings.text:format(pop(W.replay)) end,
      part = function() return shown(Panel.logo), shown(Panel.title) end },
}

-- The engine leaves a stop with no next one only as the tour ends, however it ends.
for _, step in ipairs(Tour.STEPS) do
    step.leave = function(nextStep)
        if nextStep == nil then Tour.Restore() end
    end
end

-- Running -----------------------------------------------------------------------------

local waiting   -- the token of a start waiting for its delay or another tour

function Tour.Running()
    local E = Tour.Engine()
    return E ~= nil and E.Running(Tour.KEY) == true
end

function Tour.Waiting() return waiting ~= nil end

function Tour.Seen() return CP.charDB ~= nil and CP.charDB.tourSeen == true end

local function run(E)
    local ok = E.Run(Tour.STEPS, {
        key = Tour.KEY,
        through = true,
        skipped = W.skipped:format(pop(W.replay)),
        finished = function() if CP.charDB then CP.charDB.tourSeen = true end end,
    })
    if not ok then Tour.Restore() end
    return ok == true
end

-- Starts once the window shows, out of a fight, with no other tour running.
local function try(token)
    if waiting ~= token then return end
    local E = Tour.Engine()
    if not (E and panel:IsShown()) or InCombatLockdown() then
        waiting = nil
        return
    end
    if E.Running() then
        C_Timer.After(Tour.POLL, function() try(token) end)
        return
    end
    waiting = nil
    run(E)
end

local function queue()
    local token = {}
    waiting = token
    C_Timer.After(Tour.DELAY, function() try(token) end)
end

-- The guide window showed: the first time on this character, the tour comes with it.
function Tour.Offer()
    if not CP.charDB or Tour.Seen() or waiting or Tour.Running() then return end
    if CP.Preview and CP.Preview.On() then return end
    if InCombatLockdown() or not Tour.Engine() then return end
    queue()
end

-- Runs the tour again from its first card, opening the guide window if it is shut. False in
-- a fight, while it runs, or without the engine.
function Tour.Replay()
    if not Tour.Engine() or InCombatLockdown() or Tour.Running() then return false end
    if not panel:IsShown() then Window.Open() end
    if not panel:IsShown() then return false end
    if not waiting then queue() end
    return true
end

-- Ends the tour, or a start still waiting, without saving.
function Tour.End()
    waiting = nil
    local E = Tour.Engine()
    if E and Tour.Running() then E.Stop() end
end

panel:HookScript("OnShow", function() Tour.Offer() end)
panel:HookScript("OnHide", function() Tour.End() end)
CP:On("PLAYER_REGEN_DISABLED", function() Tour.End() end)
