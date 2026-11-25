-- Round 11, the control-overlap polish: the route menu's ticks reach the gathering panel,
-- the route pin's default and its off state in the menu, the options page's wording and
-- groups, one click map for every launcher, the detached panel's own padlock, the attach
-- flip keeping closed windows closed, the split combat setting, the View switch, the window scale, the guide following the open window, the learn and
-- Craft all buttons, and Cancel on the vendor's materials confirmation.

local CP = ProfLost
local W, P, GP, GL, G, S = CP.Window, CP.Panel, CP.GatherPanel, CP.GatherList, CP.Gather, CP.Settings
local LW, TAILOR, MINING, SKINNING = 165, 197, 186, 393
local HERB = 182
local DUROTAR = 1411
local GUIDE_SPOT = { "TOPLEFT", "BOTTOMLEFT", 100, 800 }

-- A free guide window at GUIDE_SPOT with three professions, its panel attached and open.
local function scene(profs)
    MapWorld.begin({ zone = DUROTAR, level = 20, side = "Horde" })
    CraftWorld.begin({ professions = profs or { [LW] = 100, [TAILOR] = 60, [MINING] = 30 } })
    for key, v in pairs({ hideInCombat = true, gatherHideInCombat = true, windowClosed = false,
                          windowLocked = false, gatherLocked = false, gatherOpen = true,
                          gatherAttached = true, gatherPanelClosed = false, gatherSide = "right" }) do
        World.set(CP.db, key, v or nil)
    end
    World.set(CP.db, "gatherHideCarried", nil)
    World.set(CP.db, "gatherPoint", nil)
    World.set(CP.db, "gatherSize", nil)
    World.set(CP.db, "guideScale", nil)
    World.set(CP.db, "gatherScale", nil)
    World.set(CP.db, "windowPoint", { unpack(GUIDE_SPOT) })
    World.set(CP.charDB, "guideMode", "one")
    World.set(W.managed, "mover", false)
    World.set(GP.managed, "mover", false)
    World.set(GP.anchor, "GetLeft", function() return 420 end)
    World.set(GP.anchor, "GetTop", function() return 800 end)
    World.onEnd(function()
        CP.db.gatherAttached = true
        GP.ModeChanged()
        T.fire("PLAYER_REGEN_ENABLED")
        W.opened, GP.opened = false, false
        GP.anchor:ClearAllPoints()
        W.anchor:SetScale(1)
        W.Update()
    end)
    GP.anchor:ClearAllPoints()
    W.PlaceAnchor()
    W.Update()
    GP.Layout()
end

local function click(b, mouse) b:GetScript("OnClick")(b, mouse or "LeftButton") end
local function guideShown() return P.frame:IsShown() end
local function gatherShown() return GP.sheet:IsVisible() end

local function printedSince(n)
    local out = {}
    for i = n + 1, #T.prints() do out[#out + 1] = tostring(T.prints()[i]) end
    return table.concat(out, "\n")
end

-- 1. The Farm menu's ticks reach the gathering panel in Farm only -------------------------

local COOKING = 185
local MOB = { kind = "mob", entry = 1, name = "Kobold", minLevel = 5, maxLevel = 6, chance = 30 }
local function rowsFixture()
    return {
        { itemID = 2447, prof = HERB, sources = {   -- Peacebloom: its node, and a creature drop
            { kind = "node", entry = 9, name = "Peacebloom", chance = 100, prof = HERB, skill = 1 }, MOB } },
        { itemID = 765, prof = HERB, sources = {    -- Silverleaf: its node only
            { kind = "node", entry = 8, name = "Silverleaf", chance = 100, prof = HERB, skill = 1 } } },
        { itemID = 2318, prof = SKINNING, sources = {  -- Light Leather: skinning only
            { kind = "mob", entry = 2, name = "Boar", minLevel = 5, maxLevel = 6, chance = 60, prof = SKINNING } } },
        { itemID = 2672, prof = COOKING, sources = {   -- Stringy Wolf Meat: a creature, and (here) a node
            { kind = "node", entry = 7, name = "Peacebloom", chance = 100, prof = HERB, skill = 1 }, MOB } },
        { itemID = 769, prof = COOKING, sources = { MOB } },  -- Chunk of Boar Meat: untouched
    }
end

