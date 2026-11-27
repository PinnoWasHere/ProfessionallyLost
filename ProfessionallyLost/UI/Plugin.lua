local _, CP = ...
if CP.stopped then return end

-- ProfLost is a Daylight UI plugin (a required dependency). It uses DaylightUI.API
-- (DaylightUI/API.md), and DaylightUI.Motion.Tween for the gathering panel's slide
-- when present (UI/GatherPanel.lua). Settings live in Daylight UI's options window and ride in
-- its profiles: its module holds them and ProfLost copies them into CP.db, which
-- everything else reads. The guide window takes Daylight UI's mover and fade; scroll
-- bars are dressed by its Skins module. In the headless tests (no Daylight UI) none of
-- this runs.

local Plugin = { active = false }
CP.Plugin = Plugin

-- The plugin and module name; the addon folder is CP.name.
local NAME = "ProfLost"
local LABEL = "Professionally Lost"

-- The options rail's icon: white on clear, tinted with the plugin colour (the trail glyph).
Plugin.ICON = CP.MEDIA .. "Trail"

-- The guide window's fade area: its key and where its choices sit in the settings.
Plugin.FADE_KEY = "guidewindow"
Plugin.FADE_PATH = "guideFade"

-- The detached gathering panel's fade area.
Plugin.GATHER_FADE_KEY = "gatherpanel"
Plugin.GATHER_FADE_PATH = "gatherFade"

-- The guide window's mover, then the gathering panel's own: /dui unlock moves the
-- detached panel alone. A first placement stands beside the guide window. Each anchor takes
-- its saved size first, since the mover places it by its centre.
function Plugin.RegisterMovers(me)
    local win, gp = CP.Window, CP.GatherPanel
    win.SizeAnchor()
    win.managed.mover = me.RegisterMover(win.anchor, "checklist", "Guide window",
        win.DefaultPoint()) == true
    gp.SizeAnchor()
    gp.managed.mover = me.RegisterMover(gp.anchor, gp.MOVER, gp.MOVER_LABEL, gp.Beside()) == true
end

