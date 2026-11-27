-- Glowey's Recipes hand-offs (owner, 2026-11-27). Glowey's Recipes' options page has six
-- switches, one per job both addons can do: on, Professionally Lost does it. ProfLost's
-- "Glowey's Recipes" group shows the same six rows with the same labels, and each row reads and
-- writes Glowey's Recipes' own saved switch, so a change on either page shows on the other.
-- ProfLost follows the switches for the three jobs it has (leveling guide, vendor Buy button,
-- item tooltip lines) once the player has answered Glowey's Recipes' first-load question.

local CP = ProfLost
local W, P, B, G = CP.Window, CP.Panel, CP.Buying, CP.Glowey
local LW = 165
local DUROTAR = 1411
local FINE_THREAD = 2321
local GROUP = "Glowey's Recipes"
local SCOPE = "DaylightRecipes"

-- Its six rows, in its order, with its labels (DaylightRecipes Core.lua's Professionally Lost group).
local ROWS = {
    { "guide", "plGuide", "Leveling guide" },
    { "buy", "plShop", "Buy lists" },
    { "trainer", "plTrainer", "Trainer panel" },
    { "tooltip", "plTips", "Guide line in item tooltips" },
    { "prices", "plPrices", "Scanned prices" },
    { "step", "plStep", "Light up its step" },
}

-- The owner's state: the question answered, every job with ProfLost.
local function ownerState()
    local t = {}
    for _, r in ipairs(ROWS) do t[r[2]] = true end
    return t
end

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

local function greyed(item) return item.disabled ~= nil and item.disabled(get) == true end

local function theirs(key) return DaylightWorld.state.settings[SCOPE] and DaylightWorld.state.settings[SCOPE][key] end

local function shown() return P.frame:IsShown() == true end

-- The panel the options page lives on: Show records the page Daylight UI would show, "home" for
-- a page Glowey's folded hub hides (Options/Panel.lua Show).
local function optionsPanel()
    local panel = { pages = {} }
    function panel.Show(id)
        if GloweyWorld.state and GloweyWorld.Hidden(id) then id = "home" end
        panel.pages[#panel.pages + 1] = id
    end
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

T.test("six switches with Glowey's Recipes' labels, in its order, then the three buttons", function()
    scene({})
    optionsPanel()
    local items = group().items
    for i, r in ipairs(ROWS) do
        local item = items[i]
        T.eq(item.type, "toggle", r[3] .. " is a switch")
        T.eq(item.label, r[3], "row " .. i .. " has its label")
        T.eq(item.key, nil, r[3] .. " keeps no value of ProfLost's own")
        T.ok(item.desc:find("Professionally Lost", 1, true) ~= nil, r[3] .. " says what on means")
    end
    T.eq(items[7].label, "Open Glowey's Recipes")
    T.eq(items[8].label, "Glowey's Recipes settings")
    T.eq(items[9].label, "Put everything back")
    T.eq(#items, 9)
    for _, key in ipairs({ "gloweyGuide", "gloweyBuy", "gloweyTips" }) do
        T.eq(CP.Settings.Find(key), nil, key .. ": no second switch of ProfLost's own")
    end
end)

-- 2. One state, on both pages ----------------------------------------------------------------

T.test("each row reads Glowey's Recipes' switch, and a change on its page shows on ours", function()
    scene({ asked = true })
    for _, r in ipairs(ROWS) do T.eq(row(r[3]).get(), false, r[3] .. " starts off, as its default") end
    for _, r in ipairs(ROWS) do
        GloweyWorld.Set(r[2], true)
        T.eq(row(r[3]).get(), true, r[3] .. " follows its page")
    end
    GloweyWorld.Set("plTips", false)
    T.eq(row("Guide line in item tooltips").get(), false, "and back")
end)

T.test("a change on our page writes Glowey's Recipes' own switch, through Daylight UI", function()
    scene({ asked = true })
    local heard = {}
    local h = CP.Settings.Daylight().API.On("SettingChanged", function(scope, path, value)
        if scope == SCOPE then heard[path] = value end
    end)
    World.onEnd(function() CP.Settings.Daylight().API.Off(h) end)
    for _, r in ipairs(ROWS) do
        local item = row(r[3])
        T.ok(item.set(true) ~= false, r[3] .. " takes the value")
        T.eq(theirs(r[2]), true, r[3] .. " writes " .. r[2])
        T.eq(heard[r[2]], true, r[3] .. ": Glowey's Recipes hears it")
        T.eq(item.get(), true)
    end
    row("Leveling guide").set(false)
    T.eq(theirs("plGuide"), false)
    T.eq(row("Leveling guide").default(), false, "its default, off")
end)

T.test("in the owner's state no row is greyed", function()
    scene({ asked = true, settings = ownerState() })
    for _, r in ipairs(ROWS) do
        T.ok(not greyed(row(r[3])), r[3] .. " is live")
        T.eq(row(r[3]).get(), true, r[3] .. " reads on")
    end
    for _, job in ipairs({ "guide", "buy", "tooltip" }) do T.ok(not G.Handed(job), job .. " stays with ProfLost") end
end)

T.test("only the rows that follow the guide grey, and only while the guide is Glowey's Recipes'", function()
    scene({ asked = true, settings = { plShop = true, plTrainer = true, plStep = true } })
    for _, label in ipairs({ "Buy lists", "Trainer panel", "Light up its step" }) do
        T.ok(greyed(row(label)), label .. " greys while Leveling guide is off")
        T.eq(row(label).get(), true, label .. " still shows its saved switch, as Glowey's Recipes' page does")
    end
    for _, label in ipairs({ "Leveling guide", "Guide line in item tooltips", "Scanned prices" }) do
        T.ok(not greyed(row(label)), label .. " never greys")
    end
    row("Leveling guide").set(true)
    for _, r in ipairs(ROWS) do T.ok(not greyed(row(r[3])), r[3] .. " live with the guide on") end
end)

T.test("until its first-load question is answered, ProfLost keeps every job", function()
    scene({})
    for _, job in ipairs({ "guide", "buy", "tooltip" }) do T.ok(not G.Handed(job), job .. " with ProfLost") end
    T.ok(shown(), "the guide window shows")
    GloweyWorld.Set("plTips", true)
    T.ok(G.Handed("guide"), "a switch turned on is an answer: the guide, still off, is Glowey's Recipes'")
    T.ok(not G.Handed("tooltip"))
end)

T.test("old ProfLost-side switches are dropped from the saved file", function()
    local db = CP.CarryOver({ gloweyGuide = true, gloweyBuy = false, gloweyTips = true, collect = true })
    T.eq(db.gloweyGuide, nil)
    T.eq(db.gloweyBuy, nil)
    T.eq(db.gloweyTips, nil)
    T.eq(db.collect, true, "other keys stay")
end)

-- 3. The leveling guide ----------------------------------------------------------------------

T.test("Leveling guide off keeps the guide window shut until it is opened by hand", function()
    scene({ asked = true, settings = ownerState() })
    T.ok(shown(), "the guide window shows while ProfLost does the guide")
    row("Leveling guide").set(false)
    T.ok(G.Handed("guide"))
    T.ok(not shown(), "shut once the guide is Glowey's Recipes'")
    T.ok(not CP.db.windowClosed, "the player's own closed choice is untouched")
    W.Toggle()
    T.ok(shown(), "the minimap button still opens it")
    row("Leveling guide").set(true)
    T.ok(shown(), "still open with the guide back")
    W.Close()
    W.Open()
    GloweyWorld.Set("plGuide", false)
    T.ok(not shown(), "its own page switching the guide over shuts a window opened earlier")
    GloweyWorld.Set("plGuide", true)
    T.ok(shown(), "and takes it back at once")
end)

T.test("Leveling guide off takes ProfLost's step marks off the profession window's recipe lines", function()
    scene({ asked = true, settings = ownerState() }, { rank = 100, max = 150 })
    CraftWorld.Open(LW)
    T.advance(0.3)
    local API = CP.Settings.Daylight().API
    local marked = 0
    for id, line in pairs(DaylightWorld.state.rows) do
        local bar = API.Attach(line).cpBar
        if CP.CraftRows.Marks()[id] and bar and bar:IsShown() then marked = marked + 1 end
    end
    T.ok(marked > 0, "the guide's steps are marked while ProfLost does the guide")
    row("Leveling guide").set(false)
    for _, line in pairs(DaylightWorld.state.rows) do
        local bar = API.Attach(line).cpBar
        T.ok(not (bar and bar:IsShown()), "no mark while the guide is Glowey's Recipes'")
    end
    row("Leveling guide").set(true)
    local back = 0
    for id, line in pairs(DaylightWorld.state.rows) do
        local bar = API.Attach(line).cpBar
        if CP.CraftRows.Marks()[id] and bar and bar:IsShown() then back = back + 1 end
    end
    T.eq(back, marked, "the marks come back")
end)

-- 4. The vendor Buy button -------------------------------------------------------------------

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
        B.watch:Hide()
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

T.test("Buy lists off takes the Buy for guide button off the vendor window", function()
    atVendor({ asked = true, settings = ownerState() })
    T.ok(buyShown(), "the button shows while ProfLost does the buying")
    row("Buy lists").set(false)
    T.ok(not buyShown(), "gone at once")
    T.advance(1)
    T.ok(not buyShown(), "and stays gone while the vendor is open")
    row("Buy lists").set(true)
    T.ok(buyShown(), "back once Buy lists is on")
    GloweyWorld.Set("plGuide", false)
    T.ok(not buyShown(), "Buy lists counts only while ProfLost does the guide")
end)

-- 5. Item tooltips ---------------------------------------------------------------------------

local function tooltipAdds()
    local tip = { AddLine = function() end, AddDoubleLine = function() end, Show = function() end }
    return CP.ItemTooltip.Add(tip, 2319)
end

T.test("Guide line in item tooltips off drops ProfLost's lines, unless Glowey's Recipes shows no tooltips", function()
    scene({ asked = true, settings = ownerState() })
    World.set(CP.charDB, "gatherNeeds", { [LW] = { [2319] = 10 } })
    World.set(CP.db, "itemTooltip", true)
    T.ok(tooltipAdds(), "lines while ProfLost does them")
    row("Guide line in item tooltips").set(false)
    T.ok(not tooltipAdds(), "none once they are Glowey's Recipes'")
    GloweyWorld.Set("tooltips", false)
    T.ok(not greyed(row("Guide line in item tooltips")), "not greyed")
    T.ok(tooltipAdds(), "with its item tooltips off, ProfLost still says what the guides need")
end)

-- 6. Buttons, and Glowey's Recipes gone ------------------------------------------------------

T.test("the settings button opens Glowey's Recipes' own page while Glowey's hub folds it", function()
    scene({ hub = true })
    local panel = optionsPanel()
    row("Glowey's Recipes settings").func()
    T.eq(panel.pages, { "DaylightRecipes.recipes" }, "its page, not Daylight UI's home")
end)

T.test("the settings button opens the same page without the hub", function()
    scene({})
    local panel = optionsPanel()
    row("Glowey's Recipes settings").func()
    T.eq(panel.pages, { "DaylightRecipes.recipes" })
end)

T.test("Open runs Glowey's Recipes' /recipes; Put everything back gives all six to ProfLost", function()
    scene({ asked = true })
    row("Open Glowey's Recipes").func()
    T.eq(GloweyWorld.state.opened, 1, "its window toggled once")
    T.ok(not shown(), "the guide is Glowey's Recipes' before")
    local back = row("Put everything back")
    T.eq(back.confirm, true, "asks Click again first")
    back.func()
    for _, r in ipairs(ROWS) do T.eq(theirs(r[2]), true, r[2] .. " is on") end
    T.ok(shown(), "the guide window is back")
end)

T.test("the Open buttons hide when there is nothing to open", function()
    scene({ command = false })
    T.ok(hidden(row("Open Glowey's Recipes")), "no /recipes command")
    T.ok(hidden(row("Glowey's Recipes settings")), "no options panel")
    T.ok(not hidden(row("Put everything back")))
end)

T.test("with Glowey's Recipes gone, ProfLost does every job", function()
    scene(nil)
    World.set(_G, "DaylightRecipesDB", { proflost = { asked = true } })
    for _, job in ipairs({ "guide", "buy", "tooltip" }) do T.ok(not G.Handed(job), job .. " stays with ProfLost") end
    T.ok(shown(), "the guide window shows")
end)
