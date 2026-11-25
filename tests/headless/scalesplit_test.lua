-- The guide window and the gathering panel each have their own scale slider. The guide's
-- scales the guide window (and the panel attached to it); the panel's scales the detached
-- panel and waits while the panel is attached. The old single "Window scale" carries over to
-- both once.

local CP = ProfLost
local W, P, GP, S = CP.Window, CP.Panel, CP.GatherPanel, CP.Settings
local LW, TAILOR, MINING = 165, 197, 186
local DUROTAR = 1411
local LEFT, TOP = 100, 1000

local function settle() T.advance(0.5) end

local function scene(attached)
    Visual.begin()
    DaylightWorld.begin({ plugin = true })
    Visual.Skin()
    MapWorld.begin({ zone = DUROTAR, level = 20, side = "Horde" })
    CraftWorld.begin({ professions = { [LW] = 1, [TAILOR] = 60, [MINING] = 30 } })
    for _, key in ipairs({ "windowClosed", "windowCollapsed", "windowCollapsedAll", "windowLocked", "windowSize",
                           "windowWidth", "guideScale", "gatherScale", "windowScale", "gatherSize", "gatherPoint",
                           "gatherPanelClosed", "gatherLocked", "gatherScaleCarried", "windowAnchorSize" }) do
        World.set(CP.db, key, nil)
    end
    World.set(CP.db, "hideInCombat", true)
    World.set(CP.db, "gatherHideInCombat", true)
    World.set(CP.db, "guideSteps", CP.DEFAULTS.guideSteps)
    World.set(CP.db, "windowPoint", { "TOPLEFT", "BOTTOMLEFT", LEFT, TOP })
    World.set(CP.db, "gatherAttached", attached ~= false)
    World.set(CP.db, "gatherOpen", true)
    World.set(CP.db, "gatherSide", "right")
    World.set(CP.charDB, "guideMode", "one")
    World.set(W.managed, "mover", false)
    World.set(GP.managed, "mover", false)
    World.onEnd(function()
        CraftWorld.Close()
        W.anchor:SetScale(1)
        GP.anchor:SetScale(1)
        GP.anchor:ClearAllPoints()
        W.PlaceAnchor()
        P:Refresh()
        W.Update()
    end)
    GP.anchor:ClearAllPoints()
    W.PlaceAnchor()
    GP.PlaceAnchor()
    W.Update()
    W.Pick(LW)
    P:Refresh()
    settle()
end

local function row(label)
    for _, s in ipairs(S.LIST) do if s.label == label then return s end end
end

local function height(f) local _, _, _, h = f:GetRect() return h end

T.test("two scale sliders, each in its window's group, with the old range", function()
    scene()
    T.eq(row("Window scale"), nil, "the single slider is gone")
    local g, p = row("Guide window scale"), row("Gathering window scale")
    T.ok(g and g.group == "Guide window" and g.kind == "slider", "guide: in the Guide window group")
    T.ok(p and p.group == "Gathering window" and p.kind == "slider", "panel: in the Gathering window group")
    for _, s in ipairs({ g, p }) do
        T.eq({ s.min, s.max, s.step, s.unit }, { 0.5, 2, 0.05, "x" }, s.label .. ": the old range, step and unit")
        T.eq({ s.get(), s.default() }, { 1, 1 }, s.label .. ": 1 to start")
    end
    local rows = {}
    for _, grp in ipairs(CP.Plugin.Pages()[1].groups) do
        for _, item in ipairs(grp.items) do rows[item.label] = grp.label end
    end
    T.eq({ rows["Guide window scale"], rows["Gathering window scale"] }, { "Guide window", "Gathering window" }, "both on the options page")
end)

T.test("each slider scales its own window only", function()
    scene(false)
    local g, p = row("Guide window scale"), row("Gathering window scale")
    GP.Update()
    g.set(1.5)
    T.eq({ W.anchor:GetScale(), GP.anchor:GetScale() }, { 1.5, 1 }, "the guide slider moves the guide anchor")
    T.eq({ P.frame:GetScale(), GP.sheet:GetScale() }, { 1.5, 1 }, "the detached panel stays")
    p.set(0.75)
    T.eq({ W.anchor:GetScale(), GP.anchor:GetScale() }, { 1.5, 0.75 }, "the panel slider moves the panel anchor")
    T.eq({ P.frame:GetScale(), GP.sheet:GetScale() }, { 1.5, 0.75 }, "and its sheet, not the guide")
    T.eq({ CP.db.guideScale, CP.db.gatherScale }, { 1.5, 0.75 }, "each kept under its own key")
    p.set(1)
    T.eq({ CP.db.gatherScale, W.anchor:GetScale() }, { nil, 1.5 }, "1 saves nothing and leaves the guide")
end)

