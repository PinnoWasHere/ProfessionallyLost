local _, CP = ...
if CP.stopped then return end

-- Glowey's Recipes, another author's Daylight UI plugin, does some of ProfLost's jobs too. Its
-- options page has six switches, one per job: on, Professionally Lost does it. ProfLost's
-- "Glowey's Recipes" group shows the same six and reads and writes those same saved switches,
-- so the two pages always agree. ProfLost follows them for the three jobs it has: the leveling
-- guide, the vendor Buy button and the item tooltip lines.
--
-- What ProfLost uses of Glowey's Recipes:
--   loaded        its public table DaylightRecipes.API
--   its switches  read with Daylight UI's API.GetSetting("DaylightRecipes", key), written with
--                 DaylightUI:Set("DaylightRecipes", key, value), which fires its SettingChanged
--                 (its own first-load window writes them the same way, its ProfLost.lua Set)
--   answered      its first-load question, DaylightRecipesDB.proflost.asked (read only)
--   its window    its /recipes command, SlashCmdList.DAYLIGHTRECIPES (opens or closes it)
--   its settings  its hub's GloweyHub.impl.Show("DaylightRecipes", "recipes") when there, else
--                 Daylight UI's OptionsPanel.Show("DaylightRecipes.recipes")

local Glowey = {}
CP.Glowey = Glowey

Glowey.ADDON = "DaylightRecipes"   -- its global and its Daylight UI module's name
Glowey.PAGE_ID = "recipes"         -- its options page (its Core.lua pages)
Glowey.PAGE = Glowey.ADDON .. "." .. Glowey.PAGE_ID
Glowey.COMMAND = "DAYLIGHTRECIPES"

-- Its six jobs, in its order, by its switch; their rows are in Core/Settings.lua. A `follows`
-- job means nothing while the guide is Glowey's Recipes'. `idle` is its switch that, off, means
-- it does not do the job at all.
Glowey.JOBS = {
    guide = { key = "plGuide" },
    buy = { key = "plShop", follows = "guide" },
    trainer = { key = "plTrainer", follows = "guide" },
    tooltip = { key = "plTips", idle = "tooltips" },
    prices = { key = "plPrices" },
    step = { key = "plStep", follows = "guide" },
}
Glowey.ORDER = { "guide", "buy", "trainer", "tooltip", "prices", "step" }

-- The ProfLost jobs a change to one of its switches touches.
local TOUCHES = {
    plGuide = { "guide", "buy" },
    plShop = { "buy" },
    plTips = { "tooltip" },
    tooltips = { "tooltip" },
}

function Glowey.Loaded()
    local g = rawget(_G, Glowey.ADDON)
    return type(g) == "table" and type(rawget(g, "API")) == "table"
end

-- One of its saved switches, or nil when it can't be read.
local function theirs(key)
    local DUI = CP.Settings.Daylight()
    local get = DUI and DUI.API.GetSetting
    if type(get) ~= "function" then return nil end
    local ok, v = pcall(get, Glowey.ADDON, key)
    if ok then return v end
end

-- True when its switch for `job` says Professionally Lost does it.
function Glowey.Ours(job)
    local j = Glowey.JOBS[job]
    return j ~= nil and theirs(j.key) == true
end

-- Sets its switch for `job` through Daylight UI, which saves it in the profile and tells both
-- addons. Returns Daylight UI's answer, or false when it can't be written.
function Glowey.Set(job, on)
    local j = Glowey.JOBS[job]
    local DUI = CP.Settings.Daylight()
    if not (j and DUI and type(DUI.Set) == "function") then return false end
    local ok, took = pcall(DUI.Set, DUI, Glowey.ADDON, j.key, on == true)
    return ok and took ~= false
end

-- True once the player has picked who does what: its first-load question is answered, or one
-- of its switches is on. Until then both addons do every job, as before either knew the other.
function Glowey.Picked()
    local db = rawget(_G, "DaylightRecipesDB")
    local rec = type(db) == "table" and rawget(db, "proflost")
    if type(rec) == "table" and rawget(rec, "asked") == true then return true end
    for _, job in ipairs(Glowey.ORDER) do
        if Glowey.Ours(job) then return true end
    end
    return false
end

-- True while a `follows` job's row means nothing: the guide is Glowey's Recipes'.
function Glowey.Idle(job)
    local j = Glowey.JOBS[job]
    return j ~= nil and j.follows ~= nil and not Glowey.Ours(j.follows)
end

-- True while ProfLost leaves `job` to Glowey's Recipes.
function Glowey.Handed(job)
    local j = Glowey.JOBS[job]
    if not (j and Glowey.Loaded() and Glowey.Picked()) then return false end
    if j.idle and theirs(j.idle) == false then return false end
    return Glowey.Idle(job) or not Glowey.Ours(job)
end

-- One of its switches changed, from either page: what the job shows follows at once.
-- Leaving the guide shuts the guide window, even one the player opened earlier.
function Glowey.Apply(job)
    if job == "guide" then
        if Glowey.Handed("guide") and CP.Window then CP.Window.byHand = false end
        if CP.Window then CP.Window.Update() end
        if CP.CraftRows then CP.CraftRows.Repaint() end
    elseif job == "buy" and CP.Buying then
        local popup = CP.Buying.popup
        if Glowey.Handed("buy") and popup then popup:Hide() end
        CP.Buying.Update()
    end
end

-- Daylight UI's SettingChanged for its module.
function Glowey.Heard(path)
    for _, job in ipairs(TOUCHES[path] or {}) do Glowey.Apply(job) end
    if CP.Plugin then CP.Plugin.RefreshOptions() end
end

-- Its /recipes command, or nil.
local function command()
    local list = rawget(_G, "SlashCmdList")
    local fn = type(list) == "table" and list[Glowey.COMMAND]
    return type(fn) == "function" and fn or nil
end

-- Daylight UI's options panel when it can show a page, or nil.
local function options()
    local DUI = CP.Settings.Daylight()
    local P = DUI and DUI.OptionsPanel
    return type(P) == "table" and type(P.Show) == "function" and P or nil
end

-- Its hub's Show, or nil. With two or more of Glowey's plugins on, their pages fold under one
-- "Glowey's" entry and its page stays hidden (so Daylight UI shows its home) until the hub opens it.
local function hubShow()
    local hub = rawget(_G, "GloweyHub")
    local impl = type(hub) == "table" and rawget(hub, "impl")
    local show = type(impl) == "table" and rawget(impl, "Show")
    return type(show) == "function" and show or nil
end

function Glowey.CanOpen() return Glowey.Loaded() and command() ~= nil end
function Glowey.CanOpenSettings() return Glowey.Loaded() and options() ~= nil end

-- Its window, as /recipes opens it.
function Glowey.Open()
    local fn = Glowey.Loaded() and command()
    if not fn then return false end
    return (pcall(fn, ""))
end

function Glowey.OpenSettings()
    local P = Glowey.Loaded() and options()
    if not P then return false end
    local show = hubShow()
    if show then return (pcall(show, Glowey.ADDON, Glowey.PAGE_ID)) end
    return (pcall(P.Show, Glowey.PAGE))
end

-- Every job to ProfLost: all six on, as its first-load window suggests.
function Glowey.PutBack()
    for _, job in ipairs(Glowey.ORDER) do Glowey.Set(job, true) end
end
