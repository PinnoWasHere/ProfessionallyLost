-- Escape closes the guide window and the detached gathering panel like their close buttons,
-- unless the window's padlock is shut. Only the player's Escape closes them: the game's own
-- CloseAllWindows (entering the world, /reload, a loading screen) leaves them open.

local CP = ProfLost
local W, P, GP = CP.Window, CP.Panel, CP.GatherPanel
local LW, TAILOR = 165, 197
local DUROTAR = 1411

local function scene()
    MapWorld.begin({ zone = DUROTAR, level = 20, side = "Horde" })
    CraftWorld.begin({ professions = { [LW] = 100, [TAILOR] = 60 } })
    World.set(CP.db, "hideInCombat", true)
    World.set(CP.db, "gatherHideInCombat", true)
    World.set(CP.db, "gatherHideCarried", nil)
    World.set(CP.db, "windowClosed", nil)
    World.set(CP.db, "windowLocked", nil)
    World.set(CP.db, "gatherLocked", nil)
    World.set(CP.db, "gatherOpen", true)
    World.set(CP.db, "gatherAttached", false)
    World.set(CP.db, "gatherPanelClosed", nil)
    World.set(CP.db, "gatherSize", CP.db.gatherSize)
    World.set(W.managed, "mover", false)
    World.set(GP.managed, "mover", false)
    World.onEnd(function()
        CP.db.gatherAttached = true
        GP.ModeChanged()
        T.fire("PLAYER_REGEN_ENABLED")
        GP.anchor:ClearAllPoints()
        T.advance(CP.GatherList.ROUTE_MOST + 1)
    end)
    GP.anchor:ClearAllPoints()
    W.PlaceAnchor()
    W.Update()
    GP.ModeChanged()
    GP.Layout()
    T.ok(P.frame:IsShown(), "the guide window")
    T.ok(GP.sheet:IsVisible(), "the detached gathering panel")
end

-- The game's CloseSpecialWindows: hides each shown frame named in UISpecialFrames. The
-- game runs it from CloseAllWindows on entering the world, as well as on Escape.
local function closeSpecial()
    for _, name in ipairs(UISpecialFrames) do
        local f = _G[name]
        if f and f:IsShown() then f:Hide() end
    end
end

-- The player's Escape: ToggleGameMenu runs the Escape handlers, CloseAllWindows among them
-- (Blizzard_GameMenuEsc), then its post-hooks.
local function escape()
    closeSpecial()
    ToggleGameMenu()
end

-- Entering the world: the game closes every special frame, then PLAYER_ENTERING_WORLD.
local function enterWorld(login, reload)
    closeSpecial()
    T.fire("PLAYER_ENTERING_WORLD", login, reload)
end

local function click(b) b:GetScript("OnClick")(b) end

T.test("Escape closes the guide window and the gathering panel, saved like their close buttons", function()
    scene()
    escape()
    T.ok(not P.frame:IsShown(), "the guide closed")
    T.ok(not GP.sheet:IsVisible(), "the gathering panel closed")
    T.eq(CP.db.windowClosed, true, "saved: /proflost reopens it")
    T.eq(CP.db.gatherPanelClosed, true, "saved")
    W.Open()
    T.ok(P.frame:IsShown(), "the guide opens again")
    GP.Open()
    T.ok(GP.sheet:IsVisible(), "and the panel")
end)

T.test("the lock keeps both windows through Escape; unlocking lets Escape close again", function()
    scene()
    click(W.lockButton)
    click(GP.lockButton)
    T.ok(CP.db.windowLocked and CP.db.gatherLocked, "both locked")
    escape()
    T.ok(P.frame:IsShown(), "the locked guide stays")
    T.ok(GP.sheet:IsVisible(), "the locked panel stays")
    T.ok(not CP.db.windowClosed and not CP.db.gatherPanelClosed, "nothing saved as closed")
    click(W.lockButton)
    escape()
    T.ok(not P.frame:IsShown(), "unlocked, the guide closes")
    T.ok(GP.sheet:IsVisible(), "the panel keeps its own padlock")
    click(GP.lockButton)
    escape()
    T.ok(not GP.sheet:IsVisible(), "its padlock open, it closes")
end)

T.test("the detached panel has a Daylight UI close button that closes it", function()
    scene()
    T.ok(GP.closeButton:IsShown(), "shown while detached")
    T.eq(GP.closeButton:GetParent(), CP.GatherList.head, "in the panel's header")
    click(GP.closeButton)
    T.ok(not GP.sheet:IsVisible(), "closed")
    T.eq(CP.db.gatherPanelClosed, true)
end)

T.test("a loading screen, /reload or login leaves both windows open; Escape still closes them", function()
    scene()
    for _, how in ipairs({ { false, false }, { false, true }, { true, false } }) do
        enterWorld(how[1], how[2])
        T.ok(P.frame:IsShown(), "the guide stays open")
        T.ok(GP.sheet:IsVisible(), "the gathering panel stays open")
        T.eq(CP.db.windowClosed, nil, "nothing saved as closed")
        T.eq(CP.db.gatherPanelClosed, nil, "nothing saved as closed")
        T.advance(0.1)
    end
    escape()
    T.ok(not P.frame:IsShown(), "the player's Escape closes the guide")
    T.ok(not GP.sheet:IsVisible(), "and the panel")
    T.eq(CP.db.windowClosed, true)
    T.eq(CP.db.gatherPanelClosed, true)
end)

-- A static popup or a menu takes the Escape before CloseAllWindows runs.
T.test("Escape taken by something else after a loading screen closes nothing", function()
    scene()
    enterWorld(false, false)
    T.advance(0.1)
    T.ok(W.escFrame:IsShown() and W.gatherEscFrame:IsShown(), "the stand-ins are back up")
    ToggleGameMenu()
    T.ok(P.frame:IsShown() and GP.sheet:IsVisible(), "the loading screen's hide is not taken as Escape")
    T.eq(CP.db.windowClosed, nil)
    T.eq(CP.db.gatherPanelClosed, nil)
end)

-- Alt+Z hides UIParent: each shown child gets OnHide but stays shown itself. The harness
-- doesn't pass a parent's hide down, so the test runs the stand-ins' OnHide as the game does.
T.test("the whole UI hidden and shown again (Alt+Z) leaves both windows open", function()
    scene()
    for _, f in ipairs({ W.escFrame, W.gatherEscFrame }) do
        T.ok(f:IsShown(), "the stand-in is up")
        f:GetScript("OnHide")(f)
    end
    T.advance(0.1)
    T.ok(P.frame:IsShown() and GP.sheet:IsVisible(), "both open")
    T.eq(CP.db.windowClosed, nil)
    T.eq(CP.db.gatherPanelClosed, nil)
end)
