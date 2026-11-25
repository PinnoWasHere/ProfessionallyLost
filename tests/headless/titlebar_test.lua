-- The guide window's title bar after the owner's 0.2.8-beta test, buttons as of 0.2.9-beta:
-- Daylight UI's own buttons, the title in the TOC gradient, the profession dropdown as a
-- true toggle with either menu, and the lock button.

local CP = ProfLost
local W, P, S = CP.Window, CP.Panel, CP.Style
local LW, TAILOR = 165, 197
local DUROTAR = 1411

local function scene()
    MapWorld.begin({ zone = DUROTAR, level = 20, side = "Horde" })
    CraftWorld.begin({ professions = { [LW] = 100, [TAILOR] = 60 } })
    World.set(CP.db, "hideInCombat", true)
    World.set(CP.db, "windowClosed", nil)
    World.set(CP.db, "windowLocked", nil)
    World.set(CP.db, "windowPoint", CP.db.windowPoint)
    World.set(CP.charDB, "guideMode", "one")
    World.onEnd(function()
        if W.MenuOpen() then W.CloseMenu() end
        W.opened = false
        W.Update()
    end)
    W.Update()
    T.advance(0.1)   -- a frame apart from whatever the last test closed
    T.ok(P.frame:IsShown(), "the guide window")
end

local function click(b) b:GetScript("OnClick")(b) end
local function down(b) b:GetScript("OnMouseDown")(b) end

-- Buttons -------------------------------------------------------------------------------

T.test("the View switch and the dropdown are ProfLost buttons: hover trace, lit while on", function()
    scene()
    for _, b in ipairs({ W.switchButton, W.pickButton }) do
        T.ok(b.trace ~= nil and b.label ~= nil, "the button's layers")
        T.eq(b:GetHeight(), S.BUTTON_H)
        b:GetScript("OnLeave")(b)   -- an earlier test may have left it hovered
        T.eq(b.glow, 0)
        b:GetScript("OnEnter")(b)
        T.eq(b.glow, 1, "hover lights the trace")
        b:GetScript("OnLeave")(b)
        T.eq(b.glow, 0)
    end
    local b = W.switchButton
    b.SetOn(true)
    T.ok(b.on and b.active, "on")
    b.SetOn(false)
    T.ok(not b.on and not b.active)
    b.SetOff(true)
    T.ok(not b:IsEnabled(), "off: no clicks")
    b.SetOff(false)
    T.ok(not b.off)
end)

T.test("the window's and the gathering panel's chrome shows no tooltip on hover", function()
    scene()
    local owners = 0
    World.set(GameTooltip, "SetOwner", function() owners = owners + 1 end)
    -- The View switch is left out: its words get a tooltip (the UX scene checks it).
    local chrome = { W.closeButton, W.foldButton, W.lockButton, W.pickButton,
        CP.Panel.bugButton, CP.GatherPanel.tab, CP.GatherPanel.closeButton,
        CP.GatherList.head.route, CP.GatherList.head.filter,
        CP.GatherPanel.lockButton }
    for _, b in ipairs(chrome) do
        local enter = b:GetScript("OnEnter")
        if enter then enter(b) end
    end
    T.eq(owners, 0, "no tooltip owner set by any control")
end)

T.test("the step card's Open and Craft buttons are ProfLost buttons too", function()
    scene()
    W.Pick(TAILOR)
    local d = CP.GuideTab.ui.details
    for _, key in ipairs({ "craftOne", "craftAvail", "craftAll" }) do
        T.ok(d[key].SetOn ~= nil and d[key].SetOff ~= nil, key .. " is a ProfLost button")
    end
    local was = S.IsOn(d.craftOne)
    S.SetEnabled(d.craftOne, false)
    T.ok(d.craftOne.off and not d.craftOne:IsEnabled(), "SetEnabled dims it")
    S.SetEnabled(d.craftOne, was)
end)

T.test("with Daylight UI a button is Daylight UI's own (API.Button)", function()
    DaylightWorld.begin({ plugin = true })
    local b = S.Button(UIParent, 60)
    T.ok(b.dressed, "API.Button")
    T.eq(b:GetHeight(), S.BUTTON_H)
    b:Hide()
end)

-- Title -----------------------------------------------------------------------------------

T.test("the title is in the TOC's teal, green and brass gradient", function()
    local text = P.title:GetText()
    T.eq(text, CP.Gradient("Professionally Lost"))
    T.ok(text:find("^|cff1fb5a6P") ~= nil, "teal first")
    T.ok(text:find("|cffe0b43ct|r$") ~= nil, "brass last")
end)

-- The profession menu ----------------------------------------------------------------------

-- The game's context menu, closing on the mouse going down outside it as Blizzard_Menu does.
local function gameMenu()
    local menu = CreateFrame("Frame", nil, UIParent)
    menu:Hide()
    local opened = 0
    World.set(_G, "MenuUtil", { CreateContextMenu = function()
        opened = opened + 1
        menu:Show()
        return menu
    end })
    World.onEnd(function() menu:Hide() end)
    return menu, function() return opened end
end

T.test("the dropdown toggles the game's menu, whichever way the mouse-down closes it", function()
    scene()
    local menu, opened = gameMenu()
    local b = W.pickButton
    down(b)
    click(b)
    T.eq(opened(), 1)
    T.ok(menu:IsShown() and b.on, "open, the button lit")

    -- The menu closes on the mouse going down before the button hears it.
    T.advance(0.5)
    menu:Hide()
    down(b)
    click(b)
    T.eq(opened(), 1, "a click that closed the menu doesn't reopen it")
    T.ok(not menu:IsShown() and not b.on)

    T.advance(0.5)
    down(b)
    click(b)
    T.eq(opened(), 2, "the next click opens it")

    -- The button hears the mouse-down first, then the menu closes.
    T.advance(0.5)
    down(b)
    menu:Hide()
    click(b)
    T.eq(opened(), 2, "still closed")

    -- Same spot, menu still open when the click lands: it closes.
    T.advance(0.5)
    down(b)
    click(b)
    T.eq(opened(), 3)
    T.advance(0.5)
    down(b)
    click(b)
    T.eq(opened(), 3)
    T.ok(not menu:IsShown(), "closed by the click")
end)

