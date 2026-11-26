-- Glowey's Recipes hand-offs (owner, 2026-11-26). A "Glowey's Recipes" group on ProfLost's
-- options page, shown only while Glowey's Recipes is loaded, has a switch for each job both
-- addons do: the leveling guide, the vendor Buy button and the item tooltip lines. On leaves
-- the job to Glowey's Recipes. Where its own switch already leaves that job to ProfLost, ours
-- greys and ProfLost keeps the job, so neither addon leaves it to the other.

local CP = ProfLost
local W, P, B, G = CP.Window, CP.Panel, CP.Buying, CP.Glowey
local LW = 165
local DUROTAR = 1411
local FINE_THREAD = 2321
local GROUP = "Glowey's Recipes"

local function scene(glowey, skill)
    MapWorld.begin({ zone = DUROTAR, level = 20, side = "Horde" })
    CraftWorld.begin({ professions = { [LW] = skill or 100 } })
    DaylightWorld.begin({ plugin = true })
    if glowey then GloweyWorld.begin(glowey) end
    World.set(CP.db, "hideInCombat", false)
    World.set(CP.db, "windowClosed", nil)
    World.set(W, "byHand", W.byHand)
    W.byHand = false
    World.onEnd(function()
        W.CancelPick()
        W.opened = false
        W.Update()
    end)
    W.Update()
end

local function group()
    for _, g in ipairs(CP.Plugin.Pages(CP.Settings.Daylight().API)[1].groups) do
        if g.label == GROUP then return g end
    end
end

local function row(id)
    for _, item in ipairs(group().items) do
        if item.key == id or item.label == id then return item end
    end
end

local function get(k) return CP.Settings.Current(k) end

local function hidden(item) return item.hidden ~= nil and item.hidden(get) == true end

local function shown() return P.frame:IsShown() == true end

