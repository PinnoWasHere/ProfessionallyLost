-- The gathering panel attached to the guide window or standing on its own
-- (the guide window spec, "Gathering window"): the attach setting, each window's
-- saved spot, its own mover and fade, closing each on its own, the minimap button's
-- Shift-click, combat, a profession window opening, heights while attached, and the detached panel's size.

local CP = ProfLost
local W, P, GP = CP.Window, CP.Panel, CP.GatherPanel
local LW, TAILOR, MINING = 165, 197, 186
local DUROTAR = 1411

local GUIDE_SPOT = { "TOPLEFT", "BOTTOMLEFT", 100, 800 }

-- One scene: a free guide window at GUIDE_SPOT, attached, its panel open, never detached.
local function scene()
    MapWorld.begin({ zone = DUROTAR, level = 20, side = "Horde" })
    CraftWorld.begin({ professions = { [LW] = 100, [TAILOR] = 60, [MINING] = 30 } })
    World.set(CP.db, "hideInCombat", true)
    World.set(CP.db, "gatherHideInCombat", true)
    World.set(CP.db, "gatherHideCarried", nil)
    World.set(CP.db, "gatherLocked", false)
    World.set(CP.db, "windowClosed", nil)
    World.set(CP.db, "windowLocked", nil)
    World.set(CP.db, "windowPoint", { unpack(GUIDE_SPOT) })
    World.set(CP.db, "gatherOpen", true)
    World.set(CP.db, "gatherAttached", true)
    World.set(CP.db, "gatherPanelClosed", nil)
    World.set(CP.db, "gatherPoint", nil)
    World.set(CP.db, "gatherSize", nil)
    World.set(CP.db, "gatherSide", "right")
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
    GP.Layout()
end

local function detach() CP.Settings.Set("gatherAttached", false) end
local function attach() CP.Settings.Set("gatherAttached", true) end

local function guideShown() return P.frame:IsShown() end
local function gatherShown() return GP.sheet:IsVisible() end

local function point(frame) return { frame:GetPoint(1) } end

-- Where the screen says the anchor stands once it hangs beside the guide window.
local function screenAt(left, top)
    World.set(GP.anchor, "GetLeft", function() return left end)
    World.set(GP.anchor, "GetTop", function() return top end)
end

