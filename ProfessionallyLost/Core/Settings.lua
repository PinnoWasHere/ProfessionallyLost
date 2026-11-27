local _, CP = ...
if CP.stopped then return end

-- Every setting a player can change, in one list; Daylight UI's options page for
-- ProfLost is built from it (UI/Plugin.lua). Each entry: `key` in CP.db, `label`,
-- `desc`, `kind` ("toggle", "choice" with `values` or a `choices()` giving values and order,
-- or "slider" with `min`, `max`, `step`), `group` (the heading it sits under) and `apply()`
-- (what changes right away).
-- `plans` marks a setting that changes what guides plan: true for every guide, or a set of
-- the guides' skill lines. The simulator's influence check tries only these as a
-- profession's coupling switch. `couples` names the profession (skill line) whose coupling
-- the setting switches, and `affects(guideKey)` (optional) says whether it can change that
-- guide; the guide window's header offers it as "with <profession>" (Settings.Switches).
-- `disabled(get)` dims a row and ignores its clicks; a greyed toggle draws off (Settings.Shown).
-- `shown()` (toggles) overrides the position the switch draws. `when()` (toggles and buttons)
-- lists the row only while true; `confirm` (buttons) asks for a second click. A row
-- without a key stores its value elsewhere through `get()`, `set(v)` and `default()`.

local Settings = {}
CP.Settings = Settings

local REGISTER = "RegisterPlugin"   -- Daylight UI's method names, not game APIs
Settings.DAYLIGHT_CALLS = { plugin = REGISTER, module = "RegisterModule" }

local function refreshPanel()
    if CP.Plan and CP.Plan.Invalidate then CP.Plan.Invalidate() end
    if CP.Panel then CP.Panel:Refresh() end
end
local function refreshList() if CP.GatherList then CP.GatherList.Refresh() end end

-- The route menu's reset wording, by which gathering professions the player has (Gather.ResetKind).
Settings.RESET_LABEL = {
    herb = "Show every herb", ore = "Show every ore", leather = "Show every leather",
    both = "Show every herb and ore", herb_leather = "Show every herb and leather",
    ore_leather = "Show every ore and leather", all = "Show every herb, ore and leather",
}

-- "Plan for Enchanting": on by default. Init.lua's defaults are read at ADDON_LOADED,
-- after this file loads.
CP.DEFAULTS.deEnchant = true
CP.DEFAULTS.mapzRoute = true


-- True when the character has Enchanting, so "Plan for Enchanting" does something.
function Settings.HasEnchanting()
    return CP.Sourcing ~= nil and CP.Sourcing.PlayerSkills()[CP.Shared.ENCHANTING] == true
end

-- True when the character has Enchanting and another profession whose crafts disenchant, so
-- "Plan for Enchanting" has something to change.
function Settings.CanPlanEnchanting()
    if not Settings.HasEnchanting() then return false end
    for line, has in pairs(CP.Sourcing.PlayerSkills()) do
        if has and line ~= CP.Shared.ENCHANTING and Settings.Disenchants(line) then return true end
    end
    return false
end

-- True when the character has the profession (skill line) that setting `s` couples in, or `s`
-- couples none. Daylight UI's options page hides a coupling row while this is false.
function Settings.HasCoupled(s)
    if not (s and s.couples) then return true end
    return CP.Sourcing ~= nil and CP.Sourcing.PlayerSkills()[s.couples] == true
end

-- "Fish for Cooking" counts only while "Gather it yourself" is on.
function Settings.FishCook()
    return CP.db ~= nil and CP.db.fishCook == true and CP.db.collect ~= false
end

-- The price addon pick, kept in CP.db.priceSource, not by key. Its choices are read each time
-- the dropdown opens (Pricing.Listed), so an addon switched on later shows up.
local priceRow = {
    kind = "choice", group = "Prices",
    label = "Price Addon",
    desc = "Whose auction house prices to use. Automatic: the first addon that has prices. "
        .. "Professionally Lost's Own: its Scan prices button at the auction house. "
        .. "An item the picked addon has no price for is priced by the others.",
    choices = function() return CP.Pricing.Listed() end,
    get = function() return CP.Pricing.Selected() end,
    set = function(key) return CP.Pricing.Choose(key) end,
    default = function() return CP.Pricing.config.automatic end,
    apply = function() end,
}

