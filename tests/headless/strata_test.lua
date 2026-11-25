-- Every ProfLost window stands in Style.WINDOW_STRATA (HIGH): above the action bars,
-- nameplates and world markers in MEDIUM and below, under the game's and Daylight UI's
-- dialogs, menus and tooltips. Free and detached windows are toplevel, as Daylight UI's
-- Win.New makes its windows. Each window's shell stays under its content after every move.

local CP = ProfLost
local S, W, P, GP = CP.Style, CP.Window, CP.Panel, CP.GatherPanel
local LW, TAILOR, MINING = 165, 197, 186
local DUROTAR = 1411

local function rank(strata) return S.STRATA[strata] or 0 end

-- The guide window free with its gathering panel attached and open, through the visual
-- world's levels and strata, with Daylight UI's skins. `pane`: Daylight UI's own profession
-- window is on.
local function scene(pane)
    Visual.begin()
    DaylightWorld.begin({ plugin = true, craftWindow = pane == true })
    Visual.Skin()
    MapWorld.begin({ zone = DUROTAR, level = 20, side = "Horde" })
    CraftWorld.begin({ professions = { [LW] = 100, [TAILOR] = 60, [MINING] = 30 } })
    World.set(CP.db, "windowClosed", nil)
    World.set(CP.db, "windowLocked", nil)
    World.set(CP.db, "windowCollapsed", nil)
    World.set(CP.db, "collect", true)
    World.set(CP.db, "gatherAttached", true)
    World.set(CP.db, "gatherOpen", true)
    World.set(CP.db, "gatherPanelClosed", nil)
    World.set(CP.db, "gatherPoint", nil)
    World.set(CP.db, "gatherSide", "right")
    World.set(CP.db, "windowPoint", { "TOPLEFT", "BOTTOMLEFT", 100, 900 })
    World.set(CP.charDB, "guideMode", "one")
    World.set(CP.VendorWatch, "current", CP.VendorWatch.current)
    World.set(W.managed, "mover", false)
    World.set(GP.managed, "mover", false)
    World.onEnd(function()
        CraftWorld.Close()
        CP.db.gatherAttached = true
        GP.ModeChanged()
        W.opened = false
        GP.anchor:ClearAllPoints()
        W.Update()
    end)
    GP.anchor:ClearAllPoints()
    W.PlaceAnchor()
    W.Update()
    P:Refresh()
    T.advance(0.5)
end

local function detach()
    -- The detached panel saves its size.
    World.set(CP.db, "gatherSize", CP.db.gatherSize)
    CP.db.gatherAttached = false
    GP.ModeChanged()
    T.advance(0.5)
end

-- `frame` stands in the window strata, and its shell sits under `content`.
local function windowed(frame, content, label)
    T.eq(frame:GetFrameStrata(), S.WINDOW_STRATA, label .. ": strata")
    local skin = frame.__shell
    T.ok(skin and skin:GetFrameLevel() < frame:GetFrameLevel(), label .. ": the shell under the frame")
    T.ok(skin and skin:GetFrameLevel() < content:GetFrameLevel(), label .. ": the shell under the content")
end

T.test("the window strata sits over the HUD and under dialogs, menus and tooltips", function()
    local own = rank(S.WINDOW_STRATA)
    T.ok(own > rank("MEDIUM"), "over MEDIUM: action bars, nameplates, Daylight UI's windows")
    T.ok(own < rank("DIALOG"), "under DIALOG: the game's popups, Daylight UI's options and popups")
    T.ok(own < rank("FULLSCREEN_DIALOG") and own < rank("TOOLTIP"), "under menus and tooltips")
end)

T.test("the free guide window, its step card and the attached gathering panel", function()
    scene()
    T.ok(P.frame:IsVisible(), "the window shows")
    windowed(P.frame, P.body, "guide window")
    T.ok(P.frame:IsToplevel(), "toplevel, as Daylight UI's windows")
    T.eq(GP.sheet:GetFrameStrata(), S.WINDOW_STRATA, "attached gathering panel")
    T.ok(not GP.sheet:IsToplevel(), "attached: raised with the window, not alone")
    T.eq(GP.shell:GetFrameStrata(), S.WINDOW_STRATA, "the gathering shell")
    T.ok(GP.shell.__shell:GetFrameLevel() < GP.sheet:GetFrameLevel(), "the gathering shell's skin under the sheet")
    T.eq(CP.GuideTab.ui.details:GetFrameStrata(), S.WINDOW_STRATA, "the step card")
    Visual.Check("free, attached")
end)

T.test("the detached gathering panel and its grip", function()
    scene()
    detach()
    T.ok(GP.sheet:IsVisible(), "the detached panel shows")
    windowed(GP.sheet, GP.body, "detached panel")
    T.ok(GP.sheet:IsToplevel(), "toplevel")
    T.eq(GP.grip:GetFrameStrata(), S.WINDOW_STRATA, "the grip in the panel's strata")
    windowed(P.frame, P.body, "guide window beside it")
    Visual.Check("detached")
    CP.db.gatherAttached = true
    GP.ModeChanged()
    T.advance(0.5)
    T.ok(not GP.sheet:IsToplevel(), "tucked in again: not toplevel")
    T.eq(GP.sheet:GetFrameStrata(), S.WINDOW_STRATA, "tucked in: the window's strata")
    Visual.Check("attached again")
end)

for _, daylight in ipairs({ false, true }) do
    local which = daylight and "Daylight UI's" or "the game's"
    T.test(("with %s profession window open and closed, the window keeps its strata, shell and toplevel"):format(which), function()
        scene(daylight)
        CraftWorld.Open(LW)
        windowed(P.frame, P.body, "open")
        T.ok(P.frame:IsToplevel(), "toplevel")
        Visual.Check(which .. " window open")
        CraftWorld.Close()
        T.advance(0.5)
        windowed(P.frame, P.body, "closed")
        T.ok(P.frame:IsToplevel(), "toplevel")
        Visual.Check(which .. " window closed")
        detach()
        CraftWorld.Open(LW)
        CraftWorld.Close()
        T.advance(0.5)
        windowed(GP.sheet, GP.body, "detached")
        Visual.Check("detached, after " .. which .. " window")
    end)
end

T.test("the Buy confirm and the bug report stand over the windows", function()
    Visual.begin()
    World.set(CP.Buying, "popup", nil)   -- made in this scene, so the visual world sees its strata
    CP.Buying.Confirm({}, 0, nil, function() end)
    local popup = CP.Buying.popup
    World.onEnd(function() popup:Hide() end)
    T.ok(rank(popup:GetFrameStrata()) > rank(S.WINDOW_STRATA), "Buy confirm: " .. popup:GetFrameStrata())
    T.ok(rank(CP.BugReport.STRATA) > rank(S.WINDOW_STRATA), "bug report: " .. CP.BugReport.STRATA)
end)