T.test("in Farm an unticked herb, ore or leather leaves the rows, and a row's grind spots skip it", function()
    World.set(CP.db, "routeMode", "farm")
    World.set(CP.db, "routeSkip", { Silverleaf = true, Peacebloom = true })
    World.set(CP.db, "skinSkip", { [2318] = true })
    local rows = rowsFixture()
    local kept = GL.Ticked(rows)
    local by = {}
    for _, r in ipairs(kept) do by[r.itemID] = r end
    T.eq(by[765], nil, "Silverleaf, its only node unticked: gone")
    T.eq(by[2447], nil, "Peacebloom unticked: its Herbalism row goes, creature drop or not")
    T.eq(by[2318], nil, "Light Leather unticked: gone")
    T.ok(by[2672] ~= nil, "another profession's row keeps its creature source")
    T.eq(#by[2672].sources, 1)
    T.eq(by[2672].sources[1].kind, "mob", "the unticked node is gone, so its grind spots and pins skip it")
    T.eq(by[2672].prof, COOKING, "the copy reads through to the row")
    T.eq(#rows[4].sources, 2, "the cached row stays whole")
    T.ok(by[769] == rows[5], "an untouched row is the row itself")

    CP.db.routeMode = nil
    T.eq(#GL.Ticked(rows), 5, "Follow the guide: every row, Farm's ticks or not")
    for i, r in ipairs(GL.Ticked(rows)) do T.ok(r == rows[i], "row " .. r.itemID .. " whole") end
    CP.db.routeMode = "farm"
    CP.db.routeSkip, CP.db.skinSkip = nil, nil
    T.eq(#GL.Ticked(rows), 5, "all ticked: every row")
end)

T.test("Follow the guide draws every row the guides need, Farm's ticks or not", function()
    scene({ [HERB] = 50, [SKINNING] = 50 })
    World.set(CP.db, "routeMode", nil)
    World.set(CP.db, "routeSkip", { Silverleaf = true })
    World.set(CP.db, "skinSkip", { [2318] = true })
    World.set(G, "Rows", function()
        local rows = rowsFixture()
        for _, r in ipairs(rows) do r.need, r.have, r.name = 10, 0, "item " .. r.itemID end
        return rows
    end)
    GL.Refresh()
    local items = {}
    for _, line in ipairs((GL.Drawn())) do
        if line.kind == "item" then items[line.row.itemID] = line end
    end
    T.ok(items[2447] ~= nil, "Peacebloom drawn")
    T.ok(items[765] ~= nil, "Silverleaf drawn, unticked in Farm")
    T.ok(items[2318] ~= nil, "Light Leather drawn, unticked in Farm")
end)

-- 2 and 3. The route pin's default, and the menu while it is off --------------------------

T.test("the route pin is on for a player who never set it; off is saved as false", function()
    T.eq(CP.DEFAULTS.route, true, "on by default")
    World.set(CP.db, "route", nil)
    T.ok(GL.RouteOn(), "never set: on")
    local r = GL.head.route
    click(r)
    T.eq(CP.db.route, false, "off is saved")
    T.ok(not GL.RouteOn())
    click(r)
    T.eq(CP.db.route, true)
end)

-- The route menu for `skills`, its entries recorded with whether each was greyed.
local function routeMenu(skills)
    local m = { titles = {}, entries = {} }
    local root = {}
    local function entry(kind, text, data)
        local e = { kind = kind, text = text, data = data, enabled = true }
        function e:SetResponse(v) self.response = v end
        function e:SetEnabled(on) self.enabled = on end
        m.entries[#m.entries + 1] = e
        return e
    end
    -- The panel's own entries (profession filter) sit below the route's and are never greyed.
    local function apart() return { SetResponse = function() end, SetEnabled = function() end } end
    function root.CreateTitle(_, text)
        if text == GL.SHOW_HEADER then return apart() end
        m.titles[#m.titles + 1] = text
        return entry("title", text)
    end
    function root.CreateRadio(_, text, _, _, data)
        if type(data) ~= "string" then return apart() end
        return entry("radio", text, data)
    end
    function root.CreateCheckbox(_, text, _, _, data) return entry("check", text, data) end
    function root.CreateButton(_, text) return entry("button", text) end
    World.patch("MenuUtil.CreateContextMenu", function(owner, gen) gen(owner, root) end)
    World.set(_G, "MenuResponse", { Open = 1, Refresh = 2, Close = 3, CloseAll = 4 })
    World.set(G, "Skills", function() return skills end)
    World.set(G, "PlayerZone", function() return DUROTAR end)
    GL.RouteMenu(UIParent)
    return m
end

T.test("route off: the menu's top line says so and every other entry is greyed", function()
    MapWorld.begin({ zone = DUROTAR, level = 20, side = "Horde" })
    World.set(CP.db, "route", false)
    World.set(CP.db, "routeMode", "farm")
    local m = routeMenu({ [MINING] = 100, [HERB] = 100 })
    T.eq(m.titles[1], GL.ROUTE_OFF)
    T.eq(GL.ROUTE_OFF, "Route is off: click the pin to show it")
    local checks, greyed = 0, 0
    for i = 2, #m.entries do
        local e = m.entries[i]
        if e.kind == "check" then checks = checks + 1 end
        if not e.enabled then greyed = greyed + 1 end
    end
    T.ok(checks > 0, "herbs and ore listed")
    T.eq(greyed, #m.entries - 1, "every entry below the top line greyed")
    T.ok(m.entries[1].enabled, "the top line itself isn't")

    CP.db.route = true
    m = routeMenu({ [MINING] = 100, [HERB] = 100 })
    T.ok(m.titles[1]:find("^Gathering route") ~= nil, m.titles[1])
    for _, e in ipairs(m.entries) do T.ok(e.enabled, e.text .. " enabled while the route is on") end
end)

T.test("route off greys Follow the guide's entries too, herbs, ore and leather alike", function()
    MapWorld.begin({ zone = DUROTAR, level = 20, side = "Horde" })
    World.set(CP.db, "route", false)
    World.set(CP.db, "routeMode", nil)
    for _, skills in ipairs({ { [HERB] = 50 }, { [MINING] = 50 }, { [SKINNING] = 50 } }) do
        local m = routeMenu(skills)
        T.eq(m.titles[1], GL.ROUTE_OFF)
        for i = 2, #m.entries do T.ok(not m.entries[i].enabled, m.entries[i].text .. " greyed") end
    end
end)

T.test("the tick section has a dim 'Applies in every zone' header", function()
    MapWorld.begin({ zone = DUROTAR, level = 20, side = "Horde" })
    World.set(CP.db, "route", true)
    World.set(CP.db, "routeMode", "farm")
    local m = routeMenu({ [MINING] = 100 })
    local header, mining
    for i, t in ipairs(m.titles) do
        if t:find(GL.TICKS_HEADER, 1, true) then header = i end
        if t == "Mining" then mining = i end
    end
    T.eq(GL.TICKS_HEADER, "Picks are kept for other zones")
    T.ok(header ~= nil and mining ~= nil and header < mining, "above the ticks")
    T.ok(m.titles[header]:find("^|cff%x%x%x%x%x%x") ~= nil, "in the dim ink")
end)

-- 4, 6, 10, 15, 20, 21, 23. The options page ---------------------------------------------

T.test("the options page: no reset buttons, each side setting in its window's group, new wording", function()
    for _, s in ipairs(S.LIST) do
        T.ok(not (s.label or ""):find("^Show every"), "no reset on the options page: " .. tostring(s.label))
    end
    local side = S.Find("gatherSide")
    T.eq(S.Find("dockSide"), nil, "no guide window side: it never docks")
    T.eq(side.label, "Side when attached")
    T.eq(side.group, "Gathering window")
    T.eq(side.values, { left = "Left", right = "Right" })
    T.eq(CP.DEFAULTS.gatherSide, "right")
    T.eq(S.Find("vendorAlerts").label, "Pattern vendors")
    T.eq(S.Find("hideInCombat").label, "Hide in combat")
    T.eq(S.Find("hideInCombat").group, "Guide window")
    T.eq(S.Find("gatherHideInCombat").label, "Hide in combat")
    T.eq(S.Find("gatherHideInCombat").group, "Gathering window")
    T.eq(S.Find("minimapButton").label, "Minimap button")
    T.eq(CP.DEFAULTS.minimapButton, true)
end)

T.test("Fish for Cooking greys while Gather it yourself is off, and counts only while it is on", function()
    local s = S.Find("fishCook")
    T.ok(s.desc:find("only while Gather it yourself is on", 1, true) ~= nil, s.desc)
    T.ok(s.desc:find("Cooking guide plans fish recipes", 1, true) ~= nil, s.desc)
    local collect
    local function get(key) if key == "collect" then return collect end end
    collect = false
    T.eq(s.disabled(get), true, "collect off: greyed")
    collect = true
    T.eq(s.disabled(get), false, "collect on: live")
    local row
    for _, g in ipairs(CP.Plugin.Pages()[1].groups) do
        for _, item in ipairs(g.items) do if item.key == "fishCook" then row = item end end
    end
    T.eq(row.disabled, s.disabled, "the options row carries it")
    World.set(CP.db, "fishCook", true)
    World.set(CP.db, "collect", false)
    T.eq(S.FishCook(), false, "off while Gather it yourself is off")
    CP.db.collect = true
    T.eq(S.FishCook(), true)
end)

T.test("Daylight UI's Fish for Cooking row dims while collect is off", function()
    DaylightWorld.begin({ plugin = true, settings = { ProfLost = { collect = false } } })
    local mod = DaylightWorld.state.registered.ProfLost
    local row
    for _, g in ipairs(mod.options.pages[1].groups) do
        for _, item in ipairs(g.items) do if item.key == "fishCook" then row = item end end
    end
    local function get(key) return DaylightWorld.state.settings.ProfLost[key] end
    T.eq(row.disabled(get), true)
    DaylightWorld.SetSetting("ProfLost", "collect", true)
    T.eq(row.disabled(get), false)
end)

-- 5. Shift-click in Daylight UI's profession window -------------------------------------------

T.test("with Daylight UI's profession window open, Shift-click and /proflost gather slide the attached panel", function()
    scene()
    DaylightWorld.begin({ plugin = true, craftWindow = true })
    CraftWorld.Open(LW)
    T.advance(0.5)
    T.ok(CP.Host.DaylightWindow(), "Daylight UI's window is up")
    CP.db.gatherOpen = false
    GP.Layout()
    SlashCmdList.PROFLOST("gather")
    T.advance(0.5)
    T.ok(GP.Showing(), "/proflost gather slides it out")
    World.set(_G, "IsShiftKeyDown", function() return true end)
    CP.Launcher.minimapObject.OnClick(nil, "LeftButton")
    T.advance(0.5)
    T.ok(not GP.Showing(), "Shift-click slides it back")
    CraftWorld.Close()
end)

-- 6. The attached panel's side --------------------------------------------------------------

T.test("the attached panel's side is the setting's, right by default", function()
    World.set(CP.db, "gatherSide", nil)
    T.eq(GP.Side(), "right", "no side saved yet: the default")
    CP.db.gatherSide = "left"
    T.eq(GP.Side(), "left", "a picked side wins")
end)

-- 12. The detached panel's padlock --------------------------------------------------------

T.test("an old save's shut guide padlock shuts the new panel padlock too, once", function()
    T.eq(CP.CarryOver({ windowLocked = true }).gatherLocked, true)
    T.eq(CP.CarryOver({}).gatherLocked, false)
    T.eq(CP.CarryOver({ windowLocked = true, gatherLocked = false }).gatherLocked, false, "a set padlock stays")
end)

-- 13. The attach flip keeps closed windows closed ---------------------------------------------

T.test("detaching an open panel shows it; attaching a closed detached panel brings it in folded", function()
    scene()
    CP.Settings.Set("gatherAttached", false)
    T.ok(guideShown() and gatherShown(), "both were open: both stay")
    GP.Close()
    CP.Settings.Set("gatherAttached", true)
    T.ok(guideShown(), "the guide stays")
    T.eq(CP.db.gatherOpen, false, "the closed panel comes in folded")
    T.ok(not GP.Showing())
end)

-- 15. Hide in combat, one per window ---------------------------------------------------------

T.test("the old Hide in combat carries into both, and Daylight UI's copy of it too", function()
    local db = CP.CarryOver({ hideInCombat = false })
    T.eq(db.gatherHideInCombat, false, "the panel takes the old value")
    T.eq(db.gatherHideCarried, true)
    T.eq(CP.CarryOver({}).gatherHideInCombat, true, "a new player: on")

    -- Daylight UI's profile holds the old value for the guide and the default for the panel.
    local stored = { hideInCombat = false }
    DaylightWorld.KeepSettings()
    World.set(CP.db, "gatherHideCarried", true)
    World.set(CP.db, "hideInCombatCarried", nil)
    local API = { GetSetting = function(_, key) if stored[key] ~= nil then return stored[key] end return CP.DEFAULTS[key] end }
    CP.Plugin.Sync(API)
    T.eq(CP.db.hideInCombat, false)
    T.eq(CP.db.gatherHideInCombat, false, "carried: the panel follows the guide's old value")
    S.Set("gatherHideInCombat", true)
    T.eq(CP.db.gatherHideCarried, nil, "the player's own pick ends the carry")
    stored.gatherHideInCombat = true
    CP.Plugin.Sync(API)
    T.eq(CP.db.gatherHideInCombat, true, "and Daylight UI's value is used from then on")
end)

-- 16. The View switch ------------------------------------------------------------------------

T.test("the View switch lights the current view's word and greys the other beside it", function()
    local function ink(c)
        return ("|cff%02x%02x%02x"):format(math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5),
            math.floor(c[3] * 255 + 0.5))
    end
    local lit, grey = ink(CP.Style.color.title), ink(CP.Style.color.muted)
    T.eq(W.ViewLabel("one"), lit .. "Single|r  " .. grey .. "All|r")
    T.eq(W.ViewLabel("all"), grey .. "Single|r  " .. lit .. "All|r")
    scene()
    W.SetMode("one")
    T.eq(W.switchButton.label:GetText(), W.ViewLabel("one"))
    W.SetMode("all")
    T.eq(W.switchButton.label:GetText(), W.ViewLabel("all"))
end)

-- 21. The guide window scale ----------------------------------------------------------------------

local function scaleRow()
    for _, s in ipairs(S.LIST) do if s.label == "Guide window scale" then return s end end
end

T.test("Guide window scale without Daylight UI: saved and set on the window's anchor", function()
    scene()
    local s = scaleRow()
    T.ok(s ~= nil and s.group == "Guide window" and s.kind == "slider", "in the Guide window group")
    T.eq({ s.min, s.max, s.step }, { 0.5, 2, 0.05 }, "the mover's range and step")
    -- The harness keeps no frame scale: the anchor's SetScale is watched instead.
    local set
    World.set(W.anchor, "SetScale", function(_, v) set = v end)
    T.eq(s.get(), 1)
    s.set(1.25)
    T.eq(CP.db.guideScale, 1.25)
    T.eq(set, 1.25, "the anchor takes it")
    T.eq(s.get(), 1.25)
    set = nil
    W.PlaceAnchor()
    T.eq(set, 1.25, "a reload puts it back")
    s.set(1.3)
    T.eq(CP.db.guideScale, 1.3, "snapped to the 0.05 step")
    s.set(1)
    T.eq(CP.db.guideScale, nil, "1 saves nothing")
end)

T.test("Guide window scale with Daylight UI is its mover's piece scale, the value its wheel sets", function()
    scene()
    DaylightWorld.begin({ plugin = true })
    World.set(W.managed, "mover", true)
    local scales = DaylightWorld.state.frameScales
    local s = scaleRow()
    s.set(1.5)
    T.eq(scales[W.MOVER_KEY], 1.5, "stored where /dui unlock's wheel keeps it")
    T.eq(CP.db.guideScale, nil, "not in ProfLost's own save")
    scales[W.MOVER_KEY] = 0.75   -- the wheel over the handle
    T.eq(s.get(), 0.75, "the slider reads the wheel's value")
    local row
    for _, g in ipairs(CP.Plugin.Pages()[1].groups) do
        for _, item in ipairs(g.items) do if item.label == "Guide window scale" then row = item end end
    end
    T.ok(row and row.get == s.get and row.set == s.set and row.default() == 1, "the options row reads and writes it")
end)

-- 22. One Prof follows the open window, gathering professions too --------------------------------

T.test("One Prof follows the open window for Mining and Skinning as for crafting professions", function()
    scene({ [LW] = 100, [MINING] = 30, [SKINNING] = 40 })
    W.Pick(LW)
    local asked = #CraftWorld.Asked()
    for _, id in ipairs({ MINING, SKINNING, LW }) do
        CraftWorld.Open(id)
        T.advance(0.1)
        T.eq(W.ChosenID(), id, CraftWorld.NAMES[id] .. ": the guide shows it")
        T.eq(CP.charDB.guideProf, id, CraftWorld.NAMES[id] .. ": chosen")
        CraftWorld.Close()
        T.advance(1)
    end
    T.eq(#CraftWorld.Asked(), asked, "never an OpenTradeSkill outside a click")
end)

-- 17 and 18. The learn button and Craft all ---------------------------------------------------

T.test("an unlearned recipe's button reads Go to trainer, or Go to vendor for a pattern", function()
    T.eq(CP.GuideTab.LearnLabel({ src = "trainer" }), "Go to trainer")
    T.eq(CP.GuideTab.LearnLabel({ src = "vendor" }), "Go to vendor")
    T.eq(CP.GuideTab.LearnLabel({ src = "reputation" }), "Go to vendor")
    T.eq(CP.GuideTab.LearnLabel({ src = "drop" }), "Learn", "nowhere to go: Learn")
end)

T.test("Craft all says it crafts what the step needs; greyed, what is missing", function()
    local reagents = { { itemID = 4234, name = "Heavy Leather", need = 2, have = 6 },
                       { itemID = 2321, name = "Fine Thread", need = 1, have = 6 } }
    T.eq(CP.GuideTab.CraftAllTip(6, true, reagents),
        "Crafts 6, what this step still needs. Not every craft your materials allow.")
    T.eq(CP.GuideTab.MissingText(reagents, 6), "Need 6 more Heavy Leather")
    T.eq(CP.GuideTab.CraftAllTip(6, false, reagents), "Need 6 more Heavy Leather")
    reagents[2].have = 4
    T.eq(CP.GuideTab.MissingText(reagents, 6), "Need 6 more Heavy Leather, 2 more Fine Thread")
    T.eq(CP.GuideTab.MissingText(reagents, 1), nil, "enough for one: nothing missing")
end)

T.test("the step card's Craft all carries its tooltip, on or greyed", function()
    scene({ [LW] = 1 })
    CraftWorld.Open(LW)
    T.advance(0.5)
    P.tabs.guide.button:GetScript("OnClick")()
    local d = CP.GuideTab.ui.details
    local b = d.craftAll
    T.ok(b:IsShown(), "Craft all shows")
    T.ok(not CP.Style.IsOn(b), "empty bags: greyed")
    T.ok(tostring(b.tip):find("^Need %d+ more ") ~= nil, "says what's missing: " .. tostring(b.tip))
    CraftWorld.Close()
end)

-- 19. Cancel on the materials confirmation -------------------------------------------------------

T.test("cancelling the materials confirmation still shows the patterns confirmation", function()
    local B = CP.Buying
    World.set(B, "open", true)
    local after = 0
    B.Confirm({}, 0, "materials", function() after = after + 1 end)
    local f = B.popup
    T.ok(f:IsShown())
    click(f.cancel)
    T.eq(after, 1, "the patterns' confirmation runs after a Cancel")
    T.ok(not f:IsShown() or f.kind ~= "materials", "the materials popup is gone")
    B.Confirm({}, 0, "patterns")
    click(f.cancel)
    T.eq(after, 1, "Skip on the patterns ends it")
    f:Hide()
end)

-- 14. One click map for every launcher -----------------------------------------------------------

T.test("the data text, the minimap button and the compartment take the same clicks", function()
    local calls = {}
    World.set(W, "Toggle", function() calls[#calls + 1] = "guide" end)
    World.set(GP, "ToggleShown", function() calls[#calls + 1] = "gather" end)
    World.set(P, "OpenSettings", function() calls[#calls + 1] = "settings" end)
    local shift = false
    World.set(_G, "IsShiftKeyDown", function() return shift end)
    local launchers = {
        function(b) CP.Launcher.object.OnClick(nil, b) end,
        function(b) CP.Launcher.minimapObject.OnClick(nil, b) end,
        function(b) ProfLost_Open("ProfLost", b) end,
    }
    for _, press in ipairs(launchers) do
        calls = {}
        press("LeftButton")
        shift = true
        press("LeftButton")
        shift = false
        press("RightButton")
        T.eq(calls, { "guide", "gather", "settings" })
    end
end)

-- Labels ------------------------------------------------------------------------------------

T.test("the welcome names the real settings route, and /proflost settings opens them", function()
    T.ok(CP.WELCOME_SETTINGS:find("/proflost settings", 1, true) ~= nil, CP.WELCOME_SETTINGS)
    local opened = 0
    World.set(P, "OpenSettings", function() opened = opened + 1 end)
    SlashCmdList.PROFLOST("settings")
    T.eq(opened, 1)
end)