-- The options page reads in this order: groups by first appearance, most used first, and a
-- switch that greys another sits right above it. Labels are four words or fewer. Values are
-- saved by `key`, so a new label or order keeps every player's choice.
Settings.LIST = {
    { key = "collect", group = "Guides", kind = "toggle", plans = true,
      label = "Gather it yourself",
      desc = "Guides plan around what you gather and loot, with no auction house. Off, they plan by auction house prices and list what to buy.",
      apply = function() refreshPanel(); refreshList() end },
    -- Under it, what the current choice does. Daylight UI's text row reads it again on
    -- every setting change.
    { kind = "note", group = "Guides", text = function() return Settings.CollectNote(Settings.Current("collect")) end },
    { key = "fishCook", group = "Guides", kind = "toggle", plans = { [185] = true }, couples = 356,
      label = "Fish for Cooking",
      desc = "With Fishing, your Cooking guide plans fish recipes and counts the fish as cheap while Fishing levels, "
          .. "and the Gathering window finds spots for them. Applies only while Gather it yourself is on.",
      disabled = function(get) return get("collect") == false end,
      apply = function() refreshPanel(); refreshList() end },
    { key = "deEnchant", group = "Guides", kind = "toggle", plans = true, couples = 333,
      affects = function(key) return Settings.Disenchants(key) end,
      label = "Plan for Enchanting",
      desc = "Your other guides favor crafts you can disenchant for what Enchanting needs, so they use more materials. "
          .. "Greyed out until you have Enchanting and a profession whose items you can disenchant.",
      showAlways = true,
      disabled = function() return not Settings.CanPlanEnchanting() end,
      -- Greyed out, the switch reads off; the saved choice stays.
      shown = function() return Settings.CanPlanEnchanting() and Settings.Current("deEnchant") ~= false end,
      apply = function() refreshPanel(); refreshList() end },
    { key = "mapzRoute", group = "Guides", kind = "toggle",
      label = "Route with Mapzeroth",
      desc = "Waypoint pins plan a Mapzeroth route there and start it. Off, they set the game's own waypoint. Needs the Mapzeroth addon.",
      disabled = function() return not CP.Mapz.Loaded() end,
      apply = function() end },
    -- The corner grip's vertical drag sets the same value in whole rows (Window.Resize).
    { key = "guideSteps", group = "Guide window", kind = "slider", min = 1, max = 15, step = 1,
      label = "Steps shown",
      desc = "How many steps the guide window lists before the rest scroll. Dragging the window's corner up or down sets it too.",
      apply = function() if CP.Panel then CP.Panel:Refresh() end end },
    -- The scale /dui unlock's mouse wheel sets on the guide window's mover: the same stored value.
    { kind = "slider", group = "Guide window", min = 0.5, max = 2, step = 0.05, unit = "x",
      label = "Guide window scale",
      desc = "The guide window's size, as the mouse wheel over its handle in /dui unlock sets it. The attached Gathering window follows it.",
      get = function() return CP.Window.PieceScale() end,
      set = function(v) CP.Window.SetPieceScale(v) end,
      default = function() return 1 end },
    { key = "textScale", group = "Guide window", kind = "slider", min = 0.85, max = 1.15, step = 0.05, unit = "x",
      label = "Text size",
      desc = "Text in the guide, the shopping list and the Gathering window.",
      apply = function()
          CP.Style.ApplyScale()
          if CP.Panel then CP.Panel:Refresh() end
          if CP.GatherList then CP.GatherList.Refresh() end
      end },
    { key = "font", group = "Guide window", kind = "font",
      label = "Font",
      desc = "General uses your Daylight UI font.",
      apply = function() CP.Style.ApplyFont() end },
    { key = "windowOpacity", group = "Guide window", kind = "slider", min = 0.2, max = 1, step = 0.05,
      label = "Window opacity",
      desc = "How solid the guide window and the Gathering window are behind their text. It starts at your Daylight UI window opacity.",
      apply = function() CP.Style.ApplyOpacity() end },
    { key = "hideInCombat", group = "Guide window", kind = "toggle",
      label = "Hide in combat",
      desc = "Hides the guide window during a fight and brings it back after. A profession window still shows it.",
      apply = function() if CP.Window then CP.Window.Update() end end },
    { key = "minimapButton", group = "Guide window", kind = "toggle",
      label = "Minimap button",
      desc = "Shows a button on the minimap. Left-click opens the guide window, Shift-click the Gathering window, right-click these settings.",
      apply = function() if CP.Launcher then CP.Launcher.ApplyMinimap() end end },
    { key = "gatherAttached", group = "Gathering window", kind = "toggle",
      label = "Attach to guide window",
      desc = "The Gathering window slides out of the guide window. Off, it is a window of its own (Shift-click the minimap button or /proflost gather).",
      apply = function() if CP.GatherPanel then CP.GatherPanel.SettingChanged() end end },
    { key = "gatherSide", group = "Gathering window", kind = "choice",
      values = { left = "Left", right = "Right" },
      label = "Side when attached",
      desc = "Which side of the guide window the attached Gathering window opens on.",
      apply = function() if CP.GatherPanel then CP.GatherPanel.Layout() end end },
    -- The detached panel's own mover scale. Attached, the panel takes the guide window's scale.
    { kind = "slider", group = "Gathering window", min = 0.5, max = 2, step = 0.05, unit = "x",
      label = "Gathering window scale",
      desc = "The detached Gathering window's size, as the mouse wheel over its handle in /dui unlock sets it. Follows the guide window while attached.",
      disabled = function(get) return get("gatherAttached") ~= false end,
      get = function() return CP.GatherPanel.PieceScale() end,
      set = function(v) CP.GatherPanel.SetPieceScale(v) end,
      default = function() return 1 end },
    { key = "vendorAlerts", group = "Gathering window", kind = "toggle",
      label = "Pattern vendors",
      desc = "Lists patterns you can learn from vendors in your zone. New ones pulse, then show a count.",
      apply = function()
          if CP.VendorWatch.Check then CP.VendorWatch.Check() end
          refreshList()
      end },
    { key = "mapIcons", group = "Gathering window", kind = "toggle",
      label = "Icons on the map",
      desc = "ProfLost's icons and route lines on the world map and the minimap. Waypoints and arrows you ask for still work when it is off.",
      apply = function()
          if CP.RouteMap then CP.RouteMap.IconsChanged() end
          if CP.VendorWatch then CP.VendorWatch.IconsChanged() end
      end },
    { key = "otherZones", group = "Gathering window", kind = "toggle",
      disabled = function(get) return get("mapIcons") == false end,
      label = "Other zones",
      desc = "While leveling, the rest of your continent's routes and grind spots show dimmed, so you can plan ahead. "
          .. "Farm mode always shows them. Greyed out while Icons on the map is off.",
      apply = function() if CP.RouteMap then CP.RouteMap.Refresh() end end },
    { key = "gatherHideInCombat", group = "Gathering window", kind = "toggle",
      label = "Hide in combat",
      desc = "Hides the detached Gathering window during a fight and brings it back after. Attached, it hides with the guide window.",
      apply = function() if CP.Window then CP.Window.Update() end end },
    { key = "itemTooltip", group = "Tooltips and bags", kind = "toggle",
      label = "Item tooltips",
      desc = "How many of the item your guides still need.",
      apply = function() end },
    { key = "unitTooltip", group = "Tooltips and bags", kind = "toggle",
      label = "Skinning tooltips",
      desc = "Skinning drop chances, the skill needed, and how many to gather.",
      apply = function() end },
    { key = "neededMarks", group = "Tooltips and bags", kind = "toggle",
      label = "Bag marks",
      desc = "A profession icon on bag items your guides need, so you don't sell them.",
      apply = function() if CP.NeededMarks then CP.NeededMarks.Refresh() end end },
    priceRow,
    { kind = "note", group = "Prices", text = function() return CP.Pricing.ChoiceNote() end },
    -- Jobs Glowey's Recipes does too (Core/Glowey.lua). The rows show only while it is loaded.
    { key = "gloweyGuide", group = "Glowey's Recipes", kind = "toggle",
      label = "Leveling guide",
      desc = "Leave the leveling guide to Glowey's Recipes. The guide window, and a Gathering window attached to it, "
          .. "stay shut until you open them, and the profession window's recipes lose their step marks. "
          .. "Greyed out while Glowey's Recipes leaves its Leveling Guide to Professionally Lost.",
      when = function() return CP.Glowey.Loaded() end,
      disabled = function() return CP.Glowey.Defers("guide") end,
      apply = function() CP.Glowey.Apply("guide") end },
    { key = "gloweyBuy", group = "Glowey's Recipes", kind = "toggle",
      label = "Buy for guide button",
      desc = "Leave buying at vendors to Glowey's Recipes, so the Buy for guide button stays off the vendor's window. "
          .. "Greyed out while Glowey's Recipes leaves its Buy Lists to Professionally Lost.",
      when = function() return CP.Glowey.Loaded() end,
      disabled = function() return CP.Glowey.Defers("buy") end,
      apply = function() CP.Glowey.Apply("buy") end },
    { key = "gloweyTips", group = "Glowey's Recipes", kind = "toggle",
      label = "Item tooltip lines",
      desc = "Leave the guides' needs in item tooltips to Glowey's Recipes, so Professionally Lost adds no lines there. "
          .. "Greyed out while Glowey's Recipes leaves its guide line to Professionally Lost or has its item tooltips off.",
      when = function() return CP.Glowey.Loaded() end,
      disabled = function() return CP.Glowey.Defers("tooltip") end,
      apply = function() CP.Glowey.Apply("tooltip") end },
    { kind = "button", group = "Glowey's Recipes",
      label = "Open Glowey's Recipes", button = "Open",
      desc = "Opens Glowey's Recipes' window.",
      when = function() return CP.Glowey.CanOpen() end,
      apply = function() CP.Glowey.Open() end },
    { kind = "button", group = "Glowey's Recipes",
      label = "Glowey's Recipes settings", button = "Open",
      desc = "Opens Glowey's Recipes' own options page, where its switches leave jobs to Professionally Lost.",
      when = function() return CP.Glowey.CanOpenSettings() end,
      apply = function() CP.Glowey.OpenSettings() end },
    { kind = "button", group = "Glowey's Recipes",
      label = "Put everything back", button = "Put back", confirm = true,
      desc = "Turns all three off, so Professionally Lost does every job itself again.",
      when = function() return CP.Glowey.Loaded() end,
      apply = function() CP.Glowey.PutBack() end },
    { kind = "button", group = "Help",
      label = "Report a bug",
      desc = "Opens a report to copy, with your versions, where you are, the guide's steps and recent errors.",
      apply = function() if CP.BugReport then CP.BugReport.Show() end end },
    { key = "whatsNew", group = "Help", kind = "toggle",
      label = "Show What's New",
      desc = "Once after each update.",
      apply = function() end },
    -- `button` is the word on the button; the label sits beside it (UI/Plugin.lua).
    { kind = "button", group = "Help",
      label = "What's New", button = "Show",
      desc = "The changes in this version.",
      apply = function() if CP.News then CP.News.Show(true) end end },
    { key = "newerNotice", group = "Help", kind = "toggle",
      label = "Newer version notice",
      desc = "Once a session, says when someone in your guild, group or nearby runs a newer Professionally Lost.",
      apply = function() end },
    -- Shown only while Daylight UI has its tour engine (UI/Tour.lua).
    { kind = "button", group = "Help",
      label = "Take the tour",
      desc = "A short tour of the guide window's main parts. Opens the guide window first if it is shut.",
      when = function() return CP.Tour ~= nil and CP.Tour.Engine() ~= nil end,
      apply = function() if CP.Tour then CP.Tour.Replay() end end },
}