-- A drag of the detached panel to `x`, `y` (the harness doesn't move frames by mouse).
local function dragTo(x, y)
    GP.sheet:GetScript("OnDragStart")(GP.sheet)
    GP.anchor:ClearAllPoints()
    GP.anchor:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
    GP.sheet:GetScript("OnDragStop")(GP.sheet)
end

-- The setting ---------------------------------------------------------------------------

T.test("the attach setting sits in the Gathering window group, on by default", function()
    local s = CP.Settings.Find("gatherAttached")
    T.ok(s ~= nil)
    T.eq(s.group, "Gathering window")
    T.eq(s.kind, "toggle")
    T.eq(s.label, "Attach to guide window")
    T.eq(CP.DEFAULTS.gatherAttached, true, "attached by default: today's behaviour")
end)

T.test("detached: its own window, own shell and close, no fold tab; attached: back in the guide window", function()
    scene()
    T.eq(GP.sheet:GetParent(), GP.clip, "attached: inside the guide window's clip")
    T.ok(not GP.closeButton:IsShown(), "attached: no close of its own")
    screenAt(420, 800)
    detach()
    T.eq(GP.sheet:GetParent(), UIParent, "detached: its own window")
    T.ok(gatherShown(), "and it shows at once, no reload")
    T.eq(point(GP.sheet), { "TOPLEFT", GP.anchor, "TOPLEFT" }, "hanging from its own anchor")
    T.ok(GP.sheet.__shell:IsShown() and GP.sheet.__line:IsShown(), "its own shell and accent line")
    T.ok(GP.closeButton:IsShown(), "its own close button")
    T.ok(GP.lockButton:IsShown(), "its own padlock")
    T.eq(CP.GatherList.headRoom, GP.HeadRoom(), "the header leaves room for them")
    T.eq(GP.HeadRoom(), GP.CLOSE_GAP + GP.GUIDE + GP.ICON_GAP + GP.LOCK + GP.ICON_GAP + GP.CLOSE)
    T.ok(GP.guideButton:IsShown(), "and its open-the-guide button")
    T.ok(not GP.tab:IsShown() and not GP.clip:IsShown(), "no fold tab, no slide")
    T.ok(GP.shell:IsShown(), "the guide window keeps its shell")
    T.eq(GP.shell:GetWidth(), P.WIDTH, "framing the guide window alone")
    T.ok(not GP.seam:IsShown(), "no seam")

    attach()
    T.eq(GP.sheet:GetParent(), GP.clip, "back in the clip")
    T.ok(not GP.sheet.__shell:IsShown(), "no shell of its own")
    T.ok(not GP.closeButton:IsShown())
    T.ok(not GP.lockButton:IsShown())
    T.eq(CP.GatherList.headRoom, 0)
    T.ok(GP.tab:IsShown(), "the fold tab is back")
    T.eq(GP.p, 1, "slid out at once, as it was saved open")
    T.eq(GP.shell:GetWidth(), 2 * P.WIDTH, "one shell around both")
end)

-- Saved spots -----------------------------------------------------------------------------

T.test("switching both ways restores each window's saved spot, and both survive a reload", function()
    scene()
    local placed = {}
    local setPoint = GP.anchor.SetPoint
    World.set(GP.anchor, "SetPoint", function(self, ...)
        placed[#placed + 1] = { ... }
        return setPoint(self, ...)
    end)
    screenAt(420, 800)
    T.ok(GP.Unplaced(), "never placed")
    detach()
    T.eq(placed[1], { "TOPLEFT", W.anchor, "TOPRIGHT", GP.GAP, 0 }, "first time: beside the guide window's spot")
    T.eq(CP.db.gatherPoint, { "TOPLEFT", "BOTTOMLEFT", 420, 800 }, "kept as a spot on the screen")
    T.eq(point(GP.anchor), { "TOPLEFT", UIParent, "BOTTOMLEFT", 420, 800 })
    T.ok(not GP.Unplaced())

    dragTo(900, 600)
    T.eq(CP.db.gatherPoint, { "TOPLEFT", "BOTTOMLEFT", 900, 600 }, "a drag of the panel is saved")
    T.eq(CP.db.windowPoint, GUIDE_SPOT, "the guide window's spot is untouched")

    attach()
    T.eq(point(W.anchor), { GUIDE_SPOT[1], UIParent, GUIDE_SPOT[2], GUIDE_SPOT[3], GUIDE_SPOT[4] },
        "attached: the guide window at its own saved spot")
    T.eq(CP.db.gatherPoint, { "TOPLEFT", "BOTTOMLEFT", 900, 600 }, "the panel's spot is kept while attached")

    placed = {}
    detach()
    T.eq(#placed, 0, "a second detach doesn't place it again")
    T.eq(point(GP.anchor), { "TOPLEFT", UIParent, "BOTTOMLEFT", 900, 600 }, "back exactly where it last was")

    -- A reload: both anchors come from what was saved (each module's PLAYER_LOGIN).
    GP.anchor:ClearAllPoints()
    W.anchor:ClearAllPoints()
    W.PlaceAnchor()
    GP.PlaceAnchor()
    T.eq(point(GP.anchor), { "TOPLEFT", UIParent, "BOTTOMLEFT", 900, 600 }, "the panel's spot survives a reload")
    T.eq(point(W.anchor), { GUIDE_SPOT[1], UIParent, GUIDE_SPOT[2], GUIDE_SPOT[3], GUIDE_SPOT[4] },
        "and the guide window's")
end)

T.test("the detached panel drags on its own while its own padlock is open; the guide's locks only the guide", function()
    scene()
    World.set(CP.db, "gatherLocked", false)
    screenAt(420, 800)
    detach()
    GP.lockButton:GetScript("OnClick")(GP.lockButton)
    T.eq(CP.db.gatherLocked, true, "its padlock shuts, saved")
    T.ok(tostring(GP.lockButton.icon.file):find("Lock$") ~= nil, "the shut padlock")
    dragTo(50, 50)
    T.eq(CP.db.gatherPoint, { "TOPLEFT", "BOTTOMLEFT", 420, 800 }, "locked: no drag saved")
    GP.lockButton:GetScript("OnClick")(GP.lockButton)
    T.eq(CP.db.gatherLocked, false)
    CP.db.windowLocked = true
    dragTo(50, 50)
    T.eq(CP.db.gatherPoint, { "TOPLEFT", "BOTTOMLEFT", 50, 50 }, "the guide's padlock shut: the panel still drags")
    T.eq(CP.db.windowPoint, GUIDE_SPOT, "the guide window stays put")
    W.DragStart()
    T.eq(CP.db.windowPoint, GUIDE_SPOT, "and the guide stays locked")
    CP.db.windowLocked = nil
end)

-- Daylight UI's mover and fade -----------------------------------------------------------

T.test("the detached panel registers its own mover, separate from the guide window's", function()
    scene()
    local movers = {}
    local me = { RegisterMover = function(frame, key, label, default)
        movers[key] = { frame = frame, label = label, default = default }
        return true
    end }
    CP.Plugin.RegisterMovers(me)
    T.ok(movers.checklist ~= nil and movers.checklist.frame == W.anchor, "the guide window keeps its key")
    local m = movers[GP.MOVER]
    T.ok(m ~= nil, "a mover keyed " .. GP.MOVER)
    T.eq(m.frame, GP.anchor, "on the panel's own anchor")
    T.eq(m.label, "Gathering window")
    T.eq(m.default[2], W.anchor, "it starts beside the guide window")
    T.ok(GP.managed.mover and W.managed.mover)

    -- A drag saves into that mover, never the guide window's.
    local saves = {}
    World.set(_G, "DaylightUI", { Movers = { Save = function(key, exact) saves[#saves + 1] = { key, exact } end } })
    detach()
    T.eq(saves[1], { "plugin.ProfLost.gatherpanel", true }, "a first detach saves its spot into the mover")
    dragTo(10, 10)
    T.eq(saves[#saves], { "plugin.ProfLost.gatherpanel", true }, "a drag too")
    for _, s in ipairs(saves) do T.ok(s[1] ~= W.MOVER_KEY, "never the guide window's key") end
    T.eq(CP.db.gatherPoint, nil, "Daylight UI keeps the spot")
end)

T.test("Daylight UI fades the detached panel on its own key; attached, it fades with the window", function()
    DaylightWorld.begin({ plugin = true })
    scene()
    local fade = DaylightWorld.state.fades[CP.Plugin.GATHER_FADE_KEY]
    T.ok(fade ~= nil, "a fade area keyed " .. CP.Plugin.GATHER_FADE_KEY)
    T.eq(fade.float, false)
    T.eq(#fade.frames(), 0, "attached: nothing of its own to fade")
    detach()
    T.eq(fade.frames()[1], GP.sheet, "detached: the panel")
    T.ok(GP.managed.fade)
end)

-- Closing each on its own -----------------------------------------------------------------

T.test("closing the guide leaves the detached panel up, and the reverse; each close is saved", function()
    scene()
    detach()
    T.ok(guideShown() and gatherShown())
    W.closeButton:GetScript("OnClick")(W.closeButton)
    T.ok(not guideShown(), "the guide closed")
    T.ok(gatherShown(), "the gathering panel stays")
    T.eq(CP.db.windowClosed, true)

    W.Open()
    GP.closeButton:GetScript("OnClick")(GP.closeButton)
    T.ok(not gatherShown(), "the gathering panel closed")
    T.ok(guideShown(), "the guide stays")
    T.eq(CP.db.gatherPanelClosed, true, "saved")

    T.fire("PLAYER_ENTERING_WORLD")
    T.fire("PLAYER_REGEN_DISABLED")
    T.fire("PLAYER_REGEN_ENABLED")
    T.ok(not gatherShown(), "loading screens and combat don't bring it back")
    GP.anchor:ClearAllPoints()
    GP.PlaceAnchor()
    W.Update()
    T.ok(not gatherShown(), "nor does a reload")

    SlashCmdList.PROFLOST("gather")
    T.ok(gatherShown(), "/proflost gather opens it")
    T.eq(CP.db.gatherPanelClosed, nil, "saved open")
    SlashCmdList.PROFLOST("gather")
    T.ok(not gatherShown(), "and closes it")
end)

T.test("attached, closing the guide closes the panel with it, as today", function()
    scene()
    T.ok(gatherShown())
    W.Close()
    T.ok(not gatherShown(), "gone with the guide")
    W.Open()
    T.ok(gatherShown(), "back with it")
end)

-- The minimap button ------------------------------------------------------------------------

T.test("the minimap button's Shift-click shows or hides the gathering panel; its tooltip says so", function()
    scene()
    local shift = false
    World.set(_G, "IsShiftKeyDown", function() return shift end)
    local click = CP.Launcher.minimapObject.OnClick
    detach()
    shift = true
    click(nil, "LeftButton")
    T.ok(not gatherShown() and guideShown(), "detached: Shift-click closes the panel alone")
    T.eq(CP.db.gatherPanelClosed, true)
    click(nil, "LeftButton")
    T.ok(gatherShown(), "and opens it")
    shift = false
    click(nil, "LeftButton")
    T.ok(not guideShown() and gatherShown(), "a plain click still toggles the guide alone")
    click(nil, "LeftButton")

    attach()
    shift = true
    click(nil, "LeftButton")
    T.eq(CP.db.gatherOpen, false, "attached: Shift-click slides the panel back")
    click(nil, "LeftButton")
    T.eq(CP.db.gatherOpen, true, "and out")
    W.Close()
    CP.db.gatherOpen = false
    click(nil, "LeftButton")
    T.ok(guideShown() and CP.db.gatherOpen == true, "with the guide shut it opens both")

    local lines = {}
    CP.Launcher.minimapObject.OnTooltipShow({ AddLine = function(_, text) lines[#lines + 1] = text end })
    T.eq(lines[2], "Left-click: show or hide the guide window.")
    T.eq(lines[3], "Shift-click: show or hide the Gathering window.")
    T.eq(lines[4], "Right-click: settings.")
end)

T.test("/proflost gather pressed twice with the guide shut opens both, then shuts both as they were", function()
    scene()
    for _, open in ipairs({ false, true }) do
        W.Close()
        CP.db.gatherOpen = open
        SlashCmdList.PROFLOST("gather")
        T.ok(guideShown() and gatherShown(), "the first press opens the guide and the panel")
        SlashCmdList.PROFLOST("gather")
        T.ok(not guideShown(), "the second press shuts the guide it opened")
        T.eq(CP.db.windowClosed, true, "saved shut, as before")
        T.eq(CP.db.gatherOpen, open, "the panel's own state is as it was")
    end
    W.Open()
    CP.db.gatherOpen = false
    GP.Layout()
    SlashCmdList.PROFLOST("gather")
    SlashCmdList.PROFLOST("gather")
    T.ok(guideShown() and not GP.Showing(), "with the guide up, the pair only slides the panel")
end)

-- Combat and docking --------------------------------------------------------------------------

T.test("hide in combat hides both windows and brings both back", function()
    scene()
    detach()
    T.fire("PLAYER_REGEN_DISABLED")
    T.ok(not guideShown() and not gatherShown(), "both hidden in a fight")
    T.fire("PLAYER_REGEN_ENABLED")
    T.ok(guideShown() and gatherShown(), "both back after")

    T.fire("PLAYER_REGEN_DISABLED")
    SlashCmdList.PROFLOST("gather")
    T.ok(gatherShown() and not guideShown(), "opened in a fight, the panel stays for it")
    T.fire("PLAYER_REGEN_ENABLED")
    T.fire("PLAYER_REGEN_DISABLED")
    T.ok(not gatherShown(), "the next fight hides it")
    T.fire("PLAYER_REGEN_ENABLED")

    CP.Settings.Set("hideInCombat", false)
    T.fire("PLAYER_REGEN_DISABLED")
    T.ok(guideShown() and not gatherShown(), "the guide's setting off: the guide stays, the panel hides by its own")
    T.fire("PLAYER_REGEN_ENABLED")
    CP.Settings.Set("gatherHideInCombat", false)
    T.fire("PLAYER_REGEN_DISABLED")
    T.ok(guideShown() and gatherShown(), "both settings off: both stay")
    T.fire("PLAYER_REGEN_ENABLED")
    CP.Settings.Set("hideInCombat", true)
    T.fire("PLAYER_REGEN_DISABLED")
    T.ok(not guideShown() and gatherShown(), "the panel's setting off alone: only the guide hides")
    T.fire("PLAYER_REGEN_ENABLED")
end)

T.test("a profession window opening moves neither the guide window nor a detached panel", function()
    scene()
    screenAt(420, 800)
    detach()
    dragTo(900, 600)
    local before, guide = point(GP.anchor), point(W.anchor)
    CraftWorld.Open(LW)
    T.ok(guideShown() and gatherShown(), "both stay up")
    T.eq(point(W.anchor), guide, "the guide window stays where it stood")
    T.eq(GP.sheet:GetParent(), UIParent, "the panel on its own")
    T.eq(point(GP.sheet), { "TOPLEFT", GP.anchor, "TOPLEFT" }, "hanging from its own anchor")
    T.eq(point(GP.anchor), before, "which didn't move")
    CraftWorld.Close()
    T.ok(guideShown() and gatherShown())
    T.eq(point(GP.anchor), before, "still there after")
end)

-- Simulator finding, 2026-11-16 (controls, roundtrip): the attach setting off and on with a
-- profession window open left the open panel closed.
T.test("the attach setting off and on with a profession window open brings back what showed", function()
    scene()
    CP.db.gatherOpen = true
    CraftWorld.Open(LW)
    GP.Layout()
    T.ok(guideShown() and GP.Showing(), "the attached panel shows")
    detach()
    T.ok(gatherShown(), "detached, it stands on its own")
    attach()
    T.ok(GP.Showing(), "attached again, it shows as before")
    T.eq(CP.db.gatherOpen, true)
    CraftWorld.Close()
end)

-- Heights while attached -----------------------------------------------------------------

T.test("folded and attached, the panel and the shell take the guide window's height: no empty block", function()
    scene()
    World.set(CP.db, "windowCollapsed", nil)
    World.set(CP.charDB, "guideMode", "one")
    W.Pick(TAILOR)
    CP.db.gatherOpen = false
    GP.Layout()
    GP.Toggle()
    T.advance(0.35)
    T.eq(GP.p, 1, "the panel is out")
    local open = P.frame:GetHeight()
    T.eq(GP.shell:GetHeight(), open, "unfolded: the shell is the window's height")
    T.eq(GP.sheet:GetHeight(), open, "and so is the panel")
    W.SetFolded(true)
    local folded = P.frame:GetHeight()
    T.ok(folded < open, ("folding shrinks the window: %d < %d"):format(folded, open))
    T.eq(GP.sheet:GetHeight(), folded, "the panel follows it down")
    T.eq(GP.clip:GetHeight(), folded)
    T.eq(GP.shell:GetHeight(), folded, "the shell has no block under the folded window")
    T.eq(GP.shell:GetWidth(), 2 * P.WIDTH)
    T.ok(CP.GatherList.RoomRows() >= 1, "the list keeps a row and scrolls")
    W.SetFolded(false)
    T.eq(GP.sheet:GetHeight(), P.frame:GetHeight(), "unfolding brings it back up")
end)

-- The detached panel's size -----------------------------------------------------------------

-- The detached panel standing with its top-left at `left`, `top` on the screen.
local function standAt(left, top)
    World.set(GP.anchor, "GetLeft", function() return left end)
    World.set(GP.anchor, "GetTop", function() return top end)
end

local function size(frame) return { frame:GetWidth(), frame:GetHeight() } end

-- The anchor is the panel's rect: the same size, the sheet hanging from its top-left.
local function anchorIsPanel(why)
    T.eq(size(GP.anchor), size(GP.sheet), why .. ": the anchor is the panel's size")
    T.eq(point(GP.sheet), { "TOPLEFT", GP.anchor, "TOPLEFT" }, why .. ": the panel hangs from its top-left")
    T.eq(GP.anchor.profLostClampBelow, 0, why .. ": the clamp keeps the whole panel on screen")
end

-- A drag of the corner grip by `dx`, `dy` (right and down), through its own scripts.
local function dragGrip(dx, dy)
    local x, y = 1000, 500
    World.set(_G, "GetCursorPosition", function() return x, y end)
    GP.grip:GetScript("OnMouseDown")(GP.grip, "LeftButton")
    x, y = x + dx, y - dy
    GP.grip:GetScript("OnUpdate")(GP.grip, 0.016)
    GP.grip:GetScript("OnMouseUp")(GP.grip, "LeftButton")
end

T.test("a first detach starts as wide as the window at its list's height, capped by the room below; rows never change it", function()
    scene()
    local need = 2000
    standAt(900, 300)
    World.set(CP.GatherList, "NeedHeight", function() return need end)
    World.set(CP.GatherList, "Drawn", function() return { {} }, {}, 0 end)
    detach()
    T.eq(size(GP.sheet), { P.WIDTH, 300 }, "a long list: as tall as the room down to the screen's bottom")
    T.eq(CP.db.gatherSize, { P.WIDTH, 300 }, "the size is kept")
    anchorIsPanel("first detach")

    -- Opening and closing sections: the list asks for other heights; the panel keeps its own.
    for _, n in ipairs({ 3000, 60, 400 }) do
        need = n
        CP.GatherList.Refresh()
        GP.Fit()
        T.eq(size(GP.sheet), { P.WIDTH, 300 }, ("rows needing %d px: the size stays"):format(n))
    end
    T.ok(CP.GatherList.RoomRows() >= 1, "the rows scroll inside it")
end)

T.test("a first detach with a short list: its rows' height, at least the grip's least", function()
    scene()
    standAt(900, 800)
    World.set(CP.GatherList, "NeedHeight", function() return 300 end)
    World.set(CP.GatherList, "Drawn", function() return { {} }, {}, 0 end)
    detach()
    T.eq(size(GP.sheet), { P.WIDTH, 300 + 2 * P.BODY_PAD + 4 })
    CP.db.gatherSize = nil
    World.set(CP.GatherList, "NeedHeight", function() return 10 end)
    GP.Fit()
    T.eq(size(GP.sheet), { P.WIDTH, GP.SIZE_MIN[2] }, "never under the least height")
end)

T.test("the corner grip resizes the panel and its anchor, and the size is saved", function()
    scene()
    standAt(900, 800)
    detach()
    CP.db.gatherSize = { P.WIDTH, 400 }
    GP.Fit()
    T.ok(GP.grip:IsShown(), "detached: the grip shows")
    dragGrip(60, 100)
    T.eq(CP.db.gatherSize, { P.WIDTH + 60, 500 }, "saved")
    T.eq(size(GP.sheet), { P.WIDTH + 60, 500 }, "the panel")
    anchorIsPanel("after a resize")
    T.eq(point(GP.anchor), { "TOPLEFT", UIParent, "BOTTOMLEFT", 900, 800 }, "its top-left held still")
    T.eq(CP.db.gatherPoint, { "TOPLEFT", "BOTTOMLEFT", 900, 800 }, "and its spot saved")
    T.eq(CP.GatherList.width, P.WIDTH + 60 - 2 * P.BODY_PAD, "the rows take the new width")
end)

T.test("the grip keeps the panel between its least and largest size", function()
    scene()
    standAt(100, 900)
    detach()
    CP.db.gatherSize = { P.WIDTH, 400 }
    GP.Fit()
    dragGrip(-1000, -1000)
    T.eq(CP.db.gatherSize, GP.SIZE_MIN, "the least: the header and about four rows")
    dragGrip(2000, 300)
    T.eq(CP.db.gatherSize[1], GP.MAX_W, "the widest")
    World.set(UIParent, "GetWidth", function() return 1920 end)
    World.set(UIParent, "GetHeight", function() return 700 end)
    dragGrip(0, 2000)
    T.eq(CP.db.gatherSize[2], 700, "the tallest: the screen")
    standAt(1700, 300)
    dragGrip(400, 400)
    T.eq(CP.db.gatherSize, { 220, 300 }, "no further than the screen's right and bottom edges")
    anchorIsPanel("at the edges")
end)

T.test("a right-click on the grip puts back a first detach's size", function()
    scene()
    standAt(900, 800)
    World.set(CP.GatherList, "NeedHeight", function() return 300 end)
    World.set(CP.GatherList, "Drawn", function() return { {} }, {}, 0 end)
    detach()
    dragGrip(100, 100)
    T.ok(CP.db.gatherSize[1] > P.WIDTH)
    GP.grip:GetScript("OnMouseUp")(GP.grip, "RightButton")
    T.eq(CP.db.gatherSize, { P.WIDTH, 300 + 2 * P.BODY_PAD + 4 })
    anchorIsPanel("after a reset")
end)

T.test("the anchor is the panel's rect after a move, a resize and a reload", function()
    scene()
    standAt(900, 800)
    detach()
    dragTo(400, 700)
    standAt(400, 700)
    anchorIsPanel("after a move")
    dragGrip(40, 20)
    anchorIsPanel("after a resize")
    local w, h = CP.db.gatherSize[1], CP.db.gatherSize[2]

    -- A reload without Daylight UI: the anchor takes the saved size and spot at login.
    GP.anchor:SetSize(1, 1)
    GP.anchor:ClearAllPoints()
    GP.PlaceAnchor()
    T.eq(size(GP.anchor), { w, h }, "the saved size")
    T.eq(point(GP.anchor), { "TOPLEFT", UIParent, "BOTTOMLEFT", 400, 700 }, "the saved spot")
    GP.Update()
    anchorIsPanel("after a reload")

    -- With Daylight UI's mover: the anchor has its size before the mover places it by its centre.
    GP.anchor:SetSize(1, 1)
    local at
    CP.Plugin.RegisterMovers({ RegisterMover = function(frame)
        if frame == GP.anchor then at = size(frame) end
        return true
    end })
    T.eq(at, { w, h }, "sized before the mover places it")
end)

T.test("the mover's wheel still scales the detached panel", function()
    scene()
    standAt(900, 800)
    detach()
    local scales = {}
    World.set(GP.sheet, "SetScale", function(_, s) scales[#scales + 1] = s end)
    World.set(GP.anchor, "GetScale", function() return 1.2 end)
    GP.anchor:SetScale(1.2)
    T.eq(scales[#scales], 1.2, "the panel takes the anchor's scale")
    anchorIsPanel("scaled")
end)

T.test("in /dui unlock the grip rises over the mover handles", function()
    scene()
    detach()
    local strata = {}
    World.set(GP.grip, "SetFrameStrata", function(_, s) strata[#strata + 1] = s end)
    World.set(_G, "DaylightUI", { Movers = { unlocked = true } })
    GP.LiftGrip()
    T.eq(strata[#strata], "FULLSCREEN", "unlocked: above the handles")
    World.set(_G, "DaylightUI", { Movers = { unlocked = false } })
    GP.LiftGrip()
    T.eq(strata[#strata], CP.Style.WINDOW_STRATA, "locked: the panel's own strata")
end)

T.test("with Daylight UI the grip is its own window grip, Win.Grip", function()
    local made, opts = CreateFrame("Button"), nil
    local target = CreateFrame("Frame")
    target:SetSize(300, 200)
    World.set(_G, "DaylightUI", { API = { major = 1 }, Win = { Grip = function(f, o)
        T.eq(f, target)
        opts = o
        return made
    end } })
    local got = {}
    local g = CP.Style.Grip(target, { min = { 220, 160 },
        start = function() got.start = true end,
        resized = function(w, h) got.resized = { w, h } end,
        done = function(w, h) got.done = { w, h } end,
        reset = function() got.reset = true end })
    T.eq(g, made, "Daylight UI's grip")
    T.eq(opts.min, { 220, 160 })
    opts.resized(250, 180, true)
    T.eq(got.resized, { 250, 180 }, "each step of the drag")
    opts.resized(1, 1)
    T.eq(got.resized, { 250, 180 }, "its closing relayout isn't a step")
    opts.place(target)
    T.eq(got.done, { 300, 200 }, "the drop")
    opts.reset()
    T.ok(got.reset)
end)

-- Attached is unchanged ---------------------------------------------------------------------

T.test("attaching after a resize: the panel is the guide window's width and height again, no grip", function()
    scene()
    standAt(900, 800)
    detach()
    dragGrip(100, 100)
    attach()
    T.eq(GP.sheet:GetWidth(), GP.WIDTH, "the guide window's panel width")
    T.eq(CP.GatherList.width, GP.WIDTH - 2 * P.BODY_PAD)
    T.eq(GP.sheet:GetHeight(), P.frame:GetHeight(), "the window's height")
    T.ok(not GP.grip:IsShown(), "no grip")
    T.ok(CP.db.gatherSize ~= nil, "the detached size is kept for next time")
end)
