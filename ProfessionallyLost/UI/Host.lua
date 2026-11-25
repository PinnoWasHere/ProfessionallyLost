local _, CP = ...
if CP.stopped then return end

-- Daylight UI's and DaylightMogul's profession windows: whether one is up, which profession
-- it lists, and picking a recipe in it. No frame is found by name; the guide window always
-- stands free (UI/Window.lua), and the game's trade skill events say when any profession
-- window is open (Core/Professions.lua).

local Host = {}
CP.Host = Host

-- Daylight UI's plugin view (API.For) and its API, once Plugin.Start hands them over.
local daylightView = { me = nil, api = nil }
Host.view = daylightView

-- The profession Daylight UI's window lists now, or nil while it is shut. Its list
-- refills a frame or more after the game switches profession.
function Host.CraftProfession()
    local api = daylightView.api
    if not (api and type(api.GetCraftProfession) == "function") then return nil end
    local ok, id = pcall(api.GetCraftProfession)
    return ok and id or nil
end

-- True while Daylight UI's own profession window is up. It keeps its own selection and
-- never reads the game's, so C_TradeSkillUI.OpenRecipe doesn't reach it.
function Host.DaylightWindow()
    return Host.CraftProfession() ~= nil
end

-- Daylight UI's core table (the global), or nil.
local function daylight()
    local addon = rawget(_G, "DaylightUI")
    return type(addon) == "table" and addon or nil
end

-- DaylightMogul's Craft API (1.3+), or nil. While Craft.Owns() says true, Daylight UI
-- builds no profession window of its own and Mogul's window shows instead.
local function mogulCraft()
    local mog = rawget(_G, "DaylightMogul")
    local api = type(mog) == "table" and mog.API
    local craft = type(api) == "table" and api.Craft
    return type(craft) == "table" and craft or nil
end

-- True when DaylightMogul's window takes over the game's profession window.
function Host.MogulOwns()
    local craft = mogulCraft()
    if not (craft and type(craft.Owns) == "function") then return false end
    local ok, owns = pcall(craft.Owns)
    return ok and owns == true
end

-- True when Daylight UI's own profession window takes over the game's. It opens a frame
-- or more after the game's, so a pick waits for it instead of landing in the game's
-- hidden window. Daylight UI 1.7 sets craftOwnWindow at login; with an older one that
-- lacks the flag, this holds only while its window is up.
function Host.DaylightOwns()
    if not daylightView.api then return false end
    local addon = daylight()
    local own = addon and addon.craftOwnWindow
    if own == nil then return Host.DaylightWindow() end
    return own == true
end

-- Why Daylight UI's window reports no profession, for the open trace; nil while it has one.
function Host.DaylightWhy()
    if Host.CraftProfession() ~= nil then return nil end
    if not daylightView.me then return "no plugin view: Plugin.Start never handed one over" end
    if not (daylightView.api and type(daylightView.api.GetCraftProfession) == "function") then
        return "its API has no GetCraftProfession"
    end
    local addon = daylight()
    if addon and addon.craftMogul == true then return "its window is off because DaylightMogul's window owns professions" end
    if addon and addon.craftOwnWindow == false then return "its Professions window is turned off" end
    return "its window is shut or has no profession yet"
end

-- Who shows the open profession: "daylight", "mogul", "game" (the game's window or any
-- other addon's), or nil while none is open.
function Host.Holder()
    if Host.DaylightWindow() then return "daylight" end
    if not CP.Professions.tradeSkillOpen then return nil end
    if Host.MogulOwns() then return "mogul" end
    return "game"
end

-- The call a later DaylightMogul could offer to select a recipe. Mogul 0.1.1 has none.
Host.MOGUL_SELECT = "Select"

-- True when DaylightMogul's API offers that call.
function Host.MogulCanSelect()
    local craft = mogulCraft()
    return craft ~= nil and type(craft[Host.MOGUL_SELECT]) == "function"
end

local function mogulSelect(recipeID)
    if not Host.MogulCanSelect() then return false end
    local ok, done = pcall(mogulCraft()[Host.MOGUL_SELECT], recipeID)
    return ok and done == true
end

-- Picks `recipeID` in Daylight UI's window, as a click on its line would; in
-- DaylightMogul's through its select call when it has one. False when that window is
-- shut or its list lacks the recipe (another profession's list, not learned).
function Host.SelectRecipe(recipeID)
    local api = daylightView.api
    if api and type(api.SelectCraftRecipe) == "function" and Host.DaylightWindow() then
        return api.SelectCraftRecipe(recipeID) == true
    end
    if Host.MogulOwns() then return mogulSelect(recipeID) end
    return false
end

-- Daylight UI's window opened or switched profession: the guide redraws, and an Open
-- click waiting for this window selects its recipe in Daylight UI's list.
local function craftShown()
    if CP.Panel then CP.Panel.Changed() end
    if CP.Window then CP.Window.LandSoon("Daylight window") end
end

-- Daylight UI's window shut: the guide's craft buttons read Open again.
local function craftHidden()
    if CP.Panel then CP.Panel.Changed() end
end

-- Plugin.Start hands over `me` (API.For) and the API. Without Daylight UI's Craft events
-- nothing is registered. True when they were.
function Host.UseDaylight(me, api)
    if not (me and type(me.On) == "function") then return false end
    daylightView.me, daylightView.api = me, api
    local function traced(event, fn)
        return function(...)
            if CP.Window then CP.Window.Trace("Daylight %s %s", event, tostring((...))) end
            if CP.Look then CP.Look.Note("Daylight " .. event, (...)) end
            return fn(...)
        end
    end
    me.On("CraftShown", traced("CraftShown", craftShown))
    me.On("CraftProfessionChanged", traced("CraftProfessionChanged", craftShown))
    me.On("CraftHidden", traced("CraftHidden", craftHidden))

    -- A recipe picked in their list: the guide follows to its step. Just after an Open
    -- landed there, a pick their window made on its own goes back to ours.
    me.On("CraftRecipeSelected", function(recipeID)
        if CP.Window then CP.Window.DaylightSelected(recipeID) end
        if Host.DaylightWindow() and CP.GuideTab and CP.GuideTab.Follow then CP.GuideTab.Follow(recipeID) end
    end)
    return true
end
