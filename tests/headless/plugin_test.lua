-- ProfLost as a Daylight UI plugin. The harness has no Daylight UI, so a stand-in
-- records what ProfLost asks of its public API (DaylightUI/API.md 1.1).

local CP = ProfLost

local function standIn(saved)
    DaylightWorld.KeepSettings()
    -- Plugin.Start hands the stand-in's view and API to Host; the test's end puts them back.
    World.set(CP.Host.view, "me", CP.Host.view.me)
    World.set(CP.Host.view, "api", CP.Host.view.api)
    local rec ={ plugins = {}, modules = {}, handlers = {}, movers = {}, fades = {}, commands = {} }
    local me = {
        On = function(event, fn) rec.handlers[event] = fn end,
        RegisterMover = function(frame, key, label, default)
            rec.movers[key] = { frame = frame, label = label, default = default }
            return true
        end,
        RegisterFade = function(spec) rec.fades[spec.key] = spec; return true end,
        RegisterCommand = function(word, fn) rec.commands[word] = fn; return true end,
    }
    _G.DaylightUI = {
        API = { major = 1, minor = 1, For = function() return me end,
                GetSetting = function(scope, key)
                    if scope ~= "ProfLost" then return nil end
                    return saved[key]
                end,
                Skin = function() end, Font = function() return "x" end,
                Text = function(parent) return parent:CreateFontString() end },
        RegisterPlugin = function(_, name, def) rec.plugins[name] = def end,
        RegisterModule = function(_, name, def) rec.modules[name] = def end,
    }
    return rec
end

local function reset()
    _G.DaylightUI = nil
    CP.Window.managed.mover, CP.Window.managed.fade = false, false
    CP.Plugin.active = false
end

T.test("without Daylight UI nothing registers", function()
    reset()
    T.ok(not CP.Settings.InDaylight())
    T.eq(CP.Plugin.Start(), false)
    T.ok(not CP.Window.managed.mover)
end)

T.test("an older or different Daylight UI API keeps ProfLost standalone", function()
    _G.DaylightUI = { API = { major = 1, minor = 0 }, RegisterPlugin = function() end }
    T.ok(not CP.Settings.InDaylight(), "1.0 lacks the plugin calls")
    _G.DaylightUI = { API = { major = 2, minor = 0 }, RegisterPlugin = function() end }
    T.ok(not CP.Settings.InDaylight(), "a different major")
    reset()
end)

-- Button rows that keep a label beside their button word, by that word.
local LABELLED = {
    Show = { ["What's New"] = true },
    Open = { ["Open Glowey's Recipes"] = true, ["Glowey's Recipes settings"] = true },
    ["Put back"] = { ["Put everything back"] = true },
}

