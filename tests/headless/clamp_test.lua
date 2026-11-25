-- The guide window and its attached gathering panel keep to the screen as one: the
-- window's anchor clamp rect reaches over the panel on its side while it is out, and a
-- panel sliding out past the screen's edge moves the window in. Detached, the window
-- clamps alone. The harness doesn't clamp a drag, so `clampDrag` does what the game does
-- with the anchor's clamp rect (Frame:SetClampRectInsets as Style.ClampTop sets it).

local CP = ProfLost
local W, P, GP = CP.Window, CP.Panel, CP.GatherPanel
local LW, TAILOR, MINING = 165, 197, 186
local DUROTAR = 1411

local function settle() T.advance(1) end

local function scene(side, open, x)
    Visual.begin()
    DaylightWorld.begin({ plugin = true })
    Visual.Skin()
    MapWorld.begin({ zone = DUROTAR, level = 20, side = "Horde" })
    CraftWorld.begin({ professions = { [LW] = 100, [TAILOR] = 60, [MINING] = 30 } })
    World.set(CP.db, "hideInCombat", true)
    World.set(CP.db, "windowClosed", nil)
    World.set(CP.db, "windowCollapsed", nil)
    World.set(CP.db, "windowLocked", nil)
    World.set(CP.db, "windowPoint", { "TOPLEFT", "BOTTOMLEFT", x or 400, 900 })
    World.set(CP.db, "gatherAttached", true)
    World.set(CP.db, "gatherOpen", open ~= false)
    World.set(CP.db, "gatherSide", side or "right")
    World.set(CP.db, "gatherSideCarried", CP.db.gatherSideCarried)
    World.set(CP.db, "gatherPoint", CP.db.gatherPoint)
    World.set(CP.db, "gatherSize", CP.db.gatherSize)
    World.set(CP.charDB, "guideMode", "one")
    World.set(W.managed, "mover", false)
    World.set(GP.managed, "mover", false)
    World.onEnd(function()
        CP.db.gatherAttached = true
        GP.ModeChanged()
        GP.anchor:ClearAllPoints()
        W.Update()
    end)
    GP.anchor:ClearAllPoints()
    W.PlaceAnchor()
    W.Update()
    W.Pick(LW)
    P:Refresh()
    GP.Layout()
    settle()
end

local function screen() return Visual.SCREEN[1], Visual.SCREEN[2] end

-- The anchor's clamp rect on screen, from its rect and the insets last set on it.
local function clampRect()
    local a = W.anchor
    local l, b, r, t = Visual.Resolve(a)
    local c = T.calls("Frame:SetClampRectInsets")
    local last = c[#c]
    T.ok(last ~= nil, "the anchor has clamp insets")
    local s = a:GetEffectiveScale()
    return l + last[1] * s, b + last[4] * s, r + last[2] * s, t + last[3] * s
end

-- A title-bar drag toward `x` (anchor left, screen px), clamped as the game clamps it.
local function clampDrag(x)
    W.DragStart()
    local a = W.anchor
    local _, _, _, top = Visual.Resolve(a)
    a:ClearAllPoints()
    a:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, top)
    local l, _, r = clampRect()
    local sw = screen()
    local dx = 0
    if r > sw then dx = sw - r end
    if l + dx < 0 then dx = -l end
    a:ClearAllPoints()
    a:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x + dx, top)
    W.DragStop()
    settle()
end

local function onScreen(frame, what)
    local l, b, r = Visual.Resolve(frame)
    local sw = screen()
    T.ok(l >= -0.5 and r <= sw + 0.5, ("%s on screen: %d to %d of %d"):format(what, l, r, sw))
end

T.test("attached and open on the right: a drag to the right edge stops with the panel on screen", function()
    scene("right")
    T.ok(GP.Showing() and GP.p == 1, "the panel is out")
    T.eq(W.anchor.profLostClampRight, GP.WIDTH, "the clamp reaches over the panel")
    T.eq(W.anchor.profLostClampLeft, 0)
    clampDrag(screen() + 200)
    onScreen(GP.sheet, "the gathering panel")
    onScreen(P.frame, "the guide window")
    local _, _, r = Visual.Resolve(GP.sheet)
    T.ok(math.abs(r - screen()) < 1, "the panel's edge stops at the screen's")
end)

T.test("attached and open on the left: a drag to the left edge stops with the panel on screen", function()
    scene("left")
    T.eq(W.anchor.profLostClampLeft, GP.WIDTH)
    T.eq(W.anchor.profLostClampRight, 0)
    clampDrag(-400)
    onScreen(GP.sheet, "the gathering panel")
    local l = Visual.Resolve(GP.sheet)
    T.ok(math.abs(l) < 1, "the panel's edge stops at the screen's")
end)

T.test("folded back, the window alone keeps to the screen", function()
    scene("right", false)
    T.eq(W.anchor.profLostClampRight, 0, "nothing beside it")
    clampDrag(screen() + 200)
    local _, _, r = Visual.Resolve(P.frame)
    T.ok(math.abs(r - screen()) < 1, "the window's edge stops at the screen's")
end)

T.test("sliding out at the screen's edge moves the window in, and saves the spot", function()
    scene("right", false)
    clampDrag(screen() + 200)
    GP.Toggle()
    settle()
    T.eq(GP.p, 1, "out")
    onScreen(GP.sheet, "the gathering panel")
    onScreen(P.frame, "the guide window")
    local _, _, _, x = W.anchor:GetPoint(1)
    T.eq(CP.db.windowPoint[3], x, "the new spot is saved")
    -- Folding back clears the reach; the window stays where it is.
    GP.Toggle()
    settle()
    T.eq(W.anchor.profLostClampRight, 0)
end)

T.test("a side change carries the reach to the other side", function()
    scene("right")
    CP.Settings.Set("gatherSide", "left")
    settle()
    T.eq(W.anchor.profLostClampLeft, GP.WIDTH)
    T.eq(W.anchor.profLostClampRight, 0)
    onScreen(GP.sheet, "the gathering panel")
end)

T.test("detached, the window clamps alone", function()
    scene("right")
    CP.Settings.Set("gatherAttached", false)
    settle()
    T.eq(W.anchor.profLostClampLeft, 0)
    T.eq(W.anchor.profLostClampRight, 0)
end)