-- Each group's line under its heading on the options page.
Settings.GROUP_DESC = {
    ["Guides"] = "Each profession's steps from your skill to the cap, with what to craft, buy and gather.",
    ["Gathering window"] = "The window beside the guide window: what you can gather in your zone, and a route.",
    ["Guide window"] = "Move it in unlock mode (/dui unlock), or drag its title bar while its lock is open.",
    ["Tooltips and bags"] = "Lines the guides add to the game's tooltips and bags.",
    ["Prices"] = "The game lets one addon scan the auction house at a time. Pick the one Professionally Lost takes prices from; the others fill gaps.",
    ["Glowey's Recipes"] = "Glowey's Recipes does these jobs too. Switch one on to leave it to Glowey's Recipes.",
    ["Help"] = "Something wrong? A report holds what's needed to find it.",
}

-- Groups in the order their first setting appears.
function Settings.Groups()
    local order, byName = {}, {}
    for _, s in ipairs(Settings.LIST) do
        if not byName[s.group] then
            byName[s.group] = {}
            order[#order + 1] = { name = s.group, desc = Settings.GROUP_DESC[s.group], items = byName[s.group] }
        end
        table.insert(byName[s.group], s)
    end
    return order
end

-- The "Gather it yourself" note for `on`, the setting's value.
Settings.COLLECT_NOTE = {
    on = "Note: plans around what you gather and loot, no auction house. Guide steps favor gathered materials and the Shop tab is hidden.",
    off = "Note: plans by auction house prices and lists what to buy in the Shop tab.",
}

function Settings.CollectNote(on)
    return on and Settings.COLLECT_NOTE.on or Settings.COLLECT_NOTE.off
end

-- A setting's value now: Daylight UI's saved one while it is loaded (it is set before
-- ProfLost hears of the change), else CP.db's.
function Settings.Current(key)
    local DUI = Settings.Daylight()
    local v = DUI and DUI.API.GetSetting and DUI.API.GetSetting("ProfLost", key)
    if v ~= nil then return v end
    return CP.db and CP.db[key]
end

-- True when guide `key` has a recipe whose product disenchants: "Plan for Enchanting" can
-- change it. Kept per guide.
local disenchants = {}
function Settings.Disenchants(key)
    if disenchants[key] == nil then
        local guide = CP.Guides and CP.Guides[key]
        local any = false
        for _, r in pairs(guide and guide.recipes or {}) do
            if #CP.Shared.DEYield(r) > 0 then any = true break end
        end
        disenchants[key] = any
    end
    return disenchants[key]
end

-- The coupling switches for guide `key`: { { setting, line, on } } for each setting that
-- `couples` a profession the character has into this guide and is not greyed out.
function Settings.Switches(key)
    local out = {}
    local skills = CP.Sourcing and CP.Sourcing.PlayerSkills() or {}
    local function get(k) return Settings.Current(k) end
    for _, s in ipairs(Settings.LIST) do
        local plans = s.plans == true or (type(s.plans) == "table" and s.plans[key])
        if s.couples and plans and key ~= s.couples and skills[s.couples]
            and not (s.disabled and s.disabled(get)) and not (s.affects and not s.affects(key)) then
            out[#out + 1] = { setting = s, line = s.couples, on = Settings.Current(s.key) ~= false }
        end
    end
    return out
end

-- The position toggle `s` draws. Its own `shown()` when it has one, else off while the row is
-- greyed out (`disabled`), else the saved value. The saved choice is never changed here.
function Settings.Shown(s)
    if s.shown then return s.shown() end
    if s.disabled and s.disabled(function(k) return Settings.Current(k) end) then return false end
    return Settings.Current(s.key) ~= false
end

-- Saves setting `key` the way the options page does, for any control outside it. Through
-- Daylight UI's saved settings while it is loaded (its SettingChanged applies the value, and
-- Plugin.Sync reads it back at login), else here. Returns Daylight UI's answer when it took
-- the value (an options row treats an explicit false as a refusal), else Settings.Set's.
function Settings.Save(key, value)
    local DUI = Settings.Daylight()
    local viaDUI = DUI and type(DUI.Set) == "function"
    local took
    if viaDUI then took = DUI:Set("ProfLost", key, value) end
    local changed = Settings.Set(key, value)
    if viaDUI then return took end
    return changed
end

-- Turns toggle `key` over, through Settings.Save.
function Settings.Toggle(key)
    local v = not (Settings.Current(key) ~= false)
    Settings.Save(key, v)
    return v
end

-- Slider `key`'s nearest value to `v`: on its steps, between its min and max.
function Settings.Bound(key, v)
    local s = Settings.Find(key)
    v = math.floor((v - s.min) / s.step + 0.5) * s.step + s.min
    return math.max(s.min, math.min(s.max, v))
end

function Settings.Find(key)
    if key == nil then return nil end   -- buttons have no key
    for _, s in ipairs(Settings.LIST) do
        if s.key == key then return s end
    end
end

-- Sets a setting and applies it. Returns true when it changed.
function Settings.Set(key, value)
    local s = Settings.Find(key)
    if not s or not CP.db or CP.db[key] == value then return false end
    CP.db[key] = value
    -- The player's own pick now.
    if key == "hideInCombat" then CP.db.hideInCombatCarried = nil end
    if key == "hideInCombat" or key == "gatherHideInCombat" then CP.db.gatherHideCarried = nil end
    if key == "gatherSide" then CP.db.gatherSideCarried = nil end
    s.apply()
    return true
end

-- Daylight UI's plugin API (1.1 or later) is there: always in game (a required
-- dependency), never in the headless tests unless they put in a stand-in.
local DAYLIGHT = "DaylightUI"  -- the addon's global; an optional dependency, not a game API

-- Daylight UI's addon table when its plugin API can be used, else nil.
function Settings.Daylight()
    local addon = _G[DAYLIGHT]
    local API = addon and addon.API
    if API and API.major == 1 and (API.minor or 0) >= 1 and type(addon[REGISTER]) == "function" then return addon end
end

function Settings.InDaylight()
    return Settings.Daylight() ~= nil
end
