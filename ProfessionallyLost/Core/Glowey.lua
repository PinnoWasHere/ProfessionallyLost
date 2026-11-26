local _, CP = ...
if CP.stopped then return end

-- Glowey's Recipes, another author's Daylight UI plugin, does some of ProfLost's jobs too. Each
-- switch in the options' "Glowey's Recipes" group leaves one job to it: on, ProfLost stops
-- doing that job. Glowey's Recipes has its own switches the other way (on, Professionally Lost
-- does it). While one of those already leaves a job to ProfLost, ProfLost's switch greys and
-- ProfLost keeps the job, so neither addon leaves it to the other and nobody does it.
--
-- What ProfLost reads of Glowey's Recipes. Nothing of it is ever written.
--   loaded        its public table DaylightRecipes.API
--   its switches  Daylight UI's API.GetSetting("DaylightRecipes", key)
--   its window    its /recipes command, SlashCmdList.DAYLIGHTRECIPES (opens or closes it)
--   its settings  Daylight UI's OptionsPanel.Show on its page, "DaylightRecipes.recipes"

local Glowey = {}
CP.Glowey = Glowey

Glowey.ADDON = "DaylightRecipes"   -- its global and its Daylight UI module's name
Glowey.PAGE = "DaylightRecipes.recipes"
Glowey.COMMAND = "DAYLIGHTRECIPES"

-- Each job: ProfLost's switch, and the switches of Glowey's Recipes that together leave the
-- job to ProfLost. `idle` is its own switch that, off, means it does not do the job at all.
Glowey.JOBS = {
    guide = { key = "gloweyGuide", theirs = { "plGuide" } },
    -- Its buy switch counts only while its guide switch is on too.
    buy = { key = "gloweyBuy", theirs = { "plGuide", "plShop" } },
    tooltip = { key = "gloweyTips", theirs = { "plTips" }, idle = "tooltips" },
}
Glowey.ORDER = { "guide", "buy", "tooltip" }

-- Which jobs a change to one of its switches touches.
local TOUCHES = {}
for job, j in pairs(Glowey.JOBS) do
    for _, k in ipairs(j.theirs) do
        TOUCHES[k] = TOUCHES[k] or {}
        table.insert(TOUCHES[k], job)
    end
    if j.idle then
        TOUCHES[j.idle] = TOUCHES[j.idle] or {}
        table.insert(TOUCHES[j.idle], job)
    end
end

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

-- True while Glowey's Recipes leaves `job` to ProfLost, or does not do it at all.
function Glowey.Defers(job)
    local j = Glowey.JOBS[job]
    if not (j and Glowey.Loaded()) then return false end
    if j.idle and theirs(j.idle) == false then return true end
    for _, k in ipairs(j.theirs) do
        if theirs(k) ~= true then return false end
    end
    return true
end

-- True while ProfLost leaves `job` to Glowey's Recipes.
function Glowey.Handed(job)
    local j = Glowey.JOBS[job]
    if not (j and Glowey.Loaded()) then return false end
    if CP.Settings.Current(j.key) ~= true then return false end
    return not Glowey.Defers(job)
end

-- A switch for `job` changed, ProfLost's or one of its: what the job shows follows at once.
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
    if CP.Plugin then CP.Plugin.RefreshOptions() end
end

-- Daylight UI's SettingChanged for its module.
function Glowey.Heard(path)
    for _, job in ipairs(TOUCHES[path] or {}) do Glowey.Apply(job) end
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
    return (pcall(P.Show, Glowey.PAGE))
end

-- Every job back to ProfLost.
function Glowey.PutBack()
    for _, job in ipairs(Glowey.ORDER) do CP.Settings.Save(Glowey.JOBS[job].key, false) end
end
