-- Available Skill Ups rows at Leatherworking 165 with Daylight UI's window (owner, 2026-11-25):
-- each row names its recipe however long its buy list, a row that needs vendor goods says so
-- and crafts only what the bags hold them for, and each row's button acts on its own recipe.

local CP = ProfLost
local GT = CP.GuideTab
local W = CP.Window
local LW = 165
local DUROTAR = 1411
local SKILL = 165
local HEAVY_LEATHER, MEDIUM_LEATHER = 4234, 2319
local DUSKY_BRACERS, BLACK_DYE, SILKEN_THREAD = 9201, 2325, 4291
local FINE_THREAD, GREEN_DYE = 2321, 2605
local SPARE = 40
local WIDE = 640

local function known()
    local out = {}
    for id, r in pairs(CP.Guides[LW].recipes) do
        if (r.src == "trainer" or r.src == "auto") and (r.learn or 1) <= SKILL then out[#out + 1] = id end
    end
    return out
end

-- Spare Heavy and Medium Leather and no vendor goods: Dusky Bracers and one more row list.
local function scene()
    Visual.begin()
    MapWorld.begin({ zone = DUROTAR, level = 30, side = "Horde" })
    DaylightWorld.begin({ plugin = true })
    CraftWorld.begin({ professions = { [LW] = { rank = SKILL, max = 225, known = known() } }, bags = {} })
    World.set(CP.db, "collect", false)
    World.set(CP.db, "hideInCombat", false)
    World.set(CP.charDB, "guideMode", "one")
    World.set(CP.db, "windowPoint", CP.db.windowPoint)
    World.onEnd(function()
        W.CancelPick()
        CP.Crafting.Stop()
    end)
    CraftWorld.Open(LW)
    T.advance(1)
    CP.Panel.frame:Show()
    CP.Panel.tabs.guide.button:GetScript("OnClick")()
    T.advance(1)
    local needs = CP.Gather.Needs()
    CraftWorld.SetBag(HEAVY_LEATHER, (needs[HEAVY_LEATHER] or 0) + SPARE)
    CraftWorld.SetBag(MEDIUM_LEATHER, (needs[MEDIUM_LEATHER] or 0) + SPARE)
    T.advance(1)
end

local function shownRows()
    local out = {}
    for _, r in ipairs(GT.ui.impromptu.rows) do
        if r:IsShown() then out[#out + 1] = r end
    end
    return out
end

local function rowOf(spell)
    for _, r in ipairs(shownRows()) do
        if r.item.guideID == spell then return r end
    end
end

-- The window at WIDE px, at the screen's left so the width fits.
local function wide()
    for _, key in ipairs({ "windowWidth", "windowLocked", "windowPoint", "guideSteps" }) do World.set(CP.db, key, CP.db[key]) end
    local point = CP.db.windowPoint
    World.onEnd(function()
        CP.db.windowPoint = point
        W.PlaceAnchor()
    end)
    CP.db.windowLocked = false
    CP.db.windowPoint = { "TOPLEFT", "BOTTOMLEFT", 100, 1000 }
    W.PlaceAnchor()
    W.Resize(WIDE, CP.Panel.frame:GetHeight())
    T.advance(1)
end

local function lastCast()
    local casts = CraftWorld.state.casts or {}
    local c = casts[#casts]
    return c and (c.id or c[1]), #casts
end

T.test("a row names its recipe beside a long buy list", function()
    scene()
    local rows = shownRows()
    T.ok(#rows >= 2, "two rows list")
    T.ok(rowOf(DUSKY_BRACERS) ~= nil, "Dusky Bracers lists")
    for _, r in ipairs(rows) do
        local name = r.item.name
        T.eq(r.name:GetText(), name, "the row's name text")
        local w = (r.name:GetRight() or 0) - (r.name:GetLeft() or 0)
        local want = math.min(CP.Style.Measure(name, "body"), GT.IMPROMPTU_NAME_MIN or 110)
        T.ok(w >= want - 1, ("%s keeps %d px for its name (has %d)"):format(name, want, w))
        T.ok(r.info:GetRight() <= r.craft:GetLeft() + 0.5, name .. ": the info ends before the button")
        local text = r.info:GetText() or ""
        T.ok(text:find(("x%d"):format(r.item.crafts), 1, true) == 1, name .. ": the count still shows: " .. text)
        T.ok(text:find("pts", 1, true) ~= nil, name .. ": the points still show: " .. text)
    end

    -- A wider window gives the buy list room again.
    wide()
    local r = rowOf(DUSKY_BRACERS)
    local text = r and r.info:GetText() or ""
    T.ok(text:find(("buy %d Black Dye"):format(r and r.item.crafts or 0), 1, true) ~= nil,
        "wide, the row says what to buy: " .. text)
    T.ok(r and (r.name:GetRight() or 0) - (r.name:GetLeft() or 0) >= CP.Style.Measure(r.item.name, "body") - 1,
        "and the name shows whole")
    Visual.Check("impromptu rows with buy lists")
end)

T.test("a long buy list is cut with an ellipsis; the count and points stay", function()
    local item = { name = "Dusky Bracers", crafts = 2, points = 2,
                   buy = { { count = 2, name = "Black Dye" }, { count = 4, name = "Silken Thread" } } }
    T.eq(CP.Impromptu.Info(item), "x2  ·  ~2 pts  ·  buy 2 Black Dye  ·  buy 4 Silken Thread")
    local room = #"x2  ·  ~2 pts  ·  buy 2 Black"
    local cut = CP.Impromptu.Info(item, false, function(text) return #text <= room end)
    T.ok(#cut <= room, "fits: " .. cut)
    T.ok(cut:find("x2  ·  ~2 pts  ·  buy 2", 1, true) == 1 and cut:sub(-3) == "…", "cut at the end: " .. cut)
    local least = "x2  ·  ~2 pts  ·  buy…"
    T.eq(CP.Impromptu.Info(item, false, function(text) return #text <= #least end), least,
        "room for no item: buy… says something must be bought")
    T.eq(CP.Impromptu.Info(item, false, function(text) return #text <= 16 end), "x2  ·  ~2 pts",
        "no room even for that: the count and points alone")end)

T.test("a row that needs vendor goods says so, and Craft waits for them", function()
    scene()
    local r = rowOf(DUSKY_BRACERS)
    T.ok(r ~= nil, "Dusky Bracers lists")
    if not r then return end
    local n = r.item.crafts
    T.eq(r.item.now, 0, "the bags make none before buying")

    local lines = {}
    World.set(GameTooltip, "AddLine", function(_, text) lines[#lines + 1] = tostring(text) end)
    r:GetScript("OnEnter")(r)
    local buy = ("Buy first: %d Black Dye, %d Silken Thread."):format(n, n * 2)
    T.eq(lines[#lines], buy, "the tooltip says what to buy")

    T.eq(r.craft.label:GetText(), "Craft")
    T.ok(not CP.Style.IsOn(r.craft), "Craft is greyed while the goods are missing")
    T.eq(r.craft.tip, ("Need %d more Black Dye, %d more Silken Thread"):format(n, n * 2), "its tip says what is missing")
    local _, before = lastCast()
    CraftWorld.Press(r.craft)
    local _, after = lastCast()
    T.eq(after, before, "a greyed Craft crafts nothing")

    -- Goods for one craft: Craft makes one, selected in Daylight UI's window.
    CraftWorld.SetBag(BLACK_DYE, 1)
    CraftWorld.SetBag(SILKEN_THREAD, 2)
    T.advance(1)
    r = rowOf(DUSKY_BRACERS)
    T.eq(r.item.now, 1, "the bags make one now")
    T.ok(CP.Style.IsOn(r.craft), "Craft is on")
    T.eq(r.craft.count, 1, "it crafts what the bags hold the goods for")
    CraftWorld.Press(r.craft)
    T.eq(lastCast(), r.item.spell, "Craft crafts Dusky Bracers")
    T.eq(DaylightWorld.state.selected, r.item.spell, "and selects it in Daylight UI's window")
end)

T.test("each row's button acts on its own recipe, shut and open", function()
    scene()
    -- Goods for every row, so each Craft is on.
    for _, item in ipairs({ BLACK_DYE, SILKEN_THREAD, FINE_THREAD, GREEN_DYE }) do CraftWorld.SetBag(item, 50) end
    CraftWorld.Close()
    T.advance(1)
    local rows = shownRows()
    T.ok(#rows >= 2, "two rows list")
    if #rows < 2 then return end
    local a, b = rows[1], rows[2]
    local aSpell, bSpell = a.item.spell, b.item.spell
    T.ok(aSpell ~= bSpell, "two recipes")
    T.eq(a.craft.label:GetText() .. "/" .. b.craft.label:GetText(), "Open/Open", "shut, both read Open")
    T.eq(a.craft.recipeID, aSpell, "the first button carries its own recipe")
    T.eq(b.craft.recipeID, bSpell, "the second button carries its own recipe")

    CraftWorld.Press(b.craft)
    CraftWorld.Open(LW)
    T.advance(1)
    T.eq(DaylightWorld.state.selected, bSpell, "Open on the second row selects its recipe")
    T.eq(a.craft.label:GetText() .. "/" .. b.craft.label:GetText(), "Craft/Craft", "open, both read Craft")
    T.advance(W.GUARD_SECONDS + 1)

    T.eq(a.item.spell, aSpell, "the rows keep their recipes")
    CraftWorld.Press(a.craft)
    T.eq(DaylightWorld.state.selected, aSpell, "Craft on the first row selects its recipe")
    T.eq(lastCast(), aSpell, "and crafts it")
    T.advance(1)
    T.eq(DaylightWorld.state.selected, aSpell, "the selection holds")
end)