T.test("with Daylight UI: plugin, module with every shared setting, command, fade", function()
    local rec = standIn({})
    T.ok(CP.Plugin.Start())
    T.eq(rec.plugins.ProfLost.needs[1], 1)
    T.eq(rec.plugins.ProfLost.title, "Professionally Lost", "the sidebar shows the plugin's label")
    T.eq(rec.plugins.ProfLost.color, CP.ACCENT[1], "the sidebar colour is the plugin's accent")
    local mod = rec.modules.ProfLost
    T.eq(mod.plugin, "ProfLost")
    T.eq(mod.label, "Professionally Lost")
    T.eq(mod.options.pages[1].label, "Professionally Lost")
    local keys = {}
    for _, page in ipairs(mod.options.pages) do
        for _, g in ipairs(page.groups) do
            for _, item in ipairs(g.items) do
                if item.key then keys[item.key] = item.type end
                if item.type == "button" then
                    -- A row with its own button word (What's New: Show, the Glowey's Recipes rows)
                    -- keeps its label.
                    local labelled = LABELLED[item.text]
                    T.ok(item.label == "" and not labelled or labelled ~= nil and labelled[item.label] == true,
                         item.text .. ": the row label " .. tostring(item.label))
                    keys["button:" .. item.text] = item.func
                    keys["hidden:" .. item.text] = item.hidden
                end
            end
        end
    end
    for _, s in ipairs(CP.Settings.LIST) do
        if not s.key or s.kind == "font" then
            -- Buttons have no key; the font row comes from Daylight UI's API.FontRow.
        elseif s.standaloneOnly then
            T.eq(keys[s.key], nil, s.key .. " is Daylight UI's job")
        else
            T.ok(keys[s.key] ~= nil, s.key .. " shown in Daylight UI's options")
            T.eq(mod.defaults[s.key], CP.DEFAULTS[s.key])
        end
    end
    T.eq(keys.dockSide, nil, "no dock side: the guide window never docks")
    T.eq(keys.gatherSide, "dropdown")
    for _, text in ipairs({ "Show every herb", "Show every ore", "Show every herb and ore" }) do
        T.eq(keys["button:" .. text], nil, text .. ": no reset on the options page, the route menu keeps it")
    end
    T.eq(keys["hidden:Report a bug"], nil, "the bug report always shows")
    T.eq(type(keys["button:Report a bug"]), "function", "and the bug report")
    T.eq(mod.section, nil, "its own section under Plugins in the options rail")
    T.eq(#mod.options.pages, 1)
    T.eq(CP.Panel.SETTINGS_PAGE, "ProfLost." .. mod.options.pages[1].id, "the page /dui pl opens")
    T.eq(keys.minimapButton, "toggle", "a Minimap button toggle")
    T.eq(keys.gatherHideInCombat, "toggle", "the gathering panel's own Hide in combat")
    T.eq(keys.collect, "toggle")
    T.eq(keys.gatherList, nil, "the floating checklist's switch is gone")
    T.eq(keys.windowShow, nil, "no visibility dropdown")
    T.eq(keys.hideInCombat, "toggle", "Hide in combat")
    T.eq(CP.DEFAULTS.hideInCombat, true)
    -- A carried-over "always" (stay up in combat) survives Daylight UI's profile default at login.
    local was, carried = CP.db.hideInCombat, CP.db.hideInCombatCarried
    -- The panel's own combat setting follows a carried guide value during Sync: kept apart here.
    World.set(CP.db, "gatherHideInCombat", CP.db.gatherHideInCombat)
    World.set(CP.db, "gatherHideCarried", CP.db.gatherHideCarried)
    CP.db.hideInCombat, CP.db.hideInCombatCarried = false, true
    CP.Plugin.Sync({ GetSetting = function(_, key) if key == "hideInCombat" then return true end end })
    T.eq(CP.db.hideInCombat, false, "the carried value stays")
    CP.db.hideInCombatCarried = nil
    CP.Plugin.Sync({ GetSetting = function(_, key) if key == "hideInCombat" then return true end end })
    T.eq(CP.db.hideInCombat, true, "a value the player picked in Daylight UI wins")
    CP.db.hideInCombat, CP.db.hideInCombatCarried = was, carried
    T.ok(rec.commands.pl ~= nil, "/dui pl")
    T.eq(rec.movers.checklist, nil, "the mover registers at login, once Daylight UI's chat box is up")
    T.ok(not CP.Window.managed.mover)
    T.ok(CP.Window.managed.fade, "Daylight UI's fade takes over combat hiding")
    T.eq(rec.fades.guidewindow.frames()[1], CP.Panel.frame, "the window has its own fade key, on the window")
    T.eq(rec.fades.checklist, nil, "not the old checklist's")
    reset()
end)

T.test("'Gather it yourself' has a dim note under it that follows the current choice", function()
    local saved = { collect = true }
    local rec = standIn(saved)
    CP.Plugin.Start()
    local mod = rec.modules.ProfLost
    local guides
    for _, g in ipairs(mod.options.pages[1].groups) do if g.label == "Guides" then guides = g end end
    T.ok(guides ~= nil, "the Guides group")
    local at
    for i, item in ipairs(guides.items) do if item.key == "collect" then at = i end end
    T.eq(CP.Settings.Find("collect").label, "Gather it yourself")
    local note = guides.items[at + 1]
    T.eq(note.type, "text", "Daylight UI's text row, right under the toggle")
    T.eq(type(note.label), "function", "read again on every refresh")
    T.eq(note.label(), CP.Settings.COLLECT_NOTE.on)
    T.ok(note.label():find("^Note: plans around what you gather and loot, no auction house%.") ~= nil)
    saved.collect = false
    T.eq(note.label(), "Note: plans by auction house prices and lists what to buy in the Shop tab.",
        "flipped in Daylight UI: the note follows at once")
    reset()
    local was = CP.db.collect
    CP.db.collect = true
    T.eq(CP.Settings.CollectNote(CP.Settings.Current("collect")), CP.Settings.COLLECT_NOTE.on, "without Daylight UI: CP.db")
    CP.db.collect = was
end)

T.test("Daylight UI's saved values become ProfLost's, and changes apply", function()
    local saved = { collect = false, fishCook = true }
    local rec = standIn(saved)
    local before = { collect = CP.db.collect, fishCook = CP.db.fishCook }
    CP.Plugin.Start()
    rec.handlers.Login()
    T.eq(CP.db.collect, false, "Buy-and-power-level from the profile")
    T.eq(CP.db.fishCook, true)
    local applied = 0
    local setting = CP.Settings.Find("unitTooltip")
    local apply = setting.apply
    setting.apply = function() applied = applied + 1 end
    rec.handlers.SettingChanged("ProfLost", "unitTooltip", false)
    T.eq(CP.db.unitTooltip, false)
    T.eq(applied, 1, "applied once")
    rec.handlers.SettingChanged("UnitFrames", "unitTooltip", true)
    T.eq(CP.db.unitTooltip, false, "another module's setting is not ours")
    setting.apply = apply
    CP.db.unitTooltip, CP.db.collect, CP.db.fishCook = true, before.collect, before.fishCook
    reset()
end)

T.test("Pattern vendors off clears and redraws the gathering list at once", function()
    local was, current = CP.db.vendorAlerts, CP.VendorWatch.current
    local refreshed = 0
    local refresh = CP.GatherList.Refresh
    CP.GatherList.Refresh = function() refreshed = refreshed + 1 end
    CP.db.vendorAlerts = true
    CP.VendorWatch.current = { zone = 1, found = {} }
    CP.Settings.Set("vendorAlerts", false)
    CP.GatherList.Refresh = refresh
    T.eq(CP.VendorWatch.current, nil, "the zone's patterns are dropped")
    T.ok(refreshed >= 1, "the list redraws now")
    CP.db.vendorAlerts, CP.VendorWatch.current = was, current
end)

T.test("removed: the developer look switch", function()
    T.eq(CP.Settings.Find("ownLook"), nil)
end)

T.test("Daylight UI's colours reach ProfLost's text", function()
    local saved = {}
    for role, c in pairs(CP.Style.color) do saved[role] = { unpack(c) } end
    standIn({})
    DaylightUI.API.Colors = function()
        return { TITLE = { 1, 1, 1 }, TEXT = { 0.9, 0.9, 0.9 }, LABEL = { 0.8, 0.7, 0.5 }, OFF = { 0.5, 0.5, 0.5 },
                 GOOD = { 0.1, 0.9, 0.1 }, WARN = { 0.9, 0.7, 0.1 }, BAD = { 0.9, 0.1, 0.1 } }
    end
    DaylightUI.API.Accent = function() return 0.2, 0.4, 0.6 end
    DaylightUI.API.On = function() end
    local fs = CP.Style.Text(UIParent, "body", CP.Style.color.label)
    local got
    fs.SetTextColor = function(_, r) got = r end   -- the harness keeps no text colour
    CP.Style.Repaint()
    T.eq(CP.Style.color.label[1], 0.8, "label from Daylight UI")
    T.eq(CP.Style.color.accent[3], 0.6, "accent from Daylight UI")
    T.eq(got, 0.8, "an existing string recoloured")
    for role, c in pairs(saved) do
        local mine = CP.Style.color[role]
        for i = 1, #c do mine[i] = c[i] end
    end
    reset()
end)

T.test("the guide window leaves its combat fade to Daylight UI", function()
    CP.Window.managed.mover, CP.Window.managed.fade = true, true
    World.set(CP.db, "gatherHideInCombat", true)
    World.set(CP.db, "gatherPos", { "TOPLEFT", "BOTTOMLEFT", 10, 500 })
    -- The login's settings carry-over writes these.
    World.set(CP.db, "gatherHideCarried", CP.db.gatherHideCarried)
    World.set(CP.db, "gatherSideCarried", CP.db.gatherSideCarried)
    World.set(CP.db, "gatherSide", CP.db.gatherSide)
    T.fire("PLAYER_LOGIN")
    T.fire("PLAYER_REGEN_DISABLED")
    T.fire("PLAYER_REGEN_ENABLED")
    T.ok(true, "no errors with Daylight UI in charge")
    reset()
end)

T.test("the first load says how to start, once", function()
    local was = CP.db.welcomed
    CP.db.welcomed = nil
    local printed = 0
    local saved = CP.Welcome
    CP.Welcome = function() printed = printed + 1 end
    T.fire("PLAYER_ENTERING_WORLD")
    T.advance(4)
    T.fire("PLAYER_ENTERING_WORLD")
    T.advance(4)
    CP.Welcome = saved
    T.eq(printed, 1, "once, not on every loading screen")
    T.ok(CP.db.welcomed)
    CP.db.welcomed = was
end)

T.test("the font setting puts Daylight UI's chosen font on ProfLost's text", function()
    local S = CP.Style
    local fs = S.Text(UIParent, "body")
    -- The harness keeps no font state: give this string one, and watch what it's set to.
    local set
    fs.GetFont = function() return "Fonts/Old.ttf", 13, "" end
    fs.SetFont = function(_, path, px) set = { path, px } end
    local daylight, font = S.Daylight, CP.db.font
    local asked
    S.Daylight = function()
        return { FontFile = function(key) asked = key return "Fonts/Test.ttf" end }
    end
    local ok, err = pcall(function()
        CP.db.font = "fancy"
        S.ApplyFont()
        T.eq(asked, "fancy")
        T.eq(set and set[1], "Fonts/Test.ttf")
        T.eq(set and set[2], 13, "at its size")
    end)
    -- Back to the harness's own methods: the string stays in Style's registry, and a real
    -- path there would let later size changes reach the harness's placeholder size.
    fs.GetFont, fs.SetFont = nil, nil
    S.Daylight, CP.db.font = daylight, font
    T.ok(ok, err)
end)