-- The panel the options page lives on: Show records the page asked for.
local function optionsPanel()
    local panel = { pages = {} }
    function panel.Show(id) panel.pages[#panel.pages + 1] = id end
    World.set(DaylightWorld.state.addon, "OptionsPanel", panel)
    return panel
end

-- 1. The group -----------------------------------------------------------------------------

T.test("the group's rows show only while Glowey's Recipes is loaded", function()
    scene(nil)
    optionsPanel()
    local g = group()
    T.ok(g ~= nil, "a Glowey's Recipes group on the page")
    for _, item in ipairs(g.items) do
        T.ok(hidden(item), tostring(item.key or item.label) .. " is hidden without it")
    end
    GloweyWorld.begin({})
    for _, item in ipairs(g.items) do
        T.ok(not hidden(item), tostring(item.key or item.label) .. " shows with it")
    end
end)

T.test("three switches, off by default, each saying it leaves the job to Glowey's Recipes", function()
    for _, key in ipairs({ "gloweyGuide", "gloweyBuy", "gloweyTips" }) do
        local s = CP.Settings.Find(key)
        T.ok(s ~= nil, key .. " is a setting")
        T.eq(s.group, GROUP)
        T.eq(CP.DEFAULTS[key], false, key .. " starts off: ProfLost does the job")
        T.ok(s.desc:find("Glowey's Recipes", 1, true) ~= nil, key .. " names Glowey's Recipes")
    end
end)

-- 2. The leveling guide ----------------------------------------------------------------------

T.test("the guide hand-off keeps the guide window shut until it is opened by hand", function()
    scene({})
    T.ok(shown(), "the guide window shows before the hand-off")
    CP.Settings.Save("gloweyGuide", true)
    T.ok(G.Handed("guide"))
    T.ok(not shown(), "shut once the guide is left to Glowey's Recipes")
    T.ok(not CP.db.windowClosed, "the player's own closed choice is untouched")
    W.Toggle()
    T.ok(shown(), "the minimap button still opens it")
    CP.Settings.Save("gloweyGuide", false)
    T.ok(shown(), "still open with the hand-off off")
    W.Close()
    W.Open()
    CP.Settings.Save("gloweyGuide", true)
    T.ok(not shown(), "switching the hand-off on shuts a window opened earlier")
    CP.Settings.Save("gloweyGuide", false)
    T.ok(shown(), "back as before once the hand-off is off")
end)

T.test("the guide hand-off takes ProfLost's step marks off the profession window's recipe lines", function()
    scene({}, { rank = 100, max = 150 })
    CraftWorld.Open(LW)
    T.advance(0.3)
    local API = CP.Settings.Daylight().API
    local marked = 0
    for id, line in pairs(DaylightWorld.state.rows) do
        local bar = API.Attach(line).cpBar
        if CP.CraftRows.Marks()[id] and bar and bar:IsShown() then marked = marked + 1 end
    end
    T.ok(marked > 0, "the guide's steps are marked before the hand-off")
    CP.Settings.Save("gloweyGuide", true)
    for _, line in pairs(DaylightWorld.state.rows) do
        local bar = API.Attach(line).cpBar
        T.ok(not (bar and bar:IsShown()), "no mark while the guide is left to Glowey's Recipes")
    end
    CP.Settings.Save("gloweyGuide", false)
    local back = 0
    for id, line in pairs(DaylightWorld.state.rows) do
        local bar = API.Attach(line).cpBar
        if CP.CraftRows.Marks()[id] and bar and bar:IsShown() then back = back + 1 end
    end
    T.eq(back, marked, "the marks come back")
end)

T.test("Glowey's Recipes leaving its guide to ProfLost greys ours, and ProfLost keeps the guide", function()
    scene({ settings = { plGuide = true } })
    CP.Settings.Save("gloweyGuide", true)
    local r = row("gloweyGuide")
    T.eq(r.disabled(get), true, "greyed")
    T.eq(r.get(), false, "a greyed switch reads off")
    T.ok(not G.Handed("guide"), "not left to Glowey's Recipes")
    T.ok(shown(), "the guide window stays")
    GloweyWorld.Set("plGuide", false)
    T.eq(r.disabled(get), false, "live again once its switch is off")
    T.eq(r.get(), true, "the saved choice comes back")
    T.ok(not shown(), "and ProfLost leaves the guide to it at once")
    GloweyWorld.Set("plGuide", true)
    T.ok(shown(), "and takes it back at once")
end)

-- 3. The vendor Buy button -------------------------------------------------------------------

local function merchant(slots)
    World.patch("GetMerchantNumItems", function() return #slots end)
    World.patch("GetMerchantItemID", function(i) return slots[i] and slots[i][1] or nil end)
    World.patch("GetMerchantItemLink", function(i)
        return slots[i] and ("|cffffffff|Hitem:%d::::::::20:::::|h[x]|h|r"):format(slots[i][1])
    end)
    World.patch("C_MerchantFrame.GetItemInfo", function(i)
        local s = slots[i]
        return s and { price = s[2], stackCount = 1, numAvailable = -1, isPurchasable = true }
    end)
    World.patch("GetMerchantItemMaxStack", function() return 20 end)
    World.patch("GetMoney", function() return 100000000 end)
    World.set(B, "open", true)
    World.onEnd(function()
        B.open = false
        B.Changed()
    end)
end

local function atVendor(glowey)
    scene(glowey, { rank = 121, max = 150 })
    CraftWorld.Open(LW)
    CraftWorld.Close()
    World.set(CP.charDB, "guideMode", "one")
    W.Pick(LW)
    World.set(_G, "MerchantFrame", CreateFrame("Frame", nil, UIParent))
    merchant({ { FINE_THREAD, 100 } })
    T.fire("MERCHANT_SHOW")
    T.advance(1)
end

local function buyShown() return B.Button() ~= nil and B.Button():IsShown() == true end

T.test("the buy hand-off takes the Buy for guide button off the vendor window", function()
    atVendor({})
    T.ok(buyShown(), "the button shows before the hand-off")
    CP.Settings.Save("gloweyBuy", true)
    T.ok(not buyShown(), "gone at once")
    T.advance(1)
    T.ok(not buyShown(), "and stays gone while the vendor is open")
    CP.Settings.Save("gloweyBuy", false)
    T.ok(buyShown(), "back once the hand-off is off")
end)

T.test("Glowey's Recipes leaving its buy lists to ProfLost greys ours; its buy switch alone does not", function()
    atVendor({ settings = { plShop = true } })
    CP.Settings.Save("gloweyBuy", true)
    local r = row("gloweyBuy")
    T.eq(r.disabled(get), false, "its buy switch means nothing without its guide switch")
    T.ok(not buyShown())
    GloweyWorld.Set("plGuide", true)
    T.eq(r.disabled(get), true, "greyed once both are on")
    T.ok(buyShown(), "ProfLost's button is back at once")
end)

-- 4. Item tooltips ---------------------------------------------------------------------------

local function tooltipAdds()
    local tip = { AddLine = function() end, AddDoubleLine = function() end, Show = function() end }
    return CP.ItemTooltip.Add(tip, 2319)
end

T.test("the tooltip hand-off drops ProfLost's item tooltip lines unless Glowey's Recipes leaves them to it", function()
    scene({})
    World.set(CP.charDB, "gatherNeeds", { [LW] = { [2319] = 10 } })
    World.set(CP.db, "itemTooltip", true)
    T.ok(tooltipAdds(), "lines before the hand-off")
    CP.Settings.Save("gloweyTips", true)
    T.ok(not tooltipAdds(), "none once left to Glowey's Recipes")
    GloweyWorld.Set("plTips", true)
    T.ok(row("gloweyTips").disabled(get), "greyed while its switch leaves the lines to ProfLost")
    T.ok(tooltipAdds(), "ProfLost keeps them")
    GloweyWorld.Set("plTips", false)
    GloweyWorld.Set("tooltips", false)
    T.ok(row("gloweyTips").disabled(get), "greyed while its own tooltip lines are off")
    T.ok(tooltipAdds(), "so someone still says what the guides need")
end)

-- 5. Buttons, and Glowey's Recipes gone ------------------------------------------------------

T.test("Open runs Glowey's Recipes' /recipes, Settings shows its page, Put everything back turns all three off", function()
    scene({})
    local panel = optionsPanel()
    for _, key in ipairs({ "gloweyGuide", "gloweyBuy", "gloweyTips" }) do CP.Settings.Save(key, true) end
    row("Open Glowey's Recipes").func()
    T.eq(GloweyWorld.state.opened, 1, "its window toggled once")
    row("Glowey's Recipes settings").func()
    T.eq(panel.pages, { "DaylightRecipes.recipes" })
    local back = row("Put everything back")
    T.eq(back.confirm, true, "asks Click again first")
    back.func()
    for _, key in ipairs({ "gloweyGuide", "gloweyBuy", "gloweyTips" }) do
        T.eq(CP.Settings.Current(key), false, key .. " is off")
    end
    T.ok(shown(), "the guide window is back")
end)

T.test("the Open buttons hide when there is nothing to open", function()
    scene({ command = false })
    T.ok(hidden(row("Open Glowey's Recipes")), "no /recipes command")
    T.ok(hidden(row("Glowey's Recipes settings")), "no options panel")
    T.ok(not hidden(row("Put everything back")))
end)

T.test("switches left on with Glowey's Recipes gone: ProfLost does every job", function()
    scene(nil)
    for _, key in ipairs({ "gloweyGuide", "gloweyBuy", "gloweyTips" }) do CP.Settings.Save(key, true) end
    for _, job in ipairs({ "guide", "buy", "tooltip" }) do T.ok(not G.Handed(job), job .. " stays with ProfLost") end
    T.ok(shown(), "the guide window shows")
end)
