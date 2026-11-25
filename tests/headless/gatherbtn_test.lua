-- The guide's title bar holds a gathering panel button (shows and hides the panel) and an
-- attach/detach button (flips the attach setting), left of the gathering button.

local CP = ProfLost
local W, P, GP = CP.Window, CP.Panel, CP.GatherPanel
local LW = 165
local DUROTAR = 1411

local function scene()
    MapWorld.begin({ zone = DUROTAR, level = 20, side = "Horde" })
    CraftWorld.begin({ professions = { [LW] = 100 } })
    World.set(CP.db, "windowClosed", nil)
    World.set(CP.db, "gatherOpen", true)
    World.set(CP.db, "gatherAttached", true)
    World.set(CP.db, "gatherPanelClosed", nil)
    World.set(CP.db, "gatherSize", CP.db.gatherSize)
    World.set(CP.db, "hideInCombat", true)
    World.set(CP.db, "gatherHideInCombat", true)
    World.set(W.managed, "mover", false)
    World.set(GP.managed, "mover", false)
    World.onEnd(function()
        CP.db.gatherAttached = true
        GP.ModeChanged()
        GP.anchor:ClearAllPoints()
    end)
    W.PlaceAnchor()
    W.Update()
    GP.ModeChanged()
    T.ok(P.frame:IsShown(), "the guide window")
end

local function click(b) b:GetScript("OnClick")(b) end

T.test("the title bar has both buttons, left of the fold button, in a row", function()
    scene()
    T.ok(W.gatherButton and W.attachButton, "both buttons exist")
    T.eq(W.gatherButton:GetParent(), P.frame)
    T.ok(W.gatherButton:IsShown() and W.attachButton:IsShown(), "shown while the panel is open")
    local gap = {}
    for name, b in pairs({ fold = W.foldButton, attach = W.attachButton, gather = W.gatherButton }) do
        gap[name] = -select(4, b:GetPoint())   -- the gap from the window's right edge
    end
    T.ok(gap.gather > gap.fold and gap.attach > gap.gather, "attach, gathering, fold, left to right")
end)

T.test("the gathering button shows and hides the panel like /proflost gather", function()
    scene()
    T.ok(GP.Showing(), "open")
    click(W.gatherButton)
    T.ok(not GP.Showing(), "hidden")
    T.ok(not W.attachButton:IsShown(), "no attach button while the panel is hidden")
    click(W.gatherButton)
    T.ok(GP.Showing(), "shown again")
    T.ok(W.attachButton:IsShown(), "the attach button is back")
end)

T.test("the gathering button does not move as the panel closes and opens", function()
    scene()
    local before = select(4, W.gatherButton:GetPoint())
    local fold = select(4, W.foldButton:GetPoint())
    click(W.gatherButton)
    T.ok(not W.attachButton:IsShown(), "attach hidden")
    T.eq(select(4, W.gatherButton:GetPoint()), before, "gathering button stays")
    T.eq(select(4, W.foldButton:GetPoint()), fold, "fold button stays")
    click(W.gatherButton)
    T.eq(select(4, W.gatherButton:GetPoint()), before, "gathering button stays after reopening")
end)

T.test("the attach button detaches and attaches the panel, its tooltip following", function()
    scene()
    T.eq(W.AttachLabel(), "Detach from the guide")
    click(W.attachButton)
    T.eq(CP.db.gatherAttached, false, "detached")
    T.ok(not GP.Attached() and GP.sheet:IsVisible(), "the panel stands on its own")
    T.ok(W.attachButton:IsShown(), "still shown while the detached panel shows")
    T.eq(W.AttachLabel(), "Attach to the guide")
    click(W.attachButton)
    T.eq(CP.db.gatherAttached, true, "attached")
    T.ok(GP.Attached() and GP.Showing(), "back in the guide")
end)

T.test("the attach button hides while a detached panel is closed", function()
    scene()
    click(W.attachButton)
    GP.Close()
    T.ok(not W.attachButton:IsShown(), "panel closed, no attach button")
    click(W.gatherButton)
    T.ok(GP.sheet:IsVisible() and W.attachButton:IsShown(), "opened again")
end)

T.test("the title width holds as the attach button comes and goes", function()
    scene()
    local need = P.TitleNeed()
    click(W.gatherButton)
    T.eq(P.TitleNeed(), need, "same need with the button hidden")
end)

T.test("the buttons carry the chosen art, in the player's own look", function()
    scene()
    T.eq(W.gatherButton.icon.file, CP.GatherList.ROUTE_ICON)
    T.eq(W.attachButton.icon.file, W.ATTACH_ICONS.own)
end)

-- Daylight UI keeps its own profile, and Plugin.Sync copies it back over CP.db at login. A
-- stand-in with a profile of its own shows whether a choice made with a button reaches it.
local function profileDaylight()
    local profile = {}
    DaylightWorld.KeepSettings()
    World.set(_G, "DaylightUI", _G.DaylightUI)
    local DUI
    DUI = {
        API = { major = 1, minor = 1,
                GetSetting = function(scope, key)
                    if scope ~= "ProfLost" then return nil end
                    if profile[key] ~= nil then return profile[key] end
                    return CP.DEFAULTS[key]   -- an unsaved key reads as the module's default
                end },
        RegisterPlugin = function() end,
        Set = function(_, scope, key, v)
            if scope ~= "ProfLost" then return end
            profile[key] = v
            CP.Settings.Set(key, v)   -- its SettingChanged reaches ProfLost
        end,
    }
    _G.DaylightUI = DUI
    return profile, function() CP.Plugin.Sync(DUI.API) end   -- the second is a login
end

T.test("the attach button's choice is saved in Daylight UI and survives a reload", function()
    scene()
    local profile, login = profileDaylight()
    click(W.attachButton)
    T.eq(profile.gatherAttached, false, "Daylight UI's profile holds the detach")
    login()
    T.eq(CP.db.gatherAttached, false, "still detached after the login copies the profile back")
    click(W.attachButton)
    T.eq(profile.gatherAttached, true, "and the attach")
    login()
    T.eq(CP.db.gatherAttached, true, "attached after the login")
end)

T.test("Settings.Save sets through Daylight UI when it is loaded, else here", function()
    scene()
    local profile = profileDaylight()
    T.ok(CP.Settings.Daylight(), "the stand-in counts as loaded")
    CP.Settings.Save("gatherAttached", false)
    T.eq(profile.gatherAttached, false, "in Daylight UI's profile")
    T.eq(CP.db.gatherAttached, false, "and applied here")
    _G.DaylightUI = nil
    CP.Settings.Save("gatherAttached", true)
    T.eq(CP.db.gatherAttached, true, "without Daylight UI: Settings.Set")
    T.eq(profile.gatherAttached, false, "the profile is not touched")
end)