T.test("with Daylight UI the dropdown opens its menu, and picking a line picks the profession", function()
    DaylightWorld.begin({ plugin = true })
    scene()
    local b = W.pickButton
    down(b)
    click(b)
    local st = DaylightWorld.state
    T.eq(st.menus, 1, "API.Menu")
    T.eq(st.menu.owner, b)
    T.ok(#st.menu.keys >= 2, "a line per profession")
    T.ok(st.menu.values[TAILOR]:find("^Tailoring") ~= nil, st.menu.values[TAILOR])
    T.eq(st.menu.current, W.ChosenID(), "the current one marked")
    T.ok(W.MenuOpen() and b.on)

    -- Its catcher takes the next click, so the button never hears it.
    DaylightWorld.CloseMenu()
    T.advance(0.1)
    T.ok(not W.MenuOpen() and not b.on, "closed; the button rests")

    T.advance(0.3)
    down(b)
    click(b)
    T.eq(st.menus, 2)
    DaylightWorld.PickMenu(LW)
    T.eq(CP.charDB.guideProf, LW, "picked")
    T.advance(0.1)
    T.eq(b.label:GetText(), "Leatherworking")
    T.ok(not W.MenuOpen())
end)

-- Lock -------------------------------------------------------------------------------------

local function drag()
    W.drag:GetScript("OnDragStart")(W.drag)
    W.drag:GetScript("OnDragStop")(W.drag)
end

T.test("unlocked, the title bar drags the free window and saves where it stands; locked, it holds", function()
    scene()
    local lock = W.lockButton
    T.ok(lock:IsShown(), "the lock shows on the free window")
    T.ok(not W.Locked(), "unlocked by default")
    T.ok(tostring(lock.icon.file):find("Unlock") ~= nil, "the open padlock")
    CP.db.windowPoint = nil
    drag()
    T.ok(CP.db.windowPoint ~= nil, "a drag saves the place")

    click(lock)
    T.eq(CP.db.windowLocked, true, "saved")
    T.ok(tostring(lock.icon.file):find("Lock$") ~= nil, "the shut padlock")
    CP.db.windowPoint = nil
    drag()
    T.eq(CP.db.windowPoint, nil, "locked: no drag")
    click(lock)
    T.eq(CP.db.windowLocked, nil)

    CraftWorld.Open(LW)
    T.ok(lock:IsShown(), "it stays with a profession window open")
    CP.db.windowPoint = nil
    drag()
    T.ok(CP.db.windowPoint ~= nil, "and the title bar still drags")
    CraftWorld.Close()
end)

T.test("with Daylight UI's mover, a drag saves into the mover", function()
    DaylightWorld.begin({ plugin = true })
    scene()
    World.set(W.managed, "mover", true)
    CP.db.windowPoint = nil
    drag()
    local saved = DaylightWorld.Saved()
    T.eq(#saved, 1)
    T.eq(saved[1].key, "plugin.ProfLost.checklist", "the mover's key for the guide window")
    T.eq(saved[1].exact, true, "where it was dropped, off the grid")
    T.eq(CP.db.windowPoint, nil, "not our own key")
end)

T.test("a drag never starts in combat", function()
    scene()
    World.patch("InCombatLockdown", function() return true end)
    CP.db.windowPoint = nil
    drag()
    T.eq(CP.db.windowPoint, nil)
end)

-- The title opens the settings ----------------------------------------------------------

T.test("a right-click on the logo or title opens the settings; elsewhere on the bar it doesn't", function()
    scene()
    local opened = 0
    World.set(P, "OpenSettings", function() opened = opened + 1 end)
    local over = { logo = false, title = false }
    World.set(P.logo, "IsMouseOver", function() return over.logo end)
    World.set(P.title, "IsMouseOver", function() return over.title end)
    local up = W.drag:GetScript("OnMouseUp")
    up(W.drag, "RightButton")
    T.eq(opened, 0, "the bar's empty middle: nothing")
    over.title = true
    up(W.drag, "LeftButton")
    T.eq(opened, 0, "a left click on the title: nothing")
    up(W.drag, "RightButton")
    T.eq(opened, 1, "a right-click on the title")
    over.title, over.logo = false, true
    up(W.drag, "RightButton")
    T.eq(opened, 2, "a right-click on the logo")
    T.eq(W.drag:GetScript("OnDragStart"), W.DragStart, "the left button still drags")
end)

-- Owner, 2026-11-18: "a hover text over the title indicating it can open the settings with right click".
T.test("hovering the title bar says a right-click on the title opens the settings", function()
    scene()
    local said = {}
    World.set(GameTooltip, "SetOwner", function() said = {} end)
    World.set(GameTooltip, "SetText", function(_, t) said[#said + 1] = t end)
    World.set(GameTooltip, "AddLine", function(_, t) said[#said + 1] = t end)
    local enter = W.drag:GetScript("OnEnter")
    T.ok(enter ~= nil, "the bar has a tooltip")
    if enter then enter(W.drag) end
    T.eq(said[2], "Right click to open settings")
    T.ok(tostring(said[1]):find("P", 1, true) ~= nil, "the addon's name first")
end)