-- Daylight UI options rows from CP.Settings. `API` (optional) gives the font row.
function Plugin.Pages(API)
    local groups = {}
    for _, g in ipairs(CP.Settings.Groups()) do
        local items = {}
        for _, s in ipairs(g.items) do
            if s.kind == "choice" then
                -- A dropdown without a key keeps its value elsewhere through get, set and default,
                -- and `choices()` gives its words and order each time it opens (Options/Registry.lua
                -- Validate, Options/Widgets.lua W.dropdown).
                items[#items + 1] = { type = "dropdown", key = s.key, label = s.label, desc = s.desc, values = s.values,
                                      choices = s.choices and function() return s.choices() end or nil,
                                      get = s.get, set = s.set, default = s.default, disabled = s.disabled }
            elseif s.kind == "slider" then
                -- A slider without a key keeps its value elsewhere: Daylight UI's rows take
                -- get, set and default (Options/Registry.lua Validate).
                items[#items + 1] = { type = "slider", key = s.key, label = s.label, desc = s.desc,
                                      min = s.min, max = s.max, step = s.step, unit = s.unit,
                                      get = s.get, set = s.set, default = s.default, disabled = s.disabled }
            elseif s.kind == "font" then
                if API and type(API.FontRow) == "function" then items[#items + 1] = API.FontRow(s.key, s.label, s.desc) end
            elseif s.kind == "note" then
                -- Daylight UI's full-width text row in its dim ink. It reads a label function
                -- again on every refresh (Options/Widgets.lua W.text).
                items[#items + 1] = { type = "text", label = s.text,
                                      hidden = s.when and function() return not s.when() end or nil }
            elseif s.kind == "button" then
                -- The button says it all: an empty row label, the words on the button
                -- (Options/Widgets.lua W.button shows item.text, else the label). A row with
                -- `button` keeps its label beside a button with those words.
                -- `confirm` turns the first click into "Click again" (Options/Registry.lua button rows).
                items[#items + 1] = { type = "button", label = s.button and s.label or "", text = s.button or s.label,
                                      desc = s.desc, func = s.apply, confirm = s.confirm,
                                      hidden = s.when and function() return not s.when() end or nil }
            else
                -- A row coupling a profession the character lacks is hidden, not left on and
                -- dimmed (item.hidden, Options/Registry.lua), unless it shows always and
                -- greys out through its `disabled`.
                local hidden
                if s.couples and not s.showAlways then
                    hidden = function() return not CP.Settings.HasCoupled(s) end
                elseif s.when then
                    hidden = function() return not s.when() end
                end
                local row = { type = "toggle", key = s.key, label = s.label, desc = s.desc,
                              disabled = s.disabled, hidden = hidden }
                if not s.key then
                    -- A switch without a key keeps its value elsewhere (Options/Registry.lua Validate).
                    row.get, row.set, row.default = s.get, s.set, s.default
                elseif s.shown or s.disabled then
                    -- The switch draws Settings.Shown(s), off while the row is greyed (Options.Get
                    -- reads item.get); a click still saves through Daylight UI's own setter, and
                    -- its default is ProfLost's.
                    row.get = function() return CP.Settings.Shown(s) end
                    row.default = function() return CP.DEFAULTS[s.key] end
                    row.set = function(v) return CP.Settings.Save(s.key, v) end
                end
                items[#items + 1] = row
            end
        end
        if #items > 0 then groups[#groups + 1] = { label = g.name, desc = g.desc, items = items } end
    end
    return { { id = "general", label = LABEL,
               desc = "Leveling guides for each profession, what to buy for them, and what to gather where you are.", groups = groups } }
end

-- The module's defaults: ProfLost's own.
function Plugin.Defaults()
    local out = {}
    for _, s in ipairs(CP.Settings.LIST) do
        if s.key then out[s.key] = CP.DEFAULTS[s.key] end
    end
    return out
end

-- True when Daylight UI's value would undo a carried-over setting: its profile still
-- holds the default, and the player hasn't picked one since (CP.CarryOver).
local function keepCarried(key, v)
    if v ~= CP.DEFAULTS[key] then return false end
    return (key == "hideInCombat" and CP.db.hideInCombatCarried)
        or (key == "gatherHideInCombat" and CP.db.gatherHideCarried)
        or (key == "guideSteps" and CP.db.guideStepsCarried) or false
end

-- Copies Daylight UI's saved values into CP.db, without applying them: they are what
-- ProfLost starts with.
function Plugin.Sync(API)
    if not CP.db then return end
    for _, s in ipairs(CP.Settings.LIST) do
        local v = s.key and API.GetSetting(NAME, s.key)   -- buttons have no key
        if s.key and v ~= nil and not keepCarried(s.key, v) then CP.db[s.key] = v end
    end
    -- Until the player sets either, the panel's combat choice is the guide's old one.
    if CP.db.gatherHideCarried then CP.db.gatherHideInCombat = CP.db.hideInCombat ~= false end
    Plugin.SettleSide(API)
    Plugin.SettleSteps(API)
    Plugin.SettleScale()
    if CP.Launcher then CP.Launcher.ShowMinimap() end
    CP.Style.ApplyScale()   -- text made before the saved size and font arrived
    CP.Style.ApplyFont()
    Plugin.RefreshOptions()
end

-- Redraws Daylight UI's options page when it is open, so greyed rows and what they draw
-- follow facts that settled after the page was built (Daylight UI's own OptionsPanel.Refresh).
function Plugin.RefreshOptions()
    local DUI = CP.Settings.Daylight()
    local P = DUI and DUI.OptionsPanel
    if P and type(P.Refresh) == "function" and P.IsShown and P.IsShown() then P.Refresh() end
end

-- Daylight UI 2.2.7 can leave a greyed row at full strength after the first draw of the page
-- (its first-show ease ends after Refresh sets the alpha). When our page is shown, it is
-- redrawn once a frame later and again a little after. Every way of opening the window goes
-- through OptionsPanel.Show, which this hooks.
Plugin.PAGE_ID = "ProfLost.general"
Plugin.REDRAW_AFTER = { 0, 0.3 }

function Plugin.PageShown()
    local DUI = CP.Settings.Daylight()
    local P = DUI and DUI.OptionsPanel
    if not (P and type(P.Current) == "function" and P.Current() == Plugin.PAGE_ID) then return end
    for _, after in ipairs(Plugin.REDRAW_AFTER) do
        C_Timer.After(after, function()
            if P.Current() == Plugin.PAGE_ID then Plugin.RefreshOptions() end
        end)
    end
end

function Plugin.HookPageShown()
    local DUI = CP.Settings.Daylight()
    local P = DUI and DUI.OptionsPanel
    if Plugin.hooked or not (P and type(P.Show) == "function") then return end
    Plugin.hooked = true
    hooksecurefunc(P, "Show", Plugin.PageShown)
end

-- Greyed rows follow the professions (Plan for Enchanting), which load after the page and change
-- while it is open. One redraw per burst of events.
local function skillsChanged() CP:Soon("optionsRefresh", Plugin.RefreshOptions) end
CP:On("ProfLost_SKILLS", skillsChanged)
CP:On("SKILL_LINES_CHANGED", skillsChanged)
CP:On("PLAYER_ENTERING_WORLD", skillsChanged)

-- The panel's side, once after CP.CarryOver set it. Daylight UI saves only what differs
-- from the default, so its "right" may be the default rather than a pick: then the side
-- CP.CarryOver carried wins. A "left" there is the player's pick. The result is saved in
-- Daylight UI too (DaylightUI:Set), so its options page shows it.
function Plugin.SettleSide(API)
    if not CP.db.gatherSideCarried then return end
    CP.db.gatherSideCarried = nil
    local saved = API.GetSetting(NAME, "gatherSide")
    local picked = (saved == "left" or saved == "right") and saved ~= CP.DEFAULTS.gatherSide and saved or nil
    local side = picked or CP.db.gatherSide
    CP.db.gatherSide = side
    local DUI = CP.Settings.Daylight()
    if saved ~= side and DUI and type(DUI.Set) == "function" then DUI:Set(NAME, "gatherSide", side) end
end

-- The step count CP.CarryOver made from an old grip height, once: written into Daylight UI's
-- profile so its slider shows it, unless the player picked another value there.
function Plugin.SettleSteps(API)
    if not CP.db.guideStepsCarried then return end
    CP.db.guideStepsCarried = nil
    local saved = API.GetSetting(NAME, "guideSteps")
    local picked = type(saved) == "number" and saved ~= CP.DEFAULTS.guideSteps and saved or nil
    local steps = picked or CP.db.guideSteps
    CP.db.guideSteps = steps
    local DUI = CP.Settings.Daylight()
    if saved ~= steps and DUI and type(DUI.Set) == "function" then DUI:Set(NAME, "guideSteps", steps) end
end

-- The old single window scale, once: Daylight UI's guide window scale also becomes the
-- gathering panel's, unless the player already wheeled the panel to another size. The
-- scales live in Daylight UI's mover profile, which is where this saves them.
function Plugin.SettleScale()
    if not CP.db.gatherScaleCarried then return end
    local M = CP.Window.Movers()
    if not M then return end
    CP.db.gatherScaleCarried = nil
    local guide = M.PieceScale(CP.Window.MOVER_KEY)
    if guide ~= 1 and M.PieceScale(CP.GatherPanel.MOVER_KEY) == 1 then
        M.SetPieceScale(CP.GatherPanel.MOVER_KEY, guide)
    end
end

function Plugin.Start()
    local DUI = CP.Settings.Daylight()
    if not DUI then return false end
    local API = DUI.API
    local calls = CP.Settings.DAYLIGHT_CALLS
    DUI[calls.plugin](DUI, NAME, {
        title = LABEL, needs = { 1, 1 }, color = CP.ACCENT[1], short = NAME, icon = Plugin.ICON,
        -- The folder differs from the plugin name, so Daylight UI reads the .toc through it.
        addon = CP.name,
        blurb = "Profession leveling guides, a shopping list and a Gathering window.",
    })
    -- Its own section under Plugins in the options rail, as every plugin has.
    DUI[calls.module](DUI, NAME, { plugin = NAME, label = LABEL, defaults = Plugin.Defaults(),
                                   options = { pages = Plugin.Pages(API) } })
    local me = API.For(NAME)
    Plugin.HookPageShown()

    -- Daylight UI's profession window: its Craft events and recipe selection (UI/Host.lua).
    CP.Host.UseDaylight(me, API)
    CP.CraftRows.UseDaylight(me, API)
    CP.Crafting.UseDaylight(me)
    CP.NeededMarks.UseDaylight(me, API)

    me.On("SettingChanged", function(scope, path, value)
        if scope == NAME then
            CP.Settings.Set(path, value)
        elseif scope == CP.Glowey.ADDON then
            CP.Glowey.Heard(path)
        end
    end)
    me.On("Login", function() Plugin.Sync(API) end)
    CP:On("ADDON_LOADED", function(_, addon)
        if addon == CP.name then Plugin.Sync(API) end
    end)

    me.RegisterCommand("pl", function() CP.Panel:OpenSettings() end, "Professionally Lost settings")

    -- Every list scrolls with Daylight UI's own bar (Widgets.Scroll), Skins module or not.
    CP.Style.AdoptScrolls()

    -- The guide window moves with /dui unlock, starting beside the chat box (made by
    -- DaylightUI_Chat, so at login). The mover keeps the checklist's key, so its saved
    -- position carries over.
    local win, gp = CP.Window, CP.GatherPanel
    CP:On("PLAYER_LOGIN", function() Plugin.RegisterMovers(me) end)
    -- The grips rise over the mover handles while /dui unlock is on; the guide window's
    -- shows then even while its padlock is shut.
    me.On("UnlockChanged", function() gp.LiftGrip(); win.SyncGrip() end)

    -- The window has its own fade area. No saved choice means full alpha, and float = false
    -- keeps General > Fade's "Float everything" from hiding it.
    win.managed.fade = me.RegisterFade({ key = Plugin.FADE_KEY, scope = NAME, path = Plugin.FADE_PATH, float = false,
        frames = function() return { CP.Panel.frame } end }) == true

    -- The detached gathering panel fades on its own; attached, it fades with the window.
    gp.managed.fade = me.RegisterFade({ key = Plugin.GATHER_FADE_KEY, scope = NAME, path = Plugin.GATHER_FADE_PATH,
        float = false, frames = function() return gp.Attached() and {} or { gp.sheet } end }) == true

    Plugin.active = true
    return true
end

Plugin.Start()
