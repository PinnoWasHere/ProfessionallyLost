-- The guide window always stands free (DOCKLESS-01, owner 2026-11-20: too many addons touch
-- the profession window, and a tester on Daylight UI 2.0 with a plugin got "Open" in place of
-- the craft button).
--
-- Whoever draws the profession window (the game, Daylight UI, DaylightMogul or another addon),
-- the guide window keeps its own place, size, strata and close. The craft button follows the
-- game's trade skill events, a state query after a /reload, and Daylight UI's craft API. A
-- save from a docking build loses its dock keys once, and a player who kept only the docked
-- window open finds the free one open.

local CP = ProfLost
local W, P, H = CP.Window, CP.Panel, CP.Host
local LW, TAILOR = 165, 197
local DUROTAR = 1411

-- Who draws the profession window: the game's (Daylight UI's own off), Daylight UI's with
-- its plugin view, DaylightMogul's, or another addon's (the game's frame stays hidden).
local HOSTS = { "game", "daylight", "mogul", "foreign" }

local POINT = { "TOPLEFT", "BOTTOMLEFT", 100, 900 }

local function scene(host)
    Visual.begin()
    if host == "daylight" then
        DaylightWorld.begin({ plugin = true, craftWindow = true })
    elseif host == "mogul" then
        DaylightWorld.begin({ plugin = true, mogul = true })
        MogulWorld.begin({ craftWindow = true })
    else
        DaylightWorld.begin({ plugin = true, craftWindow = false })
    end
    MapWorld.begin({ zone = DUROTAR, level = 20, side = "Horde", shareSolves = true })
    CraftWorld.begin({ professions = { [LW] = 100, [TAILOR] = 60 } })
    World.set(CP.db, "windowClosed", nil)
    World.set(CP.db, "hideInCombat", true)
    World.set(CP.db, "windowCollapsed", nil)
    World.set(CP.db, "windowCollapsedAll", nil)
    World.set(CP.db, "gatherAttached", true)
    World.set(CP.db, "gatherOpen", true)
    World.set(CP.db, "windowPoint", { POINT[1], POINT[2], POINT[3], POINT[4] })
    World.set(CP.charDB, "guideMode", "one")
    World.set(W.managed, "mover", false)
    World.onEnd(function()
        CraftWorld.Close()
        W.CancelPick()
        W.opened = false
        T.fire("PLAYER_REGEN_ENABLED")
        W.Update()
    end)
    W.PlaceAnchor()
    W.Update()
    T.advance(0.5)
end

local function settle() T.advance(0.5) end

local function open(host, line)
    CraftWorld.Open(line or LW, nil, host == "foreign" and "foreign" or nil)
    settle()
end

local function rect(f)
    local l, b, r, t = Visual.Resolve(f)
    return { l, b, r, t }
end

-- The step card's buttons on Leatherworking's guide.
local function card()
    W.Pick(LW)
    P.tabs.guide.button:GetScript("OnClick")()
    return CP.GuideTab.ui.details
end

-- 1. Free with every profession window ----------------------------------------------------------

for _, host in ipairs(HOSTS) do
    T.test(("%s window: the guide window stays where it stood, free, and the card crafts"):format(host), function()
        scene(host)
        local before = rect(P.frame)
        local level = P.frame:GetFrameLevel()
        open(host)
        T.ok(P.frame:IsShown(), "it shows")
        T.eq(P.frame:GetParent(), UIParent, "on UIParent")
        T.eq(P.frame:GetFrameStrata(), CP.Style.WINDOW_STRATA, "in its own strata")
        T.eq(P.frame:GetFrameLevel(), level, "at its own level")
        local now = rect(P.frame)
        T.eq(now[1], before[1], "its left edge holds")
        T.eq(now[4], before[4], "its top edge holds")
        T.eq(W.OpenID(), LW, "the open profession counts")
        local d = card()
        T.ok(d.craftAll.label:GetText() ~= "Open", "the card's button crafts: " .. tostring(d.craftAll.label:GetText()))
        Visual.Check(host .. " open")
        CraftWorld.Close()
        settle()
        T.ok(P.frame:IsShown(), "closing the profession window leaves it")
        T.eq(rect(P.frame)[4], before[4], "where it stood")
        T.eq(W.OpenID(), nil)
        T.eq(card().craftAll.label:GetText(), "Open", "the card reads Open again")
    end)
end

T.test("the close X closes the guide window, and a profession window opening keeps it closed", function()
    scene("game")
    W.closeButton:GetScript("OnClick")(W.closeButton)
    T.ok(not P.frame:IsShown() and W.Closed(), "closed")
    open("game")
    T.ok(not P.frame:IsShown(), "the profession window doesn't bring it back")
    SlashCmdList.PROFLOST("")
    T.advance(0.2)
    T.ok(P.frame:IsShown() and not W.Closed(), "/proflost opens it")
end)

T.test("the lock and fold buttons show while a profession window is open", function()
    scene("game")
    open("game")
    T.ok(W.lockButton:IsShown() and W.foldButton:IsShown(), "both on the title bar")
    W.SetFolded(true)
    T.ok(P.folded, "the window folds with a profession window open")
    W.SetFolded(false)
end)

T.test("in combat the guide window steps aside by its setting, profession window or not", function()
    scene("game")
    open("game")
    World.patch("InCombatLockdown", function() return true end)
    T.fire("PLAYER_REGEN_DISABLED")
    T.ok(not P.frame:IsShown(), "hidden in combat")
    T.fire("PLAYER_REGEN_ENABLED")
    T.ok(P.frame:IsShown(), "back after")
end)

-- 2. The open profession, without frame names ------------------------------------------------------

T.test("a frame named like the game's window counts for nothing; the trade skill does", function()
    scene("game")
    open("game")
    T.eq(W.OpenID(), LW)
    ProfessionsFrame:Hide()
    T.eq(W.OpenID(), LW, "the game's frame hidden: the open trade skill still counts")
    T.fire("TRADE_SKILL_CLOSE")
    T.eq(W.OpenID(), nil, "TRADE_SKILL_CLOSE: shut, though the data still names the profession")
end)

T.test("Daylight UI's craft API counts its window open", function()
    scene("daylight")
    open("daylight")
    World.set(CP.Professions, "tradeSkillOpen", false)
    T.eq(H.CraftProfession(), LW, "its API lists Leatherworking")
    T.eq(W.OpenID(), LW, "so the profession counts as open")
    T.eq(H.Holder(), "daylight")
end)

-- A /reload with the window open sends no TRADE_SKILL_SHOW: the reload's
-- PLAYER_ENTERING_WORLD asks the game.
local function reloadWithWindowOpen()
    World.set(CP.Professions, "tradeSkillOpen", false)
    T.eq(W.OpenID(), nil, "before the query, nothing says the window is open")
    T.fire("PLAYER_ENTERING_WORLD", false, true)
    settle()
end

for _, host in ipairs({ "game", "foreign" }) do
    T.test(("%s window open through a /reload: the card still crafts"):format(host), function()
        scene(host)
        open(host)
        reloadWithWindowOpen()
        T.eq(W.OpenID(), LW, "the reload's query finds the open profession")
        T.ok(card().craftAll.label:GetText() ~= "Open", "the card crafts")
        CraftWorld.Close()
        settle()
        T.eq(W.OpenID(), nil, "and the window closing still shuts it")
    end)
end

T.test("a /reload with no profession window open finds none", function()
    scene("game")
    T.fire("PLAYER_ENTERING_WORLD", false, true)
    settle()
    T.eq(W.OpenID(), nil)
    T.eq(CP.Professions.tradeSkillOpen, false)
end)

T.test("a /reload while the game says its trade skill isn't ready finds none", function()
    scene("game")
    open("game")
    World.patch("C_TradeSkillUI.IsTradeSkillReady", function() return false end)
    reloadWithWindowOpen()
    T.eq(W.OpenID(), nil)
end)

T.test("a login or a loading screen asks nothing: the events hold", function()
    scene("game")
    open("game")
    World.set(CP.Professions, "tradeSkillOpen", false)
    T.fire("PLAYER_ENTERING_WORLD", true, false)
    T.fire("PLAYER_ENTERING_WORLD", false, false)
    T.eq(W.OpenID(), nil, "no TRADE_SKILL_SHOW, no reload: shut")
end)

for _, case in ipairs({
    { "IsTradeSkillLinked", "another player's linked recipes" },
    { "IsTradeSkillGuild", "the guild's list" },
    { "IsNPCCrafting", "an NPC's crafting" },
}) do
    T.test(("%s through a /reload still doesn't count"):format(case[2]), function()
        scene("game")
        open("game")
        World.patch("C_TradeSkillUI." .. case[1], function() return true end)
        reloadWithWindowOpen()
        T.eq(W.OpenID(), nil)
    end)
end

-- 3. Saved state from a docking build ------------------------------------------------------------

-- A copy of `db` through login's carry-over, as a docking build's save loads.
local function carried(db)
    local copy = {}
    for k, v in pairs(db) do copy[k] = v end
    return CP.CarryOver(copy)
end

T.test("a docking build's save loses its dock keys once", function()
    local db = carried({ dockSide = "LEFT", dockClosed = true, windowClosed = true, gatherSide = "left" })
    T.eq(db.dockSide, nil)
    T.eq(db.dockClosed, nil)
    T.eq(db.windowClosed, true, "closed both ways: it stays closed")
    T.eq(db.gatherSide, "left", "the gathering panel's side is the player's")
end)

T.test("only the docked window open: the guide window opens free once", function()
    local db = carried({ dockSide = "RIGHT", windowClosed = true })
    T.eq(db.windowClosed, nil, "open")
    T.eq(db.dockSide, nil)
    db.windowClosed = true
    T.eq(carried(db).windowClosed, true, "a later close holds: the carry-over ran once")
end)

T.test("a save set to show the window only with a profession window opens free once", function()
    local db = carried({ dockSide = "RIGHT", windowShow = "profession" })
    T.eq(db.windowClosed, nil)
    T.eq(db.windowShow, nil)
end)

T.test("a save whose dock stood left puts the gathering panel left, once", function()
    local db = carried({ dockSide = "LEFT" })
    T.eq(db.gatherSide, "left")
    T.eq(db.gatherSideCarried, true)
    T.eq(db.dockSide, nil)
end)

T.test("a docking build's save without a free position stands beside the chat box", function()
    scene("game")
    World.set(CP.db, "windowPoint", nil)
    World.set(CP.db, "dockSide", "RIGHT")
    World.set(CP.db, "windowClosed", true)
    CP.CarryOver(CP.db)
    Visual.Reload()
    T.fire("PLAYER_ENTERING_WORLD", false, true)
    settle()
    T.ok(P.frame:IsShown(), "the guide window shows")

    -- The default point, moved in only as far as the screen asks (Window.KeepOnScreen).
    local want = W.DefaultPoint()
    local top = rect(W.anchor)[4]
    W.anchor:ClearAllPoints()
    W.anchor:SetPoint(unpack(want))
    T.eq(top, rect(W.anchor)[4], "at the default point's height")
    W.PlaceAnchor()
    W.Update()
    local r, screen = rect(P.frame), Visual.SCREEN
    T.ok(r[1] >= 0 and r[3] <= screen[1] and r[2] >= 0 and r[4] <= screen[2], "on screen")
    Visual.Check("migrated")
end)

T.test("no dock setting, default or key is left", function()
    T.eq(CP.DEFAULTS.dockSide, nil, "no default")
    for _, s in ipairs(CP.Settings.LIST) do T.ok(s.key ~= "dockSide", "no dockSide row") end
    for _, name in ipairs({ "reopenButton", "pane", "Dock", "ShowWith", "Refresh", "InPane", "VisibleHost", "NAMES" }) do
        T.eq(H[name], nil, "Host." .. name .. " is gone")
    end
    for _, name in ipairs({ "Docked", "DockClosed" }) do T.eq(W[name], nil, "Window." .. name .. " is gone") end
    T.eq(P.GuestsOn, nil, "no title-bar guests")
end)