T.test("attached, the panel takes the guide's scale, edge to edge, and its slider waits", function()
    scene(true)
    GP.Open(true)
    settle()
    local g, p = row("Guide window scale"), row("Gathering window scale")
    local disabled = function(s, attached)
        return s.disabled and s.disabled(function(k) if k == "gatherAttached" then return attached end end) or false
    end
    T.ok(disabled(p, true), "greyed while attached")
    T.ok(not disabled(p, false), "live once detached")
    T.ok(not disabled(g, true), "the guide's never")
    T.ok(p.desc:find("Follows the guide window while attached", 1, true), "its note says why")
    g.set(1.5)
    p.set(0.6)   -- ignored on screen while attached
    settle()
    T.eq(GP.sheet:GetEffectiveScale(), P.frame:GetEffectiveScale(), "the panel draws at the guide's scale")
    T.eq(GP.sheet:GetHeight(), P.frame:GetHeight(), "as tall as the window")
    local l, _, w = P.frame:GetRect()
    T.eq(GP.clip:GetLeft(), l + w, "from the window's right edge")
    T.eq(height(GP.sheet), height(P.frame), "drawn heights match")
end)

T.test("the grip and Steps shown work at a scale, attached and detached", function()
    scene(true)
    GP.Open(true)
    row("Guide window scale").set(1.5)
    settle()
    local w0, n0 = P.WIDTH, CP.db.guideSteps
    W.GripStart()
    W.Resize(w0 + 40, P.frame:GetHeight() + 2 * CP.GuideTab.RowHeight())
    T.eq({ CP.db.windowWidth, CP.db.guideSteps }, { w0 + 40, n0 + 2 }, "width and two more steps")
    T.eq(GP.sheet:GetHeight(), P.frame:GetHeight(), "the attached panel keeps the window's height")

    scene(false)
    row("Gathering window scale").set(0.75)
    GP.Update()
    GP.Resize(GP.SIZE_MIN[1] + 20, GP.SIZE_MIN[2] + 30)
    T.eq(CP.db.gatherSize, { GP.SIZE_MIN[1] + 20, GP.SIZE_MIN[2] + 30 }, "the detached size saves in its own units")
    T.eq({ GP.sheet:GetWidth(), GP.sheet:GetHeight() }, { GP.SIZE_MIN[1] + 20, GP.SIZE_MIN[2] + 30 }, "and the sheet takes it at 0.75")
    T.eq(GP.sheet:GetScale(), 0.75)
end)

T.test("the old single scale carries over to both, once", function()
    local db = CP.CarryOver({ windowScale = 1.4, gatherOpen = true })
    T.eq({ db.guideScale, db.gatherScale, db.windowScale }, { 1.4, 1.4, nil }, "without the mover: both keys, the old one gone")
    T.eq(db.gatherScaleCarried, true, "flagged for Daylight UI's mover scale")
    db.guideScale, db.gatherScale = 1.1, 0.9
    CP.CarryOver(db)
    T.eq({ db.guideScale, db.gatherScale }, { 1.1, 0.9 }, "a second load changes nothing")
    local fresh = CP.CarryOver({})
    T.eq({ fresh.guideScale, fresh.gatherScale, fresh.gatherScaleCarried }, { nil, nil, nil }, "a first run has nothing to carry")
end)

T.test("with Daylight UI the guide's mover scale also becomes the panel's mover scale, once", function()
    scene()
    World.set(W.managed, "mover", true)
    World.set(GP.managed, "mover", true)
    local scales = DaylightWorld.state.frameScales
    World.set(scales, W.MOVER_KEY, 1.4)
    World.set(scales, GP.MOVER_KEY, nil)
    World.set(CP.db, "gatherScaleCarried", true)
    CP.Plugin.SettleScale()
    T.eq({ scales[W.MOVER_KEY], scales[GP.MOVER_KEY] }, { 1.4, 1.4 }, "both movers hold the old value")
    T.eq(CP.db.gatherScaleCarried, nil, "settled")
    scales[GP.MOVER_KEY] = 0.8   -- the player's own pick since
    CP.db.gatherScaleCarried = true
    CP.Plugin.SettleScale()
    T.eq(scales[GP.MOVER_KEY], 0.8, "a size the player already set stays")
    T.eq(row("Gathering window scale").get(), 0.8, "the slider reads the panel mover")
end)

T.test("both scales survive a reload", function()
    scene(false)
    row("Guide window scale").set(1.25)
    row("Gathering window scale").set(0.8)
    GP.Update()
    W.anchor:SetScale(1)
    GP.anchor:SetScale(1)
    Visual.Reload()
    T.eq({ W.anchor:GetScale(), GP.anchor:GetScale() }, { 1.25, 0.8 }, "the anchors take their saved scales")
    GP.Update()
    settle()
    T.eq(GP.sheet:GetScale(), 0.8, "the detached panel stands at its own")
    T.eq(P.frame:GetScale(), 1.25, "the guide at its own")
end)
