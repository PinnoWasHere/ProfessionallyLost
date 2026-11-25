-- Escape closes the guide window and the detached gathering panel like their close buttons,
-- unless the window's padlock is shut. The harness has no CloseSpecialWindows, so
-- `escape` does what the game does: hide each shown frame named in UISpecialFrames.

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
    end)
    GP.anchor:ClearAllPoints()
    W.PlaceAnchor()
    W.Update()
    GP.ModeChanged()
    GP.Layout()
    T.ok(P.frame:IsShown(), "the guide window")
    T.ok(GP.sheet:IsVisible(), "the detached gathering panel")
end

local function escape()
    for _, name in ipairs(UISpecialFrames) do
        local f = _G[name]
        if f and f:IsShown() then f:Hide() end
    end
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
